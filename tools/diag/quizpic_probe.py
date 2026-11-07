"""Quiz picture probe: how pdfium sees page 187 of the CAT395 System Operation
manual (page size, boxes, text and char boxes), and the page drawn with the
word boxes covered the way the app does it."""
import json, sys, urllib.request
import pypdfium2 as pdfium
import pypdfium2.raw as raw
from PIL import ImageDraw

BASE = "https://mymanual.my.id/"
def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "MyManual-probe/1.0"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return r.read()

# The workflow fetched catalog.json and the PDF from the bucket (wrangler).
doc = pdfium.PdfDocument("/tmp/so.pdf")
PAGE = int(sys.argv[1]) if len(sys.argv) > 1 else 187
page = doc[PAGE - 1]
w, h = page.get_size()
print("size", w, h, "rotation", page.get_rotation())
print("mediabox", page.get_mediabox(), "cropbox", page.get_cropbox(), "bbox", page.get_bbox())
tp = page.get_textpage()
n = tp.count_chars()
text = "".join(chr(raw.FPDFText_GetUnicode(tp, i)) for i in range(n))
print("chars", n, "text len", len(text))
boxes = [tp.get_charbox(i) for i in range(n)]  # (l, b, r, t)
for i in range(0, min(n, 2000)):
    print(i, repr(text[i]), [round(v, 1) for v in boxes[i]])
scale = 1600 / max(w, h)
img = page.render(scale=scale).to_pil().convert("RGB")
img.save("tools/diag/p_plain.png")
d = ImageDraw.Draw(img)
bl, bb = page.get_bbox()[0], page.get_bbox()[1]
start = -1
def close(e):
    global start
    if start < 0: return
    word = text[start:e]
    if any(c.isalpha() for c in word):
        l = min(boxes[i][0] for i in range(start, e)); r = max(boxes[i][2] for i in range(start, e))
        b = min(boxes[i][1] for i in range(start, e)); t = max(boxes[i][3] for i in range(start, e))
        # The app's pdfrx subtracts the page bbox origin.
        l -= bl; r -= bl; b -= bb; t -= bb
        d.rectangle([l * scale, (h - t) * scale, r * scale, (h - b) * scale], outline=(255, 0, 0))
    start = -1
for i in range(n):
    if text[i].strip() == "":
        close(i)
    elif start < 0:
        start = i
close(n)
img.save("tools/diag/p_boxes.png")
print("done")
