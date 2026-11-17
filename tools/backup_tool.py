#!/usr/bin/env python3
"""Backup and restore of MyManual's employee list and quiz (see BACKUP.md).

Run by the GitHub workflows "Backup mingguan" (.github/workflows/backup.yml)
and "Pulihkan backup" (.github/workflows/restore.yml); nothing has to be
installed on a PC. Needs CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID
(the repository secrets the AI server deploy uses) for the commands that
talk to Cloudflare.

    export-karyawan OUT.json        employees (KV "emp:*") from Cloudflare
    excel-karyawan IN.json OUT.xlsx  readable list, without PINs
    excel-quiz QUIZ.sql OUT.xlsx     every quiz table as a sheet
    restore-quiz-sql QUIZ.sql OUT.sql  SQL that empties each quiz table
                                     and fills it from the backup
    restore-karyawan IN.json         puts every employee in the backup back
    count-quiz QUIZ.sql              "question: 412, quiz_user: 187, ..."

The quiz backup (QUIZ.sql) is made by Cloudflare's own
"wrangler d1 export mymanual-quiz --remote".
"""

import argparse
import datetime
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.cloudflare.com/client/v4"
KV_TITLE = "mymanual-auth"
EMPLOYEE_PREFIX = "emp:"
# Tables of the quiz database that are not quiz data.
SKIP_TABLES = {"d1_migrations", "sqlite_sequence"}
EXCEL_MAX_ROWS = 1_000_000
WIB = datetime.timezone(datetime.timedelta(hours=7))


# --- Cloudflare -----------------------------------------------------------

class CloudflareError(Exception):
    pass


def cloudflare(method: str, path: str, body=None, raw: bool = False):
    """One call to the Cloudflare API: the JSON answer, or the bytes when
    [raw] (a stored value)."""
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
    if not token or not account:
        raise CloudflareError("CLOUDFLARE_API_TOKEN dan CLOUDFLARE_ACCOUNT_ID belum diisi (Settings > Secrets).")
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        f"{API}/accounts/{account}{path}",
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            content = response.read()
    except urllib.error.HTTPError as e:
        raise CloudflareError(f"Cloudflare menolak {method} {path}: {e.code} {e.read()[:500]!r}") from e
    return content if raw else json.loads(content)


def namespace_id(api=cloudflare) -> str:
    """The id of the KV namespace that holds the employees."""
    page = 1
    while True:
        answer = api("GET", f"/storage/kv/namespaces?per_page=100&page={page}")
        spaces = answer.get("result") or []
        for ns in spaces:
            if ns["title"] == KV_TITLE or ns["title"].endswith("-" + KV_TITLE):
                return ns["id"]
        if len(spaces) < 100:
            raise CloudflareError(f"Penyimpanan KV '{KV_TITLE}' tidak ditemukan di Cloudflare.")
        page += 1


def export_karyawan(api=cloudflare) -> dict:
    """Every employee entry exactly as stored: key, value (text), metadata."""
    ns = namespace_id(api)
    keys, cursor = [], ""
    while True:
        answer = api("GET", f"/storage/kv/namespaces/{ns}/keys?prefix={EMPLOYEE_PREFIX}&limit=1000"
                     + (f"&cursor={cursor}" if cursor else ""))
        keys += [k["name"] for k in answer.get("result") or []]
        cursor = (answer.get("result_info") or {}).get("cursor") or ""
        if not cursor:
            break
    items = []
    for start in range(0, len(keys), 100):
        batch = keys[start:start + 100]
        try:
            answer = api("POST", f"/storage/kv/namespaces/{ns}/bulk/get",
                         {"keys": batch, "type": "text", "withMetadata": True})
            values = (answer.get("result") or {}).get("values") or {}
        except CloudflareError:
            # Without the bulk read, one key at a time.
            values = {}
            for key in batch:
                quoted = urllib.parse.quote(key, safe="")
                try:
                    value = api("GET", f"/storage/kv/namespaces/{ns}/values/{quoted}", raw=True).decode("utf-8")
                except CloudflareError:
                    continue
                try:
                    meta = api("GET", f"/storage/kv/namespaces/{ns}/metadata/{quoted}").get("result")
                except CloudflareError:
                    meta = None
                values[key] = {"value": value, "metadata": meta}
        for key in batch:
            entry = values.get(key)
            if entry is None:
                continue  # deleted while reading
            items.append({"key": key, "value": entry.get("value"), "metadata": entry.get("metadata")})
    return {"exported_at": datetime.datetime.now(WIB).isoformat(timespec="seconds"), "items": items}


def restore_karyawan(backup: dict, api=cloudflare) -> int:
    """Writes every employee in the backup back; others are left alone."""
    ns = namespace_id(api)
    items = [i for i in backup["items"] if i["key"].startswith(EMPLOYEE_PREFIX) and i.get("value") is not None]
    for start in range(0, len(items), 1000):
        batch = [
            {"key": i["key"], "value": i["value"], **({"metadata": i["metadata"]} if i.get("metadata") else {})}
            for i in items[start:start + 1000]
        ]
        api("PUT", f"/storage/kv/namespaces/{ns}/bulk", batch)
    return len(items)


# --- Readable Excel files ---------------------------------------------------

def _when(ms) -> str:
    if not ms:
        return ""
    return datetime.datetime.fromtimestamp(ms / 1000, WIB).strftime("%Y-%m-%d %H:%M")


def karyawan_rows(backup: dict) -> list[list]:
    """One row per employee, sorted by NRP; no PIN or device ids."""
    rows = []
    for item in backup["items"]:
        try:
            e = json.loads(item["value"])
        except (TypeError, ValueError):
            continue
        devices = (e.get("devices") or {}).values()
        last = max(devices, key=lambda d: d.get("seen", 0), default={})
        rows.append([
            e.get("nrp", item["key"][len(EMPLOYEE_PREFIX):]),
            e.get("name", ""),
            ", ".join(e.get("sections") or ["TRACK"]),
            e.get("department", ""),
            "ya" if e.get("active", True) else "tidak",
            "ya" if e.get("admin") else "",
            "belum" if e.get("must_change") else "sudah",
            _when(e.get("last_seen")),
            last.get("model", ""),
            last.get("app", ""),
        ])
    return sorted(rows, key=lambda r: str(r[0]))


KARYAWAN_HEADER = ["NRP", "Nama", "Section", "Departemen", "Aktif", "Admin", "Sudah ganti PIN",
                   "Terakhir dipakai", "HP terakhir", "Versi app"]


def _save_sheets(sheets: list[tuple[str, list, list[list]]], out: Path) -> None:
    from openpyxl import Workbook
    from openpyxl.styles import Font

    book = Workbook()
    book.remove(book.active)
    for title, header, rows in sheets:
        sheet = book.create_sheet(title[:31])
        sheet.append(header)
        for cell in sheet[1]:
            cell.font = Font(bold=True)
        for row in rows[:EXCEL_MAX_ROWS]:
            sheet.append([_cell(v) for v in row])
        sheet.freeze_panes = "A2"
    if not sheets:
        book.create_sheet("kosong")
    out.parent.mkdir(parents=True, exist_ok=True)
    book.save(out)


def _cell(value):
    if isinstance(value, bytes):
        return f"({len(value)} byte)"
    if isinstance(value, str) and len(value) > 32000:
        return value[:32000] + "…"
    return value


def load_dump(sql: str) -> sqlite3.Connection:
    """The quiz backup in a database in memory."""
    db = sqlite3.connect(":memory:")
    db.executescript(sql)
    return db


def quiz_tables(db: sqlite3.Connection) -> list[str]:
    names = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")]
    return [n for n in names if n not in SKIP_TABLES and not n.startswith(("sqlite_", "_cf_"))]


def quiz_sheets(sql: str) -> list[tuple[str, list, list[list]]]:
    db = load_dump(sql)
    sheets = []
    for table in quiz_tables(db):
        cursor = db.execute(f'SELECT * FROM "{table}"')
        sheets.append((table, [c[0] for c in cursor.description], [list(r) for r in cursor]))
    return sheets


def count_quiz(sql: str) -> dict[str, int]:
    db = load_dump(sql)
    return {t: db.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0] for t in quiz_tables(db)}


# --- Quiz restore -----------------------------------------------------------

def _literal(value) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return str(int(value))
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, bytes):
        return f"X'{value.hex()}'"
    return "'" + str(value).replace("'", "''") + "'"


def restore_quiz_sql(sql: str) -> str:
    """Empties every quiz table and fills it again from the backup, naming
    the columns so a table that gained a column since still takes it."""
    db = load_dump(sql)
    out = []
    for table in quiz_tables(db):
        out.append(f'DELETE FROM "{table}";')
        cursor = db.execute(f'SELECT * FROM "{table}"')
        columns = ", ".join(f'"{c[0]}"' for c in cursor.description)
        for row in cursor:
            out.append(f'INSERT INTO "{table}" ({columns}) VALUES ({", ".join(_literal(v) for v in row)});')
    return "\n".join(out) + "\n"


# --- Command line -----------------------------------------------------------

def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("export-karyawan").add_argument("out")
    p = sub.add_parser("excel-karyawan")
    p.add_argument("json_in")
    p.add_argument("out")
    p = sub.add_parser("excel-quiz")
    p.add_argument("sql_in")
    p.add_argument("out")
    p = sub.add_parser("restore-quiz-sql")
    p.add_argument("sql_in")
    p.add_argument("out")
    sub.add_parser("restore-karyawan").add_argument("json_in")
    sub.add_parser("count-quiz").add_argument("sql_in")
    args = parser.parse_args(argv)
    try:
        run(args)
    except CloudflareError as e:
        sys.exit(str(e))


def run(args) -> None:

    if args.command == "export-karyawan":
        backup = export_karyawan()
        if not backup["items"]:
            sys.exit("Tidak ada data karyawan yang terbaca; backup dibatalkan.")
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(json.dumps(backup, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"Karyawan: {len(backup['items'])}")
    elif args.command == "excel-karyawan":
        backup = json.loads(Path(args.json_in).read_text(encoding="utf-8"))
        _save_sheets([("Karyawan", KARYAWAN_HEADER, karyawan_rows(backup))], Path(args.out))
    elif args.command == "excel-quiz":
        _save_sheets(quiz_sheets(Path(args.sql_in).read_text(encoding="utf-8")), Path(args.out))
    elif args.command == "restore-quiz-sql":
        Path(args.out).write_text(restore_quiz_sql(Path(args.sql_in).read_text(encoding="utf-8")), encoding="utf-8")
    elif args.command == "restore-karyawan":
        backup = json.loads(Path(args.json_in).read_text(encoding="utf-8"))
        print(f"Karyawan dipulihkan: {restore_karyawan(backup)}")
    elif args.command == "count-quiz":
        counts = count_quiz(Path(args.sql_in).read_text(encoding="utf-8"))
        print(", ".join(f"{t}: {n}" for t, n in counts.items()))


if __name__ == "__main__":
    main()
