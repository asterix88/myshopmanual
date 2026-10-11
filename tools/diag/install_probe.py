"""Servis probe: bookmarks and service_ranges for the PC2000 OMM."""
import json, sqlite3, sys, urllib.request
sys.path.insert(0, "tools")
import build_packages as bp
BASE = "https://mymanual.my.id/"
def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "MyManual-probe/1.0"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return r.read()
cat = json.loads(get("catalog.json"))
for u in cat["units"]:
    for f in u["files"]:
        if f["type"] != "omm" and "OMM" not in f["title"].upper():
            continue
        open("/tmp/x.sqlite", "wb").write(get(f["index"]["path"]))
        db = sqlite3.connect("/tmp/x.sqlite")
        toc = [list(r) for r in db.execute("SELECT level, title, page FROM toc ORDER BY seq")]
        texts = {int(p): t for p, t in db.execute("SELECT CAST(page AS INTEGER), text FROM pages")}
        db.close()
        n = f["pages"]
        tl = [texts.get(i + 1, "") for i in range(n)]
        print(f"\n=== {u['id']} {f['title']}")
        if u["id"].startswith("PC2000"):
            on = False
            for lv, t, p in toc:
                if "MAINTENANCE SCHEDULE" in t.upper(): on = True
                if on: print(f"  toc L{lv} p{p} {t}")
                if on and "9000" in t: on = False
            for pg in (443, 444, 451, 452):
                print(f"--- text p{pg}\n{tl[pg-1][:1500]}")
        spec = u.get("spec") or {}
        print("catalog service:", [(e["hours"], e["title"][:50], e["item"]) for e in spec.get("service", [])][:60])
        for e in bp.service_ranges(toc, n, tl):
            print(f"  svc {e['hours']} item={e['item']} p{e['page']}-{e['last']} {e['title']}")
