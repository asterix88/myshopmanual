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
      units/PC210/<file>.sqlite     that file's search index + bookmarks

Every file has its own index, so a mechanic can download (and delete) one
manual at a time and search still works over whatever is on the phone.
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


def extract(pdf_path: Path) -> tuple[list[str], list[list]]:
    """Per-page text and the PDF's own bookmarks as [level, title, page]."""
    with pymupdf.open(pdf_path) as doc:
        pages = [page.get_text("text") for page in doc]
        toc = [[lvl, title.strip(), page] for lvl, title, page in doc.get_toc()]
    return pages, toc


def is_scanned(pages: list[str]) -> bool:
    if not pages:
        return True
    text_pages = sum(1 for t in pages if len(t.strip()) >= MIN_CHARS_PER_PAGE)
    return text_pages / len(pages) < MIN_TEXT_PAGE_RATIO


def write_index(path: Path, title: str, doc_type: str, pages: list[str],
                toc: list[list], searchable: bool) -> None:
    path.unlink(missing_ok=True)
    db = sqlite3.connect(path)
    db.executescript(
        """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        -- The PDF's own bookmarks, kept so search results can say which
        -- section a hit is in.
        CREATE TABLE toc (
          seq INTEGER PRIMARY KEY,
          level INTEGER NOT NULL,
          title TEXT NOT NULL,
          page INTEGER NOT NULL
        );
        -- One row per PDF page; page is stored but not tokenized.
        CREATE VIRTUAL TABLE pages USING fts5(
          page UNINDEXED,
          text,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        """
    )
    db.executemany(
        "INSERT INTO meta VALUES (?, ?)",
        [("schema", "1"), ("title", title), ("type", doc_type),
         ("page_count", str(len(pages))), ("searchable", str(int(searchable)))],
    )
    db.executemany("INSERT INTO toc (level, title, page) VALUES (?, ?, ?)", toc)
    if searchable:
        db.executemany(
            "INSERT INTO pages (page, text) VALUES (?, ?)",
            ((n, text) for n, text in enumerate(pages, start=1)),
        )
        db.execute("INSERT INTO pages(pages) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()


def file_entry(path: Path, rel: str) -> dict:
    return {"path": rel, "size": path.stat().st_size, "sha256": sha256_of(path)}


def build_unit(unit_dir: Path, out_dir: Path, include_scanned: bool) -> dict:
    unit_id = unit_dir.name
    unit_out = out_dir / "units" / unit_id
    unit_out.mkdir(parents=True, exist_ok=True)

    files, skipped = [], []
    for pdf in sorted(unit_dir.glob("*.pdf")):
        pages, toc = extract(pdf)
        scanned = is_scanned(pages)
        if scanned and not include_scanned:
            skipped.append(pdf.name)
            print(f"  skip (scanned): {pdf.name}")
            continue

        file_id = slugify(pdf.stem)
        title = pdf.stem
        doc_type = guess_doc_type(pdf.name)
        target = unit_out / f"{file_id}.pdf"
        index_path = unit_out / f"{file_id}.sqlite"
        shutil.copy2(pdf, target)
        write_index(index_path, title, doc_type, pages, toc, not scanned)

        pdf_info = file_entry(target, f"units/{unit_id}/{target.name}")
        index_info = file_entry(index_path, f"units/{unit_id}/{index_path.name}")
        files.append(
            {
                "id": file_id,
                "title": title,
                "type": doc_type,
                "pages": len(pages),
                "bookmarks": len(toc),
                "searchable": not scanned,
                "pdf": pdf_info,
                "index": index_info,
                # What the app shows as the download size for this file.
                "download_size": pdf_info["size"] + index_info["size"],
            }
        )
        print(
            f"  {doc_type:12} {len(pages):5} pages {len(toc):4} bookmarks  "
            f"pdf {pdf_info['size'] / 1e6:.1f} MB + index {index_info['size'] / 1e6:.1f} MB  {pdf.name}"
        )

    return {
        "id": unit_id,
        "name": unit_id,
        "size": sum(f["download_size"] for f in files),
        "files": files,
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
