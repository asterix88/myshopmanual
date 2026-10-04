"""Copy the manuals' page text into the AI server's search database (D1).

Tanya AI searches on the server, so phones download nothing to ask about a
manual. This reads catalog.json from the manual server, and for every
searchable manual whose search index changed since the last run, downloads
that index (units/<UNIT>/<file>.sqlite, built by build_packages.py) and loads
its pages into the Cloudflare D1 database "mymanual-search". Manuals removed
from the catalog are removed from the database too.

Run by .github/workflows/ai-worker.yml, from the ai-worker folder (it calls
`npx wrangler d1 execute`, which needs CLOUDFLARE_API_TOKEN and
CLOUDFLARE_ACCOUNT_ID). Use --local to fill wrangler's local database for
`npx wrangler dev` instead.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

DATABASE = "mymanual-search"

SCHEMA = """
CREATE TABLE IF NOT EXISTS manuals (
  key TEXT PRIMARY KEY,
  unit_id TEXT NOT NULL,
  unit_name TEXT NOT NULL,
  title TEXT NOT NULL,
  type TEXT NOT NULL,
  index_sha256 TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS pages USING fts5(
  file_key UNINDEXED,
  page UNINDEXED,
  section UNINDEXED,
  text,
  tokenize = 'unicode61 remove_diacritics 2'
);
"""

TYPE_LABELS = {"shop_manual": "Shop Manual", "omm": "OMM", "partsbook": "Partsbook"}

# D1 rejects SQL statements over 100 KB; a page never needs that much.
MAX_PAGE_CHARS = 30_000


def sql_text(value: str | None) -> str:
    if value is None:
        return "NULL"
    return "'" + value.replace("\x00", "").replace("'", "''") + "'"


class D1:
    def __init__(self, local: bool):
        self.target = "--local" if local else "--remote"

    def run(self, *args: str) -> str:
        result = subprocess.run(
            ["npx", "wrangler", "d1", "execute", DATABASE, self.target, "--yes", *args],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout

    def query(self, sql: str) -> list[dict]:
        out = json.loads(self.run("--json", "--command", sql))
        return out[0]["results"] if out else []

    def execute_file(self, sql: str) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as f:
            f.write(sql)
            path = f.name
        try:
            self.run("--file", path)
        finally:
            Path(path).unlink()


def page_rows(index_path: Path) -> list[tuple[int, str | None, str]]:
    """(page, section, text) for every page, section from the PDF bookmarks."""
    db = sqlite3.connect(index_path)
    try:
        toc = db.execute("SELECT page, title FROM toc ORDER BY page, seq").fetchall()
        rows = []
        t = 0
        section = None
        for page, text in db.execute("SELECT CAST(page AS INTEGER), text FROM pages ORDER BY 1"):
            while t < len(toc) and toc[t][0] <= page:
                section = toc[t][1]
                t += 1
            text = " ".join(text.split())
            if text:
                rows.append((page, section, text[:MAX_PAGE_CHARS]))
        return rows
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--server", default="https://mymanual.my.id", help="manual server address")
    parser.add_argument("--local", action="store_true", help="fill wrangler's local database")
    args = parser.parse_args()
    server = args.server.rstrip("/")

    with urllib.request.urlopen(f"{server}/catalog.json", timeout=60) as response:
        catalog = json.load(response)

    d1 = D1(args.local)
    d1.execute_file(SCHEMA)
    known = {row["key"]: row["index_sha256"] for row in d1.query("SELECT key, index_sha256 FROM manuals")}

    wanted = {}
    for unit in catalog.get("units", []):
        for f in unit.get("files", []):
            if f.get("searchable", True):
                wanted[f"{unit['id']}/{f['id']}"] = (unit, f)

    for key in sorted(set(known) - set(wanted)):
        print(f"remove {key}")
        d1.execute_file(
            f"DELETE FROM pages WHERE file_key = {sql_text(key)};\n"
            f"DELETE FROM manuals WHERE key = {sql_text(key)};\n"
        )

    changed = 0
    for key, (unit, f) in sorted(wanted.items()):
        sha = f["index"]["sha256"]
        if known.get(key) == sha:
            continue
        changed += 1
        with tempfile.TemporaryDirectory() as tmp:
            index_path = Path(tmp) / "index.sqlite"
            urllib.request.urlretrieve(f"{server}/{f['index']['path']}", index_path)
            rows = page_rows(index_path)
        print(f"load {key}: {len(rows)} pages")
        # The manuals row goes in last, so a run that fails halfway loads this
        # manual again next time.
        lines = [
            f"DELETE FROM manuals WHERE key = {sql_text(key)};",
            f"DELETE FROM pages WHERE file_key = {sql_text(key)};",
        ]
        lines += [
            f"INSERT INTO pages (file_key, page, section, text) VALUES "
            f"({sql_text(key)}, {page}, {sql_text(section)}, {sql_text(text)});"
            for page, section, text in rows
        ]
        lines.append(
            "INSERT INTO manuals (key, unit_id, unit_name, title, type, index_sha256) VALUES ("
            + ", ".join(
                sql_text(v)
                for v in (
                    key,
                    unit["id"],
                    unit.get("name") or unit["id"],
                    f["title"],
                    TYPE_LABELS.get(f.get("type"), "Lainnya"),
                    sha,
                )
            )
            + ");"
        )
        d1.execute_file("\n".join(lines) + "\n")

    print(f"{len(wanted)} manuals on the server, {changed} loaded, {len(set(known) - set(wanted))} removed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
