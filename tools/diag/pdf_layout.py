"""Where a manual's objects live in the file: how many 1 MB blocks (pdfrx's
range block size) the viewer must fetch to read the outline or one page."""
import json, re, subprocess, sys, urllib.request
import pikepdf

BASE = 'https://mymanual.my.id/'
cat = json.loads(subprocess.run(['curl', '-sS', '-A', 'MyManual-probe', BASE + 'catalog.json'], capture_output=True, text=True, check=True).stdout)


def files():
    for u in cat.get('units', []):
        for f in u.get('files', []):
            yield u, f


def xref_offsets(path):
    out = subprocess.run(['qpdf', '--show-xref', path], capture_output=True, text=True).stdout
    off, comp = {}, {}
    for line in out.splitlines():
        m = re.match(r'(\d+)/(\d+): uncompressed; offset = (\d+)', line)
        if m:
            off[int(m[1])] = int(m[3]); continue
        m = re.match(r'(\d+)/(\d+): compressed; stream number = (\d+)', line)
        if m:
            comp[int(m[1])] = int(m[3])
    return off, comp


def blocks_of(objs, off, comp, size):
    b = set()
    for o in objs:
        pos = off.get(o)
        if pos is None and o in comp:
            pos = off.get(comp[o])
        if pos is not None:
            b.add(pos // size)
    return b


def reach(obj, seen, skip_parent=True):
    stack = [obj]
    while stack:
        x = stack.pop()
        if isinstance(x, pikepdf.Object) and x.is_indirect:
            if x.objgen[0] in seen: continue
            seen.add(x.objgen[0])
        if isinstance(x, (pikepdf.Dictionary, pikepdf.Stream)):
            for k in x.keys():
                if skip_parent and k in ('/Parent', '/P', '/Prev', '/Next', '/First', '/Last', '/Dest', '/A', '/Annots', '/StructParents'):
                    continue
                stack.append(x[k])
        elif isinstance(x, pikepdf.Array):
            stack.extend(list(x))
    return seen


def outline_objs(pdf):
    seen = set()
    root = pdf.Root.get('/Outlines')
    if root is None: return seen
    stack = [root]
    while stack:
        x = stack.pop()
        if x.objgen[0] in seen: continue
        seen.add(x.objgen[0])
        for k in ('/First', '/Next'):
            if k in x: stack.append(x[k])
    return seen


for want in sys.argv[1:]:
    hit = [(u, f) for u, f in files() if want.lower() in (u.get('name', '') + ' ' + f.get('title', '')).lower()
           and 'shop' in f.get('type', f.get('title', '')).lower()]
    if not hit:
        print('no file for', want, [ (u.get('name'), f.get('title')) for u, f in files()][:40]); continue
    u, f = hit[0]
    url = BASE + f['pdf']['path']
    print(f"\n===== {u.get('name')} · {f.get('title')} · {f['pdf'].get('size', 0)/1e6:.0f} MB · {url}")
    subprocess.run(['curl', '-sS', '-A', 'MyManual-probe', '-o', '/tmp/m.pdf', url], check=True)
    pdf = pikepdf.open('/tmp/m.pdf')
    print('pages', len(pdf.pages), 'linearized', pdf.is_linearized, 'pdf version', pdf.pdf_version)
    off, comp = xref_offsets('/tmp/m.pdf')
    print('objects uncompressed', len(off), 'in object streams', len(comp))
    for size, name in ((1 << 20, '1MB'), (1 << 16, '64KB')):
        o = outline_objs(pdf)
        b = blocks_of(o, off, comp, size)
        print(f'[{name}] outline items {len(o)} -> blocks {len(b)}')
    for n in [1, 2, 3, 4, 5, 6, 10, 50, 78, 500, 1500]:
        if n > len(pdf.pages): continue
        objs = reach(pdf.pages[n - 1].obj, set())
        b1 = blocks_of(objs, off, comp, 1 << 20)
        b64 = blocks_of(objs, off, comp, 1 << 16)
        print(f'page {n}: objects {len(objs)} -> 1MB blocks {len(b1)} {sorted(b1)[:12]} | 64KB blocks {len(b64)}')
    # pages tree nodes needed to find page N
    print('xref/trailer near end?', max(off.values()) // (1 << 20), 'of', f['pdf'].get('size', 0) // (1 << 20))
