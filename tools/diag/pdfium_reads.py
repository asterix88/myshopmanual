"""How many 64 KB pieces PDFium reads to show far pages of a manual, as
the app reads it online: the original file, and the same file rewritten
with qpdf object streams (page dictionaries packed together)."""
import io, json, subprocess, sys, time
import pikepdf, pypdfium2 as pdfium

BASE = 'https://mymanual.my.id/'
BS = 64 * 1024


class Counting(io.RawIOBase):
    def __init__(self, path):
        self.f = open(path, 'rb'); self.size = self.f.seek(0, 2); self.f.seek(0); self.blocks = set(); self.reads = 0
    def readable(self): return True
    def seekable(self): return True
    def seek(self, pos, whence=0): return self.f.seek(pos, whence)
    def tell(self): return self.f.tell()
    def readinto(self, b):
        pos = self.f.tell(); n = self.f.readinto(b); self.reads += 1
        for blk in range(pos // BS, (pos + max(n, 1) - 1) // BS + 1): self.blocks.add(blk)
        return n


def run(path, pages):
    src = Counting(path)
    doc = pdfium.PdfDocument(src)
    out = [f'open: {len(src.blocks)} pieces']
    for n in pages:
        before = len(src.blocks); t = time.time()
        page = doc[n - 1]; page.get_size(); tp = page.get_textpage(); tp.count_chars()
        out.append(f'p{n}: +{len(src.blocks) - before} pieces ({(len(src.blocks) - before) * 64 // 1024} MB)')
    return out


cat = json.loads(subprocess.run(['curl', '-sS', '-A', 'MyManual-probe', BASE + 'catalog.json'], capture_output=True, text=True, check=True).stdout)
for want in sys.argv[1:]:
    f = next(f for u in cat['units'] for f in u['files'] if want.lower() in (u.get('name', '') + ' ' + f['title']).lower() and 'shop' in (f.get('type') or '').lower())
    subprocess.run(['curl', '-sS', '-A', 'MyManual-probe', '-o', '/tmp/a.pdf', BASE + f['pdf']['path']], check=True)
    pdf = pikepdf.open('/tmp/a.pdf')
    root = pdf.Root.Pages
    print(f"\n===== {f['title']} pages {len(pdf.pages)} top-level kids {len(root.Kids)}")
    pages = [1, 10, 722, 849, 1250, 1251, len(pdf.pages) - 10]
    print('ORIGINAL', run('/tmp/a.pdf', pages))
    pdf.save('/tmp/b.pdf', object_stream_mode=pikepdf.ObjectStreamMode.generate, linearize=False)
    import os
    print('OBJSTM size', os.path.getsize('/tmp/a.pdf') // 2**20, '->', os.path.getsize('/tmp/b.pdf') // 2**20, 'MB')
    print('OBJSTM  ', run('/tmp/b.pdf', pages))
