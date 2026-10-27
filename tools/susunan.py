"""Merge a folder of single SIS documents into one manual with bookmarks.

sis-download.bat saves every SIS document as its own PDF ("NNN Title.pdf")
plus daftar-dokumen.txt (number, title, book, date). A folder holding a
susunan.txt is shipped as ONE manual instead of one file per document:

    # Engine (C15/C18)                <- chapter (bookmark level 1)
    ## Fuel system                    <- group (level 2)
    121 Fuel System - Prime           <- document (level 3), by its file number

The words after the number are the bookmark title (the file's own title
when there are none). A line starting with // is a note; "// 090 ..."
leaves document 090 out of the manual. PDFs of the folder that
susunan.txt does not name at all (new downloads) go to a chapter
"Others" at the end, so nothing is lost. Without a
susunan.txt, build_packages writes a first one from daftar-dokumen.txt
(see draft_susunan): chapters from the SIS book, groups from words in the
titles. It is a plain text file, to be edited in Notepad.
"""

import hashlib
import json
import re
from pathlib import Path

import pymupdf

SUSUNAN_FILE = "susunan.txt"
LIST_FILE = "daftar-dokumen.txt"
OTHERS = "Others"

DOC_NUMBER = re.compile(r"^(\d{3,})\b\s*(.*)$")


def is_merged_folder(folder: Path) -> bool:
    """A folder that is shipped as one manual."""
    return (folder / SUSUNAN_FILE).exists() or (folder / LIST_FILE).exists()


def numbered_pdfs(folder: Path) -> dict[str, Path]:
    """The folder's "NNN Title.pdf" files by number."""
    out = {}
    for pdf in sorted(folder.glob("*.pdf")):
        m = DOC_NUMBER.match(pdf.stem)
        if m:
            out[m.group(1)] = pdf
    return out


def doc_title(pdf: Path) -> str:
    m = DOC_NUMBER.match(pdf.stem)
    return (m.group(2) if m else pdf.stem).strip() or pdf.stem


def read_susunan(path: Path) -> tuple[list[tuple[int, str, str | None]], set[str]]:
    """The outline as (level, title, document number or None) rows, and
    the numbers left out on purpose ("// 090 ...")."""
    rows, left_out = [], set()
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if line.startswith("//"):
            m = DOC_NUMBER.match(line[2:].strip())
            if m:
                left_out.add(m.group(1))
            continue
        if not line:
            continue
        if line.startswith("##"):
            rows.append((2, line.lstrip("#").strip(), None))
        elif line.startswith("#"):
            rows.append((1, line.lstrip("#").strip(), None))
        else:
            m = DOC_NUMBER.match(line)
            if m:
                rows.append((3, m.group(2).strip(), m.group(1)))
    return rows, left_out


def plan(folder: Path) -> tuple[list[tuple[int, str, Path | None]], list[str], list[Path]]:
    """What goes into the manual, in order: (bookmark level, title, PDF or
    None for a chapter or group heading). Also returns the numbers listed
    but missing and the PDFs not listed (those are put under Others)."""
    pdfs = numbered_pdfs(folder)
    rows, left_out = read_susunan(folder / SUSUNAN_FILE)
    out, missing, used = [], [], set(left_out)
    depth = 0  # 0 = no chapter yet, 1 = in a chapter, 2 = in a group
    for level, title, number in rows:
        if level < 3:
            depth = level if level == 1 or depth else 1
            out.append((depth, title, None))
            continue
        pdf = pdfs.get(number)
        if pdf is None:
            missing.append(number)
            continue
        used.add(number)
        out.append((depth + 1, title or doc_title(pdf), pdf))
    unlisted = [pdf for number, pdf in pdfs.items() if number not in used]
    if unlisted:
        out.append((1, OTHERS, None))
        out += [(2, doc_title(pdf), pdf) for pdf in unlisted]
    return out, missing, unlisted


def fingerprint(folder: Path) -> str:
    """Changes whenever susunan.txt or any of the folder's PDFs changes."""
    h = hashlib.sha256((folder / SUSUNAN_FILE).read_bytes())
    for pdf in sorted(folder.glob("*.pdf")):
        st = pdf.stat()
        h.update(f"{pdf.name}|{st.st_size}|{st.st_mtime_ns}".encode())
    return h.hexdigest()


def merge_folder(folder: Path, target: Path, title: str) -> tuple[bool, list[str], list[Path]]:
    """Writes the folder's manual to target. Returns (rebuilt, missing
    numbers, unlisted PDFs). A folder that has not changed since the last
    run is not merged again, so the manual keeps its exact bytes (and the
    app does not see a new version)."""
    items, missing, unlisted = plan(folder)
    stamp = target.with_suffix(".json")
    key = fingerprint(folder)
    if target.exists() and stamp.exists():
        try:
            if json.loads(stamp.read_text())["fingerprint"] == key:
                return False, missing, unlisted
        except (ValueError, KeyError, OSError):
            pass

    out = pymupdf.open()
    toc = []
    pending: list[tuple[int, str]] = []  # headings waiting for their first page
    for level, name, pdf in items:
        if pdf is None:
            # A heading replaces one of its level (or deeper) still waiting:
            # an empty chapter or group is left out.
            pending = [(lvl, h) for lvl, h in pending if lvl < level]
            pending.append((level, name))
            continue
        page = out.page_count + 1
        toc += [[lvl, heading, page] for lvl, heading in pending]
        pending = []
        toc.append([level, name, page])
        with pymupdf.open(pdf) as doc:
            out.insert_pdf(doc)
    if out.page_count == 0:
        raise ValueError(f"{folder}: tidak ada PDF yang bisa digabung")
    out.set_toc(toc)
    out.set_metadata({"title": title, "producer": "MyManual"})
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".tmp")
    out.save(tmp, garbage=3, deflate=True)
    out.close()
    tmp.replace(target)
    stamp.write_text(json.dumps({"fingerprint": key}))
    return True, missing, unlisted


# --- the first susunan.txt, written from daftar-dokumen.txt -----------------

# SIS book (by its code) -> chapter.
BOOK_CHAPTERS = {
    "M0118654": "Hydraulic & Machine Systems",
    "M0109908": "Work Tool Control",
    "M0082989": "Cat Grade 2D / 3D",
    "UENR4125": "Air Conditioning & Heating",
    "M0085479": "Air Conditioning & Heating",
    "M0083909": "Machine Security System",
    "RENR7911": "Product Link",
    "RENR8143": "Product Link",
    "UENR0997": "Engine (C15/C18)",
    "SENR9832": "Engine (C15/C18)",
    "M0119606": "Work Area Vision",
}
CHAPTER_ORDER = [
    "General Information", "Engine (C15/C18)", "Hydraulic & Machine Systems", "Work Tool Control",
    "Cat Grade 2D / 3D", "Air Conditioning & Heating", "Machine Security System", "Product Link",
    "Work Area Vision",
]
# Titles that belong to another chapter than their book's (or that have no book).
CHAPTER_BY_TITLE = [
    ("General Information", r"^(General Testing And Adjusting Information|Specifications|Operational Checks"
                            r"|Visual Inspection|Machine Preparation|Hydraulic System Warm-Up"
                            r"|System Pressure - Release)$", "M0118654"),
    ("Engine (C15/C18)", r"^Engine Performance", None),
    ("Hydraulic & Machine Systems", r"Joystick", None),
    ("Cat Grade 2D / 3D", r"Web Interface", None),
]
# (chapter, group, title pattern), tried in order; the group order in a
# chapter follows this list too.
GROUPS = [
    ("General Information", "General", r"^General Testing|^Specifications$|^Operational Checks|^Visual Inspection"),
    ("General Information", "Machine preparation", r"^Machine Preparation$|Warm-Up|^System Pressure - Release"),
    ("Engine (C15/C18)", "Engine performance", r"^Engine Performance"),
    ("Engine (C15/C18)", "Fuel system", r"Fuel|Electronic Unit Injector"),
    ("Engine (C15/C18)", "Air inlet & exhaust",
     r"Air Inlet|Exhaust|Turbocharger|Aftercooler|Inlet Manifold|Crankcase Pressure"),
    ("Engine (C15/C18)", "Lubrication system", r"Engine Oil|Oil Consumption|Bearing Wear"),
    ("Engine (C15/C18)", "Cooling system", r"Cooling System|Water Temperature|Water Pump"),
    ("Engine (C15/C18)", "Valve & timing", r"Valve Lash|Brake Lash|Top Center|Gear Group"),
    ("Engine (C15/C18)", "Basic engine",
     r"Piston|Liner|Connecting Rod|Main Bearing|Cylinder Block|Flywheel|Vibration Damper"),
    ("Engine (C15/C18)", "Electrical system", r"Charging|Starting|Battery|Pinion Clearance"),
    ("Hydraulic & Machine Systems", "Relief valve", r"Relief Valve"),
    ("Hydraulic & Machine Systems", "Main pump & pump control", r"Main Pump|Pump Control"),
    ("Hydraulic & Machine Systems", "Pilot & accumulator", r"Pilot Pressure|Accumulator"),
    ("Hydraulic & Machine Systems", "Air purge", r"Air - Purge"),
    ("Hydraulic & Machine Systems", "Travel", r"Travel"),
    ("Hydraulic & Machine Systems", "Swing", r"Swing"),
    ("Hydraulic & Machine Systems", "Cylinder", r"Cylinder (Drift|Speed)"),
    ("Hydraulic & Machine Systems", "Calibration", r"Calibrate"),
    ("Work Tool Control", "Relief valve & parameters", r"Relief|Parameter"),
    ("Work Tool Control", "Solenoid valve calibration", r"Solenoid Valve"),
    ("Work Tool Control", "Work tool setup", r"Work Tool|System Identification"),
    ("Cat Grade 2D / 3D", "Calibration", r"^Calibration|Imu|Bucket Sensor|Service Tool Accuracy"),
    ("Cat Grade 2D / 3D", "Configuration & setup", r"Configuration|Setup Sequence"),
    ("Cat Grade 2D / 3D", "Licenses", r"Licenses"),
    ("Cat Grade 2D / 3D", "Accuracy tests", r"Accuracy|Test|Bucket Wear"),
    ("Air Conditioning & Heating", "Tools & preparation", r"Manifold Gauge|Required Tools|Preparation|Publications"),
    ("Air Conditioning & Heating", "Refrigerant", r"Refrigerant"),
    ("Air Conditioning & Heating", "Performance tests", r"Performance|Heat|Compressor Protection"),
]


def read_list(folder: Path) -> list[dict]:
    """daftar-dokumen.txt rows: number, title, book (with its code), date."""
    rows = []
    for line in (folder / LIST_FILE).read_text(encoding="utf-8-sig").splitlines():
        parts = [p.strip() for p in line.split(" | ")]
        m = DOC_NUMBER.match(parts[0])
        if not m:
            continue
        title = re.sub(r"\.pdf$", "", m.group(2), flags=re.I).strip()
        book = re.sub(r"<[^>]+>|&[a-z]+;", "", parts[1]) if len(parts) > 2 else ""
        code = re.search(r"\(([A-Z]+\d+)-\d+\)\s*$", book)
        rows.append({"number": m.group(1), "title": title, "book": book,
                     "code": code.group(1) if code else "", "date": parts[-1] if len(parts) > 1 else ""})
    return rows


def chapter_of(row: dict) -> str:
    for chapter, pattern, only_book in CHAPTER_BY_TITLE:
        if re.search(pattern, row["title"], re.I) and (only_book is None or row["code"] == only_book):
            return chapter
    if row["code"] in BOOK_CHAPTERS:
        return BOOK_CHAPTERS[row["code"]]
    if row["code"]:
        # A book not known yet: its own chapter, named after the book.
        return re.sub(r"^.*? - |\s*\([A-Z]+\d+-\d+\)$", "", row["book"]).strip() or OTHERS
    return "Engine (C15/C18)"  # SIS shows no book for most engine documents


def group_of(chapter: str, title: str) -> str:
    for ch, group, pattern in GROUPS:
        if ch == chapter and re.search(pattern, title, re.I):
            return group
    return "Others"


def draft_susunan(folder: Path) -> str:
    """A first susunan.txt for the folder, from its daftar-dokumen.txt.
    Every document is listed, same titles too (each SIS copy may differ);
    a title found in two books carries the book's code."""
    rows = read_list(folder)
    files = numbered_pdfs(folder)
    rows = [r for r in rows if r["number"] in files]
    tree: dict[str, dict[str, list[dict]]] = {}
    for row in rows:
        chapter = chapter_of(row)
        tree.setdefault(chapter, {}).setdefault(group_of(chapter, row["title"]), []).append(row)

    def chapter_key(name: str) -> int:
        return CHAPTER_ORDER.index(name) if name in CHAPTER_ORDER else len(CHAPTER_ORDER)

    def group_key(chapter: str, name: str) -> int:
        order = [g for ch, g, _ in GROUPS if ch == chapter]
        return order.index(name) if name in order else len(order)

    lines = [
        "// Susunan manual: # = bab, ## = kelompok, lalu nomor file dan judul bookmark.",
        "// Pindahkan baris untuk mengubah urutan atau kelompok; ganti judul setelah nomor untuk",
        "// mengubah nama bookmark. Untuk tidak memakai dokumen, tulis // di depan barisnya.",
        "// File baru yang belum ada di sini otomatis masuk bab Others di akhir.",
    ]
    for chapter in sorted(tree, key=chapter_key):
        lines += ["", f"# {chapter}"]
        for group in sorted(tree[chapter], key=lambda g: group_key(chapter, g)):
            docs = sorted(tree[chapter][group], key=lambda r: (r["title"].lower(), r["number"]))
            books = {}
            for r in docs:
                books.setdefault(r["title"].lower(), set()).add(r["code"])
            # A chapter with no groups of its own lists its documents directly.
            if list(tree[chapter]) != ["Others"]:
                lines.append(f"## {group}")
            for r in docs:
                code = f" ({r['code']})" if len(books[r["title"].lower()]) > 1 and r["code"] else ""
                lines.append(f"{r['number']} {r['title']}{code}")
    return "\n".join(lines) + "\n"
