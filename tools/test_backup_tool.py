"""Backup and restore of employees and quiz (backup_tool.py), without Cloudflare."""

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

import backup_tool as bt

# Like "wrangler d1 export": schema and rows of the quiz database.
DUMP = """
PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE d1_migrations(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, applied_at TIMESTAMP);
INSERT INTO "d1_migrations" VALUES(1,'0001_quiz.sql','2026-11-04 01:00:00');
CREATE TABLE question (id TEXT PRIMARY KEY, text TEXT NOT NULL, level INTEGER, score REAL, image BLOB);
INSERT INTO "question" VALUES('q1','Berapa torsi ''track shoe''?',2,0.5,NULL);
INSERT INTO "question" VALUES('q2','Apa itu SL1?',NULL,NULL,X'0102');
CREATE TABLE xp_board (nrp TEXT PRIMARY KEY, xp INTEGER NOT NULL);
INSERT INTO "xp_board" VALUES('21045678',120);
"""


def employee(nrp, name, **extra):
    value = {"nrp": nrp, "name": name, "admin": False, "active": True, "sections": ["TRACK"], "pin": "h",
             "salt": "s", "must_change": False, "last_seen": 1_800_000_000_000,
             "devices": {"a": {"model": "Samsung A15", "seen": 5, "app": "1.1.215"}}, **extra}
    return {"key": f"emp:{nrp}", "value": json.dumps(value), "metadata": {"name": name}}


class FakeCloudflare:
    """Answers the few KV calls the tool makes, from a dict."""

    def __init__(self, store, bulk=True):
        self.store = store
        self.bulk = bulk
        self.writes = []

    def __call__(self, method, path, body=None, raw=False):
        if path.startswith("/storage/kv/namespaces?"):
            return {"result": [{"id": "other", "title": "x"}, {"id": "ns1", "title": "mymanual-ai-mymanual-auth"}]}
        if "/keys?" in path:
            names = sorted(k for k in self.store if k.startswith("emp:"))
            if "cursor=" in path:
                return {"result": [{"name": n} for n in names[1:]], "result_info": {"cursor": ""}}
            return {"result": [{"name": names[0]}], "result_info": {"cursor": "next"}}
        if path.endswith("/bulk/get"):
            if not self.bulk:
                raise bt.CloudflareError("404")
            return {"result": {"values": {k: self.store[k] for k in body["keys"] if k in self.store}}}
        if "/values/" in path:
            key = bt.urllib.parse.unquote(path.rsplit("/", 1)[1])
            return self.store[key]["value"].encode()
        if "/metadata/" in path:
            key = bt.urllib.parse.unquote(path.rsplit("/", 1)[1])
            return {"result": self.store[key]["metadata"]}
        if path.endswith("/bulk") and method == "PUT":
            self.writes += body
            return {"success": True}
        raise AssertionError(path)


class Karyawan(unittest.TestCase):
    def store(self):
        return {i["key"]: {"value": i["value"], "metadata": i["metadata"]}
                for i in [employee("2", "Budi"), employee("1", "Ali", admin=True, active=False)]}

    def test_export_reads_every_page_and_keeps_values_exactly(self):
        for bulk in (True, False):
            store = self.store()
            backup = bt.export_karyawan(FakeCloudflare(store, bulk=bulk))
            self.assertEqual([i["key"] for i in backup["items"]], ["emp:1", "emp:2"])
            self.assertEqual(backup["items"][0]["value"], store["emp:1"]["value"])
            self.assertEqual(backup["items"][0]["metadata"], {"name": "Ali"})

    def test_restore_writes_back_only_what_the_backup_has(self):
        fake = FakeCloudflare({})
        backup = {"items": [employee("1", "Ali"), {"key": "config:app", "value": "{}"}]}
        self.assertEqual(bt.restore_karyawan(backup, fake), 1)
        self.assertEqual(fake.writes, [{"key": "emp:1", "value": backup["items"][0]["value"],
                                        "metadata": {"name": "Ali"}}])

    def test_readable_rows_have_no_pin(self):
        rows = bt.karyawan_rows({"items": [employee("2", "Budi"), employee("1", "Ali", active=False, admin=True)]})
        self.assertEqual(rows[0][:7], ["1", "Ali", "TRACK", "", "tidak", "ya", "sudah"])
        self.assertEqual(rows[1][8:], ["Samsung A15", "1.1.215"])
        self.assertNotIn("h", sum((list(map(str, r)) for r in rows), []))

    def test_excel_file(self):
        from openpyxl import load_workbook
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "karyawan.xlsx"
            source = Path(d) / "k.json"
            source.write_text(json.dumps({"items": [employee("1", "Ali")]}))
            bt.main(["excel-karyawan", str(source), str(out)])
            sheet = load_workbook(out)["Karyawan"]
            self.assertEqual([c.value for c in sheet[1]][:2], ["NRP", "Nama"])
            self.assertEqual(sheet["B2"].value, "Ali")


class Quiz(unittest.TestCase):
    def test_counts_and_sheets_leave_out_migrations(self):
        self.assertEqual(bt.count_quiz(DUMP), {"question": 2, "xp_board": 1})
        sheets = bt.quiz_sheets(DUMP)
        self.assertEqual([s[0] for s in sheets], ["question", "xp_board"])
        self.assertEqual(sheets[0][1], ["id", "text", "level", "score", "image"])

    def test_restore_brings_the_tables_back_exactly(self):
        live = sqlite3.connect(":memory:")
        live.executescript(DUMP)
        # After the backup: a question changed, one deleted, one added,
        # XP grew, and a new column came with a migration.
        live.executescript("""
            UPDATE question SET text = 'rusak' WHERE id = 'q1';
            DELETE FROM question WHERE id = 'q2';
            INSERT INTO question VALUES('q3','baru',1,1,NULL);
            UPDATE xp_board SET xp = 999;
            ALTER TABLE question ADD COLUMN site TEXT DEFAULT 'TS';
        """)
        live.executescript(bt.restore_quiz_sql(DUMP))
        self.assertEqual(
            live.execute("SELECT id, text, level, score, image, site FROM question ORDER BY id").fetchall(),
            [("q1", "Berapa torsi 'track shoe'?", 2, 0.5, None, "TS"), ("q2", "Apa itu SL1?", None, None, b"\x01\x02", "TS")],
        )
        self.assertEqual(live.execute("SELECT * FROM xp_board").fetchall(), [("21045678", 120)])
        self.assertEqual(live.execute("SELECT COUNT(*) FROM d1_migrations").fetchone()[0], 1)

    def test_excel_file(self):
        from openpyxl import load_workbook
        with tempfile.TemporaryDirectory() as d:
            source = Path(d) / "quiz.sql"
            source.write_text(DUMP)
            out = Path(d) / "quiz.xlsx"
            bt.main(["excel-quiz", str(source), str(out)])
            book = load_workbook(out)
            self.assertEqual(book.sheetnames, ["question", "xp_board"])
            self.assertEqual(book["question"]["C2"].value, 2)
            self.assertEqual(book["question"]["E3"].value, "(2 byte)")


if __name__ == "__main__":
    unittest.main()
