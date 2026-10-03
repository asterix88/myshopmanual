#!/usr/bin/env python3
"""Search downloaded manuals the same way the app will, and time it.

Each manual has its own <file>.sqlite index, so this searches every index
found under the given folders (= whatever is downloaded on the phone).

    python tools/search.py dist/units "hydraulic oil"
    python tools/search.py dist/units/PC210 "track tension"
"""

import sqlite3
import sys
import time
from pathlib import Path


def to_fts_query(text: str) -> str:
    # Every word must match; the last word also matches as a prefix
    # so results appear while the mechanic is still typing.
    words = [w.replace('"', "") for w in text.split() if w.strip('"')]
    if not words:
        return ""
    terms = [f'"{w}"' for w in words[:-1]] + [f'"{words[-1]}"*']
    return " ".join(terms)


SEARCH_SQL = """
SELECT page, bm25(pages) AS rank,
       snippet(pages, 1, '[', ']', '…', 12) AS snip,
       (SELECT title FROM toc WHERE toc.page <= pages.page
        ORDER BY toc.page DESC, toc.seq DESC LIMIT 1) AS section
FROM pages
WHERE pages MATCH ?
ORDER BY rank
LIMIT 50
"""


def search(index_paths: list[Path], text: str) -> tuple[list[tuple], int]:
    query = to_fts_query(text)
    hits, total = [], 0
    for path in index_paths:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        title = db.execute("SELECT value FROM meta WHERE key = 'title'").fetchone()[0]
        for page, rank, snip, section in db.execute(SEARCH_SQL, (query,)):
            hits.append((rank, title, page, section, snip))
        total += db.execute("SELECT count(*) FROM pages WHERE pages MATCH ?", (query,)).fetchone()[0]
        db.close()
    hits.sort(key=lambda h: h[0])
    return hits, total


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    indexes = sorted(Path(sys.argv[1]).rglob("*.sqlite"))
    started = time.perf_counter()
    hits, total = search(indexes, " ".join(sys.argv[2:]))
    elapsed = (time.perf_counter() - started) * 1000
    for _, title, page, section, snip in hits[:8]:
        print(f"{title}  p.{page}  [{section}]\n    {' '.join(snip.split())}")
    print(f"{total} pages matched across {len(indexes)} files in {elapsed:.1f} ms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
