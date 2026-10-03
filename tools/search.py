#!/usr/bin/env python3
"""Query a unit's index.sqlite the same way the app will, and time it.

    python tools/search.py dist/units/PC210/index.sqlite "hydraulic oil"
"""

import sqlite3
import sys
import time


def to_fts_query(text: str) -> str:
    # Every word must match; the last word also matches as a prefix
    # so results appear while the mechanic is still typing.
    words = [w.replace('"', "") for w in text.split() if w.strip('"')]
    if not words:
        return ""
    terms = [f'"{w}"' for w in words[:-1]] + [f'"{words[-1]}"*']
    return " ".join(terms)


SEARCH_SQL = """
SELECT d.title, p.page,
       snippet(pages, 2, '[', ']', '…', 12) AS snip
FROM pages p JOIN docs d ON d.id = p.doc_id
WHERE pages MATCH ?
ORDER BY bm25(pages)
LIMIT 50
"""


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    db = sqlite3.connect(sys.argv[1])
    query = to_fts_query(" ".join(sys.argv[2:]))
    started = time.perf_counter()
    rows = db.execute(SEARCH_SQL, (query,)).fetchall()
    total = db.execute("SELECT count(*) FROM pages WHERE pages MATCH ?", (query,)).fetchone()[0]
    elapsed = (time.perf_counter() - started) * 1000
    for title, page, snip in rows[:10]:
        print(f"{title}  p.{page}: {' '.join(snip.split())}")
    print(f"{total} pages matched in {elapsed:.1f} ms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
