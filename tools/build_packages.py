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
A unit folder may hold an optional unit.json with display info, e.g.
{"name": "PC210-10M0", "kind": "Excavator"}. PDFs may also sit in
subfolders of a unit folder (source/CAT395/System Diagram/x.pdf): they
belong to that unit, and the subfolder name becomes the file's "group"
("A / B" for a folder inside a folder). The app shows each subfolder as a
folder at the top of the unit page that opens on its own page.

Re-running keeps the previous catalog.json in dist/: units not rebuilt
(with --only) stay listed, and each file keeps its "updated_at" date until
its PDF actually changes. The app uses those dates to show what is new.

Each unit also gets units/<UNIT>/spek.pdf: the pages its manuals bookmark
as bolt torque, refill capacities, standard values and pressures, or the
maintenance schedule (chart and every-N-hours service items), cut
into one small PDF that the app keeps on the phone for its Spek tab (the
catalog's unit "spec" lists those pages). The bookmark titles are matched
with SPEC_SECTIONS below.

PDFs with little or no text layer (scans, wiring and hydraulic diagrams)
are shipped too, marked as not searchable: they open and keep their
bookmarks, but search and Tanya AI skip them. Pass --skip-scanned to leave
them out instead.
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

# Spek tab sections and the bookmark titles that belong to them. Keep in
# step with specSections in app/lib/src/specs.dart (used for catalogs built
# before spek.pdf existed).
SPEC_SECTIONS = [
    re.compile(r"tightening torque|torque (table|chart|spec)", re.I),
    re.compile(
        r"(fuel|coolant|lubricant|oil)s?[^/]*capacit|capacit[^/]*(fuel|coolant|lubricant|oil|refill)|refill capacit"
        r"|table of fuel|fuel, coolant and lubricants",
        re.I,
    ),
    re.compile(
        r"standard value|relief (valve|pressure)[^/]*(test|adjust|measur)|pressure[^/]*(test|adjust|setting)"
        r"|testing and adjusting.*pressure",
        re.I,
    ),
]
SPEC_SECTION_TITLES = ["Torsi baut", "Kapasitas oli & cairan", "Nilai standar & tekanan"]
# Servis tab: bookmarks of the maintenance schedule. "EVERY 500 HOURS
# SERVICE" opens a tab HM 500 listing the items under it; the schedule chart
# itself shows on every tab.
SERVICE_INTERVAL = re.compile(
    r"\b(?:every|initial)?\s*([\d.,]{3,7})\s*(?:hours?|hrs?|h|hm|smr)\b[^/]*?\b(?:service|maintenance)\b", re.I)
SERVICE_CHART = re.compile(
    r"maintenance (?:schedule|interval)s?(?: chart| table| list)?$|periodic maintenance (?:chart|table|schedule)"
    r"|maintenance (?:chart|table)", re.I)
# Pages kept per maintenance item, and for an interval's own heading page.
MAX_SERVICE_ITEM_PAGES = 10

# A matched bookmark takes its pages up to the next bookmark at its level or
# above, but never more than this many.
MAX_SPEC_PAGES = 40

DOC_TYPES = [
    ("shop_manual", re.compile(r"shop\s*manual|\bsm\b|\bsen\d", re.I)),
    ("omm", re.compile(r"\bomm\b|operation|\bpen\d", re.I)),
    ("partsbook", re.compile(r"part|\bpb\b", re.I)),
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


def spec_ranges(toc: list[list], page_count: int) -> list[tuple[int, str, int, int]]:
    """(section, title, first page, last page) for each bookmark in [toc]
    that names a spec page, pages counted from 1; each title and page once."""
    found, seen = [], set()
    for i, (level, title, page) in enumerate(toc):
        title = " ".join(title.split())
        if page < 1 or page > page_count:
            continue
        for section, pattern in enumerate(SPEC_SECTIONS):
            if not pattern.search(title) or (section, title.lower(), page) in seen:
                continue
            seen.add((section, title.lower(), page))
            last = page_count
            for next_level, _, next_page in toc[i + 1:]:
                if next_level <= level and next_page > page:
                    last = next_page - 1
                    break
            found.append((section, title, page, min(last, page + MAX_SPEC_PAGES - 1)))
    return found


def _section_end(toc: list[list], i: int, page_count: int) -> int:
    """Last page of bookmark i: the page before the next bookmark at its
    level or above (or the end of the PDF)."""
    level, _, page = toc[i]
    for next_level, _, next_page in toc[i + 1:]:
        if next_level <= level and next_page > page:
            return next_page - 1
    return page_count


def service_ranges(toc: list[list], page_count: int) -> list[dict]:
    """The maintenance schedule in [toc]: the chart (hours 0) and, for each
    "every N hours service" bookmark, its heading and the items under it,
    each with its first and last page."""
    found = []
    for i, (level, title, page) in enumerate(toc):
        title = " ".join(title.split())
        if page < 1 or page > page_count:
            continue
        if SERVICE_CHART.search(title):
            # "MAINTENANCE SCHEDULE" holding a "MAINTENANCE SCHEDULE CHART":
            # keep only the inner one.
            nxt = toc[i + 1] if i + 1 < len(toc) else None
            if nxt and nxt[0] > level and SERVICE_CHART.search(" ".join(nxt[1].split())):
                continue
            found.append({"hours": 0, "title": title, "page": page, "item": False,
                          "last": min(_section_end(toc, i, page_count), page + MAX_SPEC_PAGES - 1)})
            continue
        match = SERVICE_INTERVAL.search(title)
        if not match:
            continue
        try:
            hours = int(re.sub(r"[.,]", "", match.group(1)))
        except ValueError:
            continue
        if hours < 10:
            continue
        children = []
        for j in range(i + 1, len(toc)):
            child_level, child_title, child_page = toc[j]
            if child_level <= level:
                break
            if child_level == level + 1 and 1 <= child_page <= page_count:
                end = _section_end(toc, j, page_count)
                children.append({"hours": hours, "title": " ".join(child_title.split()), "page": child_page,
                                 "item": True, "last": min(end, child_page + MAX_SERVICE_ITEM_PAGES - 1)})
        heading_last = children[0]["page"] - 1 if children else _section_end(toc, i, page_count)
        heading_last = max(page, min(heading_last, page + MAX_SERVICE_ITEM_PAGES - 1))
        found.append({"hours": hours, "title": title, "page": page, "item": False, "last": heading_last})
        found += children
    return found


def build_spec_pack(sources: list[tuple[str, Path, list[list], int]], target: Path) -> tuple[list[dict], list[dict]]:
    """Copies the spec and maintenance schedule pages of [sources] (file id,
    PDF, bookmarks, page count) into [target] and returns where each one
    landed: (spec pages, service pages). Nothing is written when no manual
    bookmarks either."""
    entries, service, runs = [], [], []
    for file_id, pdf, toc, page_count in sources:
        ranges = spec_ranges(toc, page_count)
        svc = service_ranges(toc, page_count)
        if not ranges and not svc:
            continue
        # Each source page goes in once, even when bookmarks overlap.
        pages = sorted({n for _, _, first, last in ranges for n in range(first, last + 1)}
                       | {n for e in svc for n in range(e["page"], e["last"] + 1)})
        runs.append((file_id, pdf, pages, ranges, svc))
    if not runs:
        if target.exists():
            target.unlink()
        return [], []

    pack = pymupdf.open()
    at = {}
    for file_id, pdf, pages, ranges, svc in runs:
        with pymupdf.open(pdf) as src:
            start = 0
            while start < len(pages):
                end = start
                while end + 1 < len(pages) and pages[end + 1] == pages[end] + 1:
                    end += 1
                for n in pages[start:end + 1]:
                    at[(file_id, n)] = pack.page_count + 1 + n - pages[start]
                pack.insert_pdf(src, from_page=pages[start] - 1, to_page=pages[end] - 1)
                start = end + 1
        for section, title, first, last in ranges:
            entries.append({
                "section": section,
                "title": title,
                "file": file_id,
                "page": first,
                "at": at[(file_id, first)],
                "count": last - first + 1,
            })
        for e in svc:
            service.append({
                "hours": e["hours"],
                "title": e["title"],
                "file": file_id,
                "page": e["page"],
                "at": at[(file_id, e["page"])],
                "count": e["last"] - e["page"] + 1,
                "item": e["item"],
            })
    entries.sort(key=lambda e: e["section"])  # stable: manual order inside a section
    toc = []
    for section, name in enumerate(SPEC_SECTION_TITLES):
        mine = [e for e in entries if e["section"] == section]
        if mine:
            toc.append([1, name, mine[0]["at"]])
            toc += [[2, e["title"], e["at"]] for e in mine]
    if service:
        toc.append([1, "Jadwal servis", service[0]["at"]])
        for e in service:
            if not e["item"]:
                toc.append([2, e["title"], e["at"]])
    pack.set_toc(toc)
    pack.save(target, garbage=4, deflate=True)
    pack.close()
    return entries, service


def file_entry(path: Path, rel: str) -> dict:
    return {"path": rel, "size": path.stat().st_size, "sha256": sha256_of(path)}


def build_unit(unit_dir: Path, out_dir: Path, include_scanned: bool,
               previous: dict, now: str) -> dict:
    unit_id = unit_dir.name
    meta_path = unit_dir / "unit.json"
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    previous_files = {f["id"]: f for f in previous.get("files", [])}
    unit_out = out_dir / "units" / unit_id
    unit_out.mkdir(parents=True, exist_ok=True)

    files, skipped, spec_sources = [], [], []
    def order(pdf: Path) -> tuple:
        # Subfolders first, then the files directly in the unit folder
        # (the app orders them the same way).
        rel = pdf.relative_to(unit_dir)
        return (len(rel.parts) == 1, [part.lower() for part in rel.parts])

    for pdf in sorted(unit_dir.rglob("*.pdf"), key=order):
        rel = pdf.relative_to(unit_dir)
        group = " / ".join(rel.parts[:-1])
        pages, toc = extract(pdf)
        scanned = is_scanned(pages)
        if scanned and not include_scanned:
            skipped.append(rel.as_posix())
            print(f"  skip (scanned): {rel.as_posix()}")
            continue

        # The folder is part of the id, so equal names in two subfolders
        # don't collide; files directly in the unit folder keep their ids.
        file_id = slugify(rel.with_suffix("").as_posix())
        title = pdf.stem
        doc_type = guess_doc_type(pdf.name)
        target = unit_out / f"{file_id}.pdf"
        index_path = unit_out / f"{file_id}.sqlite"
        shutil.copy2(pdf, target)
        write_index(index_path, title, doc_type, pages, toc, not scanned)
        if doc_type != "partsbook":
            spec_sources.append((file_id, target, toc, len(pages)))

        pdf_info = file_entry(target, f"units/{unit_id}/{target.name}")
        index_info = file_entry(index_path, f"units/{unit_id}/{index_path.name}")
        before = previous_files.get(file_id)
        unchanged = before is not None and before["pdf"]["sha256"] == pdf_info["sha256"]
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
                "updated_at": before["updated_at"] if unchanged else now,
                **({"group": group} if group else {}),
            }
        )
        print(
            f"  {doc_type:12} {len(pages):5} pages {len(toc):4} bookmarks  "
            f"pdf {pdf_info['size'] / 1e6:.1f} MB + index {index_info['size'] / 1e6:.1f} MB  {rel.as_posix()}"
        )

    spec_path = unit_out / "spek.pdf"
    spec_pages, service_pages = build_spec_pack(spec_sources, spec_path)
    has_spec = bool(spec_pages or service_pages)
    if has_spec:
        spec = {**file_entry(spec_path, f"units/{unit_id}/spek.pdf"), "pages": spec_pages, "service": service_pages}
        intervals = sorted({e["hours"] for e in service_pages if e["hours"]})
        print(f"  spek.pdf      {len(spec_pages):4} spec pages, service HM {intervals or '-'}, "
              f"{spec['size'] / 1e6:.1f} MB")
    else:
        print("  spek.pdf      no spec or maintenance bookmarks found")

    return {
        "id": unit_id,
        "name": meta.get("name", unit_id),
        "kind": meta.get("kind", ""),
        "size": sum(f["download_size"] for f in files),
        "files": files,
        "skipped_scanned": skipped,
        **({"spec": spec} if has_spec else {}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path, help="folder with one subfolder per unit")
    parser.add_argument("dist", type=Path, help="output folder to upload")
    parser.add_argument("--only", nargs="*", help="build only these unit ids")
    parser.add_argument("--skip-scanned", action="store_true",
                        help="leave out PDFs without a text layer instead of shipping them unsearchable")
    args = parser.parse_args()

    unit_dirs = sorted(d for d in args.source.iterdir() if d.is_dir())
    if args.only:
        # Folder names typed on Windows may differ in case (pc210 vs PC210).
        wanted = {name.strip().upper() for name in args.only}
        unknown = wanted - {d.name.upper() for d in unit_dirs}
        if unknown:
            print(f"folder not found in {args.source}: {', '.join(sorted(unknown))}", file=sys.stderr)
            return 1
        unit_dirs = [d for d in unit_dirs if d.name.upper() in wanted]
    if not unit_dirs:
        print("no unit folders found", file=sys.stderr)
        return 1

    args.dist.mkdir(parents=True, exist_ok=True)
    catalog_path = args.dist / "catalog.json"
    previous = json.loads(catalog_path.read_text()) if catalog_path.exists() else {}
    previous_units = {u["id"]: u for u in previous.get("units", [])}
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    built = {}
    for unit_dir in unit_dirs:
        print(f"[{unit_dir.name}]")
        started = time.time()
        unit = build_unit(unit_dir, args.dist, not args.skip_scanned,
                          previous_units.get(unit_dir.name, {}), now)
        built[unit["id"]] = unit
        print(f"  done in {time.time() - started:.1f}s, {unit['size'] / 1e6:.1f} MB")

    # Units not rebuilt this run stay listed while their source folder exists.
    existing = {d.name for d in args.source.iterdir() if d.is_dir()}
    for unit_id, unit in previous_units.items():
        if unit_id not in built and unit_id in existing:
            built[unit_id] = unit

    catalog = {
        "schema": 1,
        "generated_at": now,
        "units": [built[k] for k in sorted(built)],
    }
    catalog_path.write_text(json.dumps(catalog, indent=2))
    print(f"wrote {catalog_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
