"""Where does the Installation part start in each remove & install chapter?
Diagnostic only; prints candidate heading lines per chapter."""
import json, re, sqlite3, sys, urllib.request, collections
sys.path.insert(0, "tools")
import build_packages as bp
BASE = "https://mymanual.my.id/"
def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "MyManual-probe/1.0"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return r.read()
CAND = re.compile(r"^\s*(?:\d+[.)]?\s*)?(?:procedure\s+for\s+)?install(?:ation|ing)?\b.{0,40}$", re.I)
cat = json.loads(get("catalog.json"))
stats = collections.Counter()
for u in cat["units"]:
    for f in u["files"]:
        if f["type"] == "partsbook" or not f.get("searchable", True):
            continue
        open("/tmp/x.sqlite", "wb").write(get(f["index"]["path"]))
        db = sqlite3.connect("/tmp/x.sqlite")
        toc = [list(r) for r in db.execute("SELECT level, title, page FROM toc ORDER BY seq")]
        texts = {int(p): t for p, t in db.execute("SELECT CAST(page AS INTEGER), text FROM pages")}
        db.close()
        n = f["pages"]
        tl = [texts.get(i + 1, "") for i in range(n)]
        parts = bp.part_ranges(toc, n, tl)
        if not parts:
            continue
        print(f"\n=== {u['id']} {f['title']} ({len(parts)} chapters)")
        for p in parts:
            hits = []
            for pg in range(p["page"], p["last"] + 1):
                for line in tl[pg - 1].splitlines():
                    if CAND.match(line):
                        hits.append((pg, line.strip()[:50]))
            stats["found" if hits else "none"] += 1
            print(f"- {p['name']} p{p['page']}-{p['last']} marks={p.get('marks')} :: {hits[:4]}")
print(stats)
