#!/usr/bin/env python3
"""Upload the employee list (karyawan.xlsx) that decides who can log in to MyManual.

The file has a header row with these columns (any order, any case):

    NRP | Nama | PIN awal | Admin | Section | Departemen

- PIN awal: 4 digits, given to the employee for the first login; the app
  then asks for a new PIN. Changing it in the file later resets that
  employee's PIN to the new starting PIN.
- Admin: "ya" for employees who manage the list in the app (menu
  Kelola karyawan). At least one is needed.
- Section: which manuals the employee sees, e.g. TRACK or WHEEL; more
  than one separated by commas ("TRACK, WHEEL"). The names are those of the
  "SECTION <name>" folders in source/ (see tools/sections.py); SEMUA is seen
  by everyone anyway. Admins see every section. Without a Section column
  everyone is TRACK; with one, an empty cell stops the upload.
- Departemen: only shown in the app's Kelola karyawan (and for its
  filter); it does not change what the employee sees.
- An employee removed from the file can no longer log in; putting the row
  back lets them in again.

Needs ADMIN_CODE (the server's admin code, the GitHub secret OWNER_CODE),
set in r2-keys.bat.

    python tools/upload_karyawan.py karyawan.xlsx
    python tools/upload_karyawan.py karyawan.xlsx --dry-run   # only check the file
"""

import argparse
import csv
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

SERVER = os.environ.get("AI_SERVER_URL", "https://ai.mymanual.my.id").rstrip("/")

# Digits in a starting PIN (the server checks the same).
PIN_LENGTH = 4

COLUMNS = {
    "nrp": ("nrp",),
    "name": ("nama", "name", "nama karyawan"),
    "pin": ("pin awal", "pin", "pin_awal"),
    "admin": ("admin",),
    "sections": ("section", "sections", "seksi"),
    "department": ("departemen", "department", "dept"),
}

DEFAULT_SECTION = "TRACK"
SECTION_NAME = re.compile(r"^[A-Z0-9][A-Z0-9 _-]*$")


def parse_sections(text: str) -> list[str]:
    """"Track, wheel" -> ["TRACK", "WHEEL"]; "SECTION TRACK" is TRACK too."""
    names = []
    for part in re.split(r"[,;/+]", text):
        name = " ".join(part.split()).upper()
        if name.startswith("SECTION "):
            name = name[len("SECTION "):]
        if name and name not in names:
            names.append(name)
    return names


def cell_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return str(value).strip()


def read_rows(path: Path) -> list[list[str]]:
    if path.suffix.lower() == ".csv":
        with path.open(newline="", encoding="utf-8-sig") as f:
            sample = f.read(2048)
            f.seek(0)
            dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
            return [[cell_text(c) for c in row] for row in csv.reader(f, dialect)]
    import openpyxl  # imported here so --help works without it installed

    sheet = openpyxl.load_workbook(path, read_only=True, data_only=True).worksheets[0]
    return [[cell_text(c) for c in row] for row in sheet.iter_rows(values_only=True)]


def parse(rows: list[list[str]]) -> tuple[list[dict], list[str]]:
    problems = []
    header_at = next((i for i, r in enumerate(rows) if any(c.lower() == "nrp" for c in r)), None)
    if header_at is None:
        return [], ["Baris judul dengan kolom NRP tidak ditemukan."]
    header = [c.lower() for c in rows[header_at]]
    where = {}
    for key, names in COLUMNS.items():
        where[key] = next((header.index(n) for n in names if n in header), None)
    for key, label in (("nrp", "NRP"), ("pin", "PIN awal")):
        if where[key] is None:
            problems.append(f"Kolom '{label}' tidak ada.")
    if problems:
        return [], problems

    def get(row, key):
        i = where[key]
        return row[i] if i is not None and i < len(row) else ""

    employees, seen = [], set()
    fatal = False
    for n, row in enumerate(rows[header_at + 1:], start=header_at + 2):
        nrp = get(row, "nrp").upper()
        if not nrp:
            continue
        pin = get(row, "pin")
        # Excel drops leading zeros from numbers: 0123 becomes 123.
        if pin.isdigit() and len(pin) < PIN_LENGTH:
            pin = pin.zfill(PIN_LENGTH)
        if not (pin.isdigit() and len(pin) == PIN_LENGTH):
            problems.append(f"Baris {n} ({nrp}): PIN awal harus {PIN_LENGTH} angka.")
            continue
        if nrp in seen:
            problems.append(f"Baris {n}: NRP {nrp} dobel.")
            continue
        if where["sections"] is None:
            sections = [DEFAULT_SECTION]
        else:
            sections = parse_sections(get(row, "sections"))
            if not sections:
                problems.append(f"Baris {n} ({nrp}): kolom Section kosong.")
                fatal = True
                continue
            bad = [s for s in sections if not SECTION_NAME.match(s)]
            if bad:
                problems.append(f"Baris {n} ({nrp}): nama section tidak dikenali: {', '.join(bad)}")
                fatal = True
                continue
        seen.add(nrp)
        employees.append({
            "sections": sections,
            "department": " ".join(get(row, "department").split()).upper(),
            "nrp": nrp,
            "name": get(row, "name") or nrp,
            "pin": pin,
            "admin": get(row, "admin").lower() in ("ya", "y", "yes", "admin", "1", "true", "v", "x"),
        })
    if where["sections"] is None:
        problems.append(f"Kolom 'Section' belum ada: semua karyawan dianggap section {DEFAULT_SECTION}.")
    if fatal:
        # A skipped row would log that employee out, so nothing is uploaded.
        return [], problems + ["Perbaiki kolom Section di baris di atas, lalu jalankan lagi."]
    return employees, problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("file", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.file.exists():
        print(f"File {args.file} tidak ada.", file=sys.stderr)
        return 1
    employees, problems = parse(read_rows(args.file))
    for p in problems:
        print("PERIKSA  " + p)
    admins = [e["name"] for e in employees if e["admin"]]
    print(f"{len(employees)} karyawan, admin: {', '.join(admins) or '-'}")
    counts: dict[str, int] = {}
    for e in employees:
        for section in e["sections"]:
            counts[section] = counts.get(section, 0) + 1
    if counts:
        print("Per section: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    if not employees:
        return 1
    if not admins:
        print("Tandai minimal satu karyawan sebagai admin (kolom Admin = ya).", file=sys.stderr)
        return 1
    if args.dry_run:
        return 0

    code = os.environ.get("ADMIN_CODE", "").strip()
    if not code:
        print("ADMIN_CODE belum diisi di r2-keys.bat (kode admin = secret OWNER_CODE di GitHub).", file=sys.stderr)
        return 1
    request = urllib.request.Request(
        f"{SERVER}/admin/import",
        data=json.dumps({"employees": employees}).encode(),
        headers={"content-type": "application/json", "authorization": f"Bearer {code}", "User-Agent": "MyManual-update"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            result = json.load(response)
    except urllib.error.HTTPError as e:
        try:
            message = json.load(e).get("message", "")
        except Exception:
            message = ""
        print(f"Server menolak ({e.code}) {message}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"Tidak bisa menghubungi server: {e}", file=sys.stderr)
        return 1
    for p in result.get("problems", []):
        print("PERIKSA  " + p)
    print(
        f"Baru {result['added']}, diubah {result['updated']}, PIN direset {result['pin_reset']}, "
        f"dinonaktifkan {result['deactivated']}, aktif lagi {result['reactivated']}, sama {result['unchanged']}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
