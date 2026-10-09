"""Torsi probe: Shop Manual bookmark trees, remove & install chapters and the
torque values PDFium finds in them. Diagnostic only; writes tools/diag/torsi/."""
import json, os, re, sqlite3, sys, urllib.request
sys.path.insert(0, "tools")
import build_packages as bp
import pypdfium2 as pdfium

BASE = "https://mymanual.my.id/"
def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "MyManual-probe/1.0"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return r.read()

# Same as app/lib/src/screens/viewer_screen.dart torqueValue.
TORQUE = re.compile(r"\d[\d.,]*\s*(?:[-–~]\s*\d[\d.,]*\s*)?(?:N\s*[·.•]?\s*m|kgf?\s*[·.•]?\s*m|lbf?\s*[·.•]?\s*ft)(?![a-z])", re.I)
LOOSE = re.compile(r"torque|tighten|N\W{0,2}m\b|kg\W{0,2}m\b|lbf?\W{0,2}ft", re.I)

out = "tools/diag/torsi"
os.makedirs(out, exist_ok=True)
os.makedirs("probe", exist_ok=True)
cat = json.loads(get("catalog.json"))
summary = []
for u in cat["units"]:
    for f in u["files"]:
        if f["type"] != "sm":
            continue
        name = f"{u['id']}-{f['id']}"[:80]
        idx = f"probe/{name}.sqlite"
        open(idx, "wb").write(get(f["index"]["path"]))
        db = sqlite3.connect(idx)
        toc = [list(r) for r in db.execute("SELECT level, title, page FROM toc ORDER BY seq")]
        n = f["pages"]
        texts = {int(p): t for p, t in db.execute("SELECT page, text FROM pages")}
        parts = bp.part_ranges(toc, n)
        w = open(f"{out}/{name}.txt", "w")
        w.write(f"{u['id']} | {f['title']} | pages {n} | bookmarks {len(toc)} | parts {len(parts)}\n\n")
        w.write("=== BOOKMARKS (levels 1-3) ===\n")
        for lvl, t, p in toc:
            if lvl <= 3:
                w.write(f"{'  ' * (lvl - 1)}{t}  [p{p}]\n")
        pdf = None
        try:
            path = f"probe/{name}.pdf"
            open(path, "wb").write(get(f["pdf"]["path"]))
            pdf = pdfium.PdfDocument(path)
        except Exception as e:
            w.write(f"\nPDF download failed: {e}\n")
        w.write("\n=== REMOVE & INSTALL CHAPTERS ===\n")
        hit = miss = 0
        for prt in parts:
            found, loose_only = [], []
            for pg in range(prt["page"], prt["last"] + 1):
                if pdf is None or pg > len(pdf):
                    continue
                txt = pdf[pg - 1].get_textpage().get_text_range()
                ms = [m.group(0) for m in TORQUE.finditer(txt)]
                found += [f"p{pg}: {x!r}" for x in ms]
                if not ms:
                    for line in txt.splitlines():
                        if LOOSE.search(line):
                            loose_only.append(f"p{pg}: {line.strip()[:140]!r}")
                fts = texts.get(pg, "")
                if not ms and TORQUE.search(fts):
                    loose_only.append(f"p{pg}: INDEX TEXT HAS TORQUE BUT PDFIUM NOT: {TORQUE.search(fts).group(0)!r}")
            hit += bool(found)
            miss += not found
            w.write(f"\n[{prt['group']}] {prt['name']}  p{prt['page']}-{prt['last']}  <- {prt['title']!r}\n")
            w.write(f"   torque matches: {len(found)}\n")
            for x in found[:6]:
                w.write(f"     + {x}\n")
            for x in loose_only[:10]:
                w.write(f"     ? {x}\n")
            if not found and pdf is not None and prt["page"] <= len(pdf):
                txt = pdf[prt["page"] - 1].get_textpage().get_text_range()
                w.write("     raw p%d: %r\n" % (prt["page"], txt[:900]))
        summary.append(f"{name}: parts {len(parts)}, with torque {hit}, without {miss}")
        w.close()
        if pdf is not None:
            pdf.close()
            os.remove(f"probe/{name}.pdf")
print("\n".join(summary))
