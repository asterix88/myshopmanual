"""Torsi evidence: for each remove & install chapter, the torque lines and
page pictures (torque lines marked yellow). Diagnostic only; writes tools/diag/ev/."""
import json, os, sqlite3, sys, urllib.request
sys.path.insert(0, "tools")
import build_packages as bp
import pymupdf
BASE = "https://mymanual.my.id/"
def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "MyManual-probe/1.0"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return r.read()
OUT = "tools/diag/ev"
os.makedirs(OUT, exist_ok=True)
cat = json.loads(get("catalog.json"))
result, total = {}, 0
for u in cat["units"]:
    for f in u["files"]:
        if f["type"] == "partsbook" or not f.get("searchable", True):
            continue
        open("/tmp/x.sqlite", "wb").write(get(f["index"]["path"]))
        db = sqlite3.connect("/tmp/x.sqlite")
        toc = [list(r) for r in db.execute("SELECT level, title, page FROM toc ORDER BY seq")]
        db.close()
        n = f["pages"]
        if not bp.part_ranges(toc, n):
            continue
        open("/tmp/x.pdf", "wb").write(get(f["pdf"]["path"]))
        doc = pymupdf.open("/tmp/x.pdf")
        texts = [doc[i].get_text() for i in range(len(doc))]
        parts = bp.part_ranges(toc, n, texts)
        udir = f"{OUT}/{u['id']}"
        os.makedirs(udir, exist_ok=True)
        rows = []
        for k, p in enumerate(parts):
            lines, pics = [], []
            for pg in range(p["page"], p["last"] + 1):
                page = doc[pg - 1]
                tl = bp.torque_lines(texts[pg - 1])
                lines += [{"page": pg, "text": t} for t in tl]
                if p["torque"] and not tl:
                    continue  # chapters with torque: only the pages that hold it
                if not p["torque"] and len(pics) >= 15:
                    continue
                for t in tl:
                    for r in page.search_for(t):
                        page.draw_rect(r + (-2, -2, 2, 2), color=None, fill=(1, 0.84, 0), fill_opacity=0.45, overlay=True)
                pix = page.get_pixmap(matrix=pymupdf.Matrix(560 / page.rect.width, 560 / page.rect.width))
                name = f"{k:03d}-{pg}.jpg"
                pix.save(f"{udir}/{name}", jpg_quality=55)
                total += os.path.getsize(f"{udir}/{name}")
                pics.append({"page": pg, "img": f"ev/{u['id']}/{name}"})
            rows.append({"group": p["group"], "name": p["name"], "title": p["title"], "page": p["page"], "last": p["last"],
                         "torque": p["torque"], "lines": lines, "pics": pics})
        result.setdefault(u["id"], {"file": f["title"], "parts": []})["parts"] += rows
        doc.close()
json.dump(result, open(f"{OUT}/evidence.json", "w"), ensure_ascii=False, indent=0)
print("images MB", round(total / 1e6, 1))
for k, v in result.items():
    print(k, len(v["parts"]), sum(1 for p in v["parts"] if p["torque"]))
# v2
