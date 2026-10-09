"""Torsi list: every remove & install chapter per unit with its torque count,
as build_packages.py would write it. Diagnostic only; writes tools/diag/torsi.json."""
import json, sqlite3, sys, urllib.request
sys.path.insert(0, "tools")
import build_packages as bp
BASE = "https://mymanual.my.id/"
def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "MyManual-probe/1.0"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return r.read()
cat = json.loads(get("catalog.json"))
out = {}
for u in cat["units"]:
    for f in u["files"]:
        if f["type"] == "partsbook":
            continue
        path = "/tmp/x.sqlite"
        open(path, "wb").write(get(f["index"]["path"]))
        db = sqlite3.connect(path)
        toc = [list(r) for r in db.execute("SELECT level, title, page FROM toc ORDER BY seq")]
        n = f["pages"]
        texts = [""] * n
        for page, text in db.execute("SELECT page, text FROM pages"):
            if 1 <= int(page) <= n:
                texts[int(page) - 1] = text
        parts = bp.part_ranges(toc, n, texts)
        if parts:
            out.setdefault(u["id"], []).extend(
                {"file": f["id"], "group": p["group"], "name": p["name"], "page": p["page"],
                 "pages": p["last"] - p["page"] + 1, "torque": p["torque"]} for p in parts)
        db.close()
json.dump(out, open("tools/diag/torsi.json", "w"), indent=1, ensure_ascii=False)
for k, v in out.items():
    print(k, len(v), sum(1 for p in v if p["torque"]))
