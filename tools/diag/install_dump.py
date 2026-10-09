"""Dump lines mentioning install on chosen pages. Diagnostic only."""
import json, re, sqlite3, urllib.request
BASE = "https://mymanual.my.id/"
def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "MyManual-probe/1.0"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return r.read()
WANT = {"D375-6R": [(1299, 1305), (1285, 1289)], "PC2000-11R": [(2594, 2608)], "PC210-1OMO": [(1989, 1993), (2008, 2012)],
        "PC1250SP-11": [(1924, 1930)], "D155A-6": [(1001, 1001)]}
cat = json.loads(get("catalog.json"))
for u in cat["units"]:
    if u["id"] not in WANT:
        continue
    for f in u["files"]:
        if f["type"] != "shop_manual":
            continue
        open("/tmp/x.sqlite", "wb").write(get(f["index"]["path"]))
        db = sqlite3.connect("/tmp/x.sqlite")
        texts = {int(p): t for p, t in db.execute("SELECT CAST(page AS INTEGER), text FROM pages")}
        for a, b in WANT[u["id"]]:
            print(f"\n=== {u['id']} {f['title']} p{a}-{b}")
            for n in range(a, b + 1):
                for line in texts.get(n, "").splitlines():
                    if re.search(r"nstall|NSTALL|emoval|EMOVAL", line):
                        print(f"  p{n}: {line.strip()[:80]!r}")
