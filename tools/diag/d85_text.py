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
for page, text in db.execute("SELECT page, text FROM pages WHERE page IN (467,468,471,472,479,480,481,482)"):
    print(f"==== p{page}")
    print(text[:2500])
