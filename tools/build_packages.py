#!/usr/bin/env python3
"""Build per-unit download packages for MyShopManual.

Input layout (one folder per unit model, PDFs inside):

    source/
      PC210/  Shop Manual PC210.pdf, OMM PC210.pdf, Partsbook PC210.pdf
      D85/    ...

Output layout (what gets uploaded to Cloudflare R2):

    dist/
      catalog.json                  list of units, files, sizes, hashes, versions
      units/PC210/<file>.pdf        PDFs copied as-is
      units/PC210/index.sqlite      full-text search index (SQLite FTS5)

Scanned PDFs (no text layer) are skipped by default, since they cannot be
searched; pass --include-scanned to ship them without search.
"""

import argparse
import hashlib
import json
import re
import shutil
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import pymupdf

# A page with fewer extracted characters than this is treated as image-only.
MIN_CHARS_PER_PAGE = 40
# A PDF is "scanned" when fewer than this share of its pages carry text.
MIN_TEXT_PAGE_RATIO = 0.5

DOC_TYPES = [
    ("shop_manual", re.compile(r"shop\s*manual|\bsm\b|\bsen\d", re.I)),
    ("omm", re.compile(r"\bomm\b|operation|\bpen\d", re.I)),
    ("partsbook", re.compile(r"part", re.I)),
]


def guess_doc_type(name: str) -> str:
    for doc_type, pattern in DOC_TYPES:
        if pattern.search(name):
            return doc_type
    return "other"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def slugify(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("_")


def extract_pages(pdf_path: Path) -> list[str]:
    with pymupdf.open(pdf_path) as doc:
        return [page.get_text("text") for page in doc]


def is_scanned(pages: list[str]) -> bool:
    if not pages:
        return True
    text_pages = sum(1 for t in pages if len(t.strip()) >= MIN_CHARS_PER_PAGE)
    return text_pages / len(pages) < MIN_TEXT_PAGE_RATIO


def create_index(path: Path) -> sqlite3.Connection:
    path.unlink(missing_ok=True)
    db = sqlite3.connect(path)
    db.executescript(
        """
        CREATE TABLE docs (
          id INTEGER PRIMARY KEY,
          file TEXT NOT NULL,
          title TEXT NOT NULL,
          type TEXT NOT NULL,
          page_count INTEGER NOT NULL
        );
        -- One row per PDF page. doc_id/page are stored but not tokenized.
        CREATE VIRTUAL TABLE pages USING fts5(
          doc_id UNINDEXED,
          page UNINDEXED,
          text,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        """
    )
    return db


def build_unit(unit_dir: Path, out_dir: Path, include_scanned: bool) -> dict:
    unit_id = unit_dir.name
    unit_out = out_dir / "units" / unit_id
    unit_out.mkdir(parents=True, exist_ok=True)
    index_path = unit_out / "index.sqlite"
    db = create_index(index_path)

    files, skipped = [], []
    for doc_id, pdf in enumerate(sorted(unit_dir.glob("*.pdf")), start=1):
        pages = extract_pages(pdf)
        scanned = is_scanned(pages)
        if scanned and not include_scanned:
            skipped.append(pdf.name)
            print(f"  skip (scanned): {pdf.name}")
            continue

        file_name = slugify(pdf.name)
        target = unit_out / file_name
        shutil.copy2(pdf, target)
        title = pdf.stem
        doc_type = guess_doc_type(pdf.name)

        db.execute(
            "INSERT INTO docs (id, file, title, type, page_count) VALUES (?, ?, ?, ?, ?)",
            (doc_id, file_name, title, doc_type, len(pages)),
        )
        if not scanned:
            db.executemany(
                "INSERT INTO pages (doc_id, page, text) VALUES (?, ?, ?)",
                ((doc_id, n, text) for n, text in enumerate(pages, start=1)),
            )

        files.append(
            {
                "id": doc_id,
                "title": title,
                "type": doc_type,
                "path": f"units/{unit_id}/{file_name}",
                "size": target.stat().st_size,
                "sha256": sha256_of(target),
                "pages": len(pages),
                "searchable": not scanned,
            }
        )
        print(f"  {doc_type:12} {len(pages):5} pages  {pdf.name}")

    db.execute("INSERT INTO pages(pages) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()

    index = {
        "path": f"units/{unit_id}/index.sqlite",
        "size": index_path.stat().st_size,
        "sha256": sha256_of(index_path),
    }
    total = sum(f["size"] for f in files) + index["size"]
    return {
        "id": unit_id,
        "name": unit_id,
        "size": total,
        "files": files,
        "index": index,
        "skipped_scanned": skipped,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path, help="folder with one subfolder per unit")
    parser.add_argument("dist", type=Path, help="output folder to upload")
    parser.add_argument("--only", nargs="*", help="build only these unit ids")
    parser.add_argument("--include-scanned", action="store_true")
    args = parser.parse_args()

    unit_dirs = sorted(d for d in args.source.iterdir() if d.is_dir())
    if args.only:
        unit_dirs = [d for d in unit_dirs if d.name in args.only]
    if not unit_dirs:
        print("no unit folders found", file=sys.stderr)
        return 1

    args.dist.mkdir(parents=True, exist_ok=True)
    units = []
    for unit_dir in unit_dirs:
        print(f"[{unit_dir.name}]")
        started = time.time()
        units.append(build_unit(unit_dir, args.dist, args.include_scanned))
        print(f"  done in {time.time() - started:.1f}s, {units[-1]['size'] / 1e6:.1f} MB")

    catalog = {
        "schema": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "units": units,
    }
    (args.dist / "catalog.json").write_text(json.dumps(catalog, indent=2))
    print(f"wrote {args.dist / 'catalog.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
