"""How many bytes and requests PDFium needs to open a manual at a page,
read the way the app's RemotePdf does (64 KB pieces, 4 pieces per request)."""
import json, os, sys, time, urllib.request
import pypdfium2 as pdfium
import pypdfium2.raw as raw

BLOCK = 64 * 1024
AHEAD = 4

class Tracer:
    def __init__(self, path):
        self.f = open(path, 'rb')
        self.size = os.path.getsize(path)
        self.have = set()
        self.requests = []  # (first block, count)
    def readinto(self, offset, length):
        first, last = offset // BLOCK, (offset + length - 1) // BLOCK
        for b in range(first, last + 1):
            if b in self.have:
                continue
            n = 1
            while n < AHEAD and (b + n) * BLOCK < self.size and (b + n) not in self.have:
                n += 1
            for x in range(b, b + n):
                self.have.add(x)
            self.requests.append((b, n))
        self.f.seek(offset)
        return self.f.read(length)

def probe(path, pages):
    t = Tracer(path)
    # Custom loader like pdfrx's openCustom.
    import ctypes
    @ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ubyte), ctypes.c_ulong)
    def get_block(_, pos, buf, size):
        data = t.readinto(pos, size)
        ctypes.memmove(buf, data, len(data))
        return 1
    access = raw.FPDF_FILEACCESS()
    access.m_FileLen = t.size
    access.m_GetBlock = get_block
    access.m_Param = None
    doc = raw.FPDF_LoadCustomDocument(ctypes.byref(access), None)
    out = [f'{os.path.basename(path)}: {t.size/1e6:.1f} MB, {raw.FPDF_GetPageCount(doc)} pages']
    out.append(f'  open: {len(t.requests)} requests, {sum(n for _, n in t.requests)*64} KB; '
               f'first blocks {t.requests[:6]} last {t.requests[-3:]}')
    for p in pages:
        before = len(t.requests)
        page = raw.FPDF_LoadPage(doc, p - 1)
        tp = raw.FPDFText_LoadPage(page)
        raw.FPDFText_ClosePage(tp)
        raw.FPDF_ClosePage(page)
        new = t.requests[before:]
        out.append(f'  page {p}: {len(new)} requests, {sum(n for _, n in new)*64} KB, blocks {new[:8]}')
    raw.FPDF_CloseDocument(doc)
    return '\n'.join(out)

def timing(base, key, headers, label):
    lines = []
    size = None
    for i, (start, n) in enumerate([(0, 1), (0, 4), (100, 4), (2000, 4), (200, 1), (2000, 4)]):
        h = dict(headers)
        h['Range'] = f'bytes={start*BLOCK}-{(start+n)*BLOCK-1}'
        h['User-Agent'] = 'MyManual-probe'
        req = urllib.request.Request(f'{base}/{key}', headers=h)
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
                cs = r.headers.get('cf-cache-status')
            lines.append(f'  {label} blocks {start}+{n}: {(time.time()-t0)*1000:.0f} ms, {len(data)//1024} KB, cache {cs}')
        except Exception as e:
            lines.append(f'  {label} blocks {start}+{n}: error {e}')
    return '\n'.join(lines)

if __name__ == '__main__':
    catalog = json.load(open('catalog.json'))
    want = {'PC2000-11R': [1, 1500], 'D155A-6': [1, 1006, 1152], 'PC500LC-10': [1]}
    out = []
    for unit in catalog['units']:
        code = unit.get('code') or unit.get('name')
        for f in unit.get('files', []):
            path = f.get('path', '')
            title = (f.get('title') or path)
            if not any(code and code.startswith(k) for k in want):
                continue
            if 'shop' not in path.lower() and not os.path.basename(path).upper().startswith('SM'):
                continue
            k = next(k for k in want if code.startswith(k))
            local = os.path.basename(path)
            if not os.path.exists(local):
                urllib.request.urlretrieve('https://mymanual.my.id/' + path, local)
            out.append(probe(local, want[k]))
            code_admin = os.environ.get('ADMIN_CODE', '')
            out.append(timing('https://files.mymanual.my.id', path, {'x-admin-code': code_admin}, 'files'))
            out.append(timing('https://mymanual.my.id', path, {}, 'public'))
    print('\n'.join(out))
