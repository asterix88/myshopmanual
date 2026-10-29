"""python -m unittest discover tools  (no PDF libraries needed)."""

import tempfile
import unittest
from pathlib import Path

from sections import find_units, is_duplicate_problem


def make(root: Path, *paths: str) -> None:
    for p in paths:
        f = root / p
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(b"%PDF")


class FindUnits(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def found(self):
        units, problems = find_units(self.root)
        return [(u.name, s, k) for u, s, k in units], problems

    def test_old_layout_is_track(self):
        make(self.root, "PC210/sm.pdf", "D85/omm.pdf", ".ocr/x.pdf")
        units, problems = self.found()
        self.assertEqual(units, [("D85", "TRACK", ""), ("PC210", "TRACK", "")])
        self.assertEqual(problems, [])

    def test_sections_and_kelompok(self):
        make(self.root, "SECTION TRACK/EXCAVATOR/PC210/sm.pdf", "Section Wheel/hd/HD785-7/sm.pdf",
             "SECTION SEMUA/UMUM/PANDUAN MLU/a.pdf", "CAT395/System Diagram/x.pdf")
        units, problems = self.found()
        self.assertEqual(units, [("CAT395", "TRACK", ""), ("HD785-7", "WHEEL", "HD"),
                                 ("PANDUAN MLU", "SEMUA", "UMUM"), ("PC210", "TRACK", "EXCAVATOR")])
        self.assertEqual(problems, [])

    def test_duplicate_unit_name(self):
        make(self.root, "PC210/a.pdf", "SECTION TRACK/EXCAVATOR/pc210/b.pdf")
        _, problems = self.found()
        self.assertEqual(len(problems), 1)
        self.assertTrue(is_duplicate_problem(problems[0]))

    def test_loose_pdfs_are_reported(self):
        make(self.root, "SECTION WHEEL/x.pdf", "SECTION WHEEL/HD/y.pdf", "SECTION WHEEL/HD/HD785/z.pdf")
        units, problems = self.found()
        self.assertEqual(units, [("HD785", "WHEEL", "HD")])
        self.assertEqual(len(problems), 2)
        self.assertFalse(any(is_duplicate_problem(p) for p in problems))


if __name__ == "__main__":
    unittest.main()
