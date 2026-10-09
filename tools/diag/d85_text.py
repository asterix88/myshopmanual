"""D85 torque text probe. Diagnostic only."""
import json, sqlite3, urllib.request, re
BASE = "https://mymanual.my.id/"
def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "MyManual-probe/1.0"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return r.read()
cat = json.loads(get("catalog.json"))
u = next(u for u in cat["units"] if u["id"].startswith("D85"))
f = next(f for f in u["files"] if f["type"] == "shop_manual")
open("/tmp/d.sqlite", "wb").write(get(f["index"]["path"]))
db = sqlite3.connect("/tmp/d.sqlite")
print("searchable", f.get("searchable"), "pages", f["pages"])
rows = list(db.execute("SELECT page, text FROM pages"))
print("rows", len(rows), "nonempty", sum(1 for _, t in rows if t and t.strip()))
for page, text in rows:
    if int(page) not in (467, 468, 471, 472, 479, 480, 481, 482):
        continue
    print(f"==== p{page}")
    print(text[:2500])
