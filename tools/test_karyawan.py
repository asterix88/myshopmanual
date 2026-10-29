"""Section and Departemen columns of karyawan.xlsx (upload_karyawan.parse)."""

import unittest

from upload_karyawan import parse

HEADER = ["NRP", "Nama", "PIN awal", "Admin", "Section", "Departemen"]


class Parse(unittest.TestCase):
    def test_sections_and_department(self):
        employees, problems = parse([HEADER, ["1", "A", "1234", "ya", "track, Wheel", "plant"],
                                     ["2", "B", "1234", "", "SECTION WHEEL", ""]])
        self.assertEqual(problems, [])
        self.assertEqual([e["sections"] for e in employees], [["TRACK", "WHEEL"], ["WHEEL"]])
        self.assertEqual([e["department"] for e in employees], ["PLANT", ""])

    def test_empty_section_stops_the_upload(self):
        employees, problems = parse([HEADER, ["1", "A", "1234", "ya", "TRACK", ""], ["2", "B", "1234", "", "", ""]])
        self.assertEqual(employees, [])
        self.assertIn("Baris 3 (2): kolom Section kosong.", problems)

    def test_no_section_column_is_track(self):
        employees, problems = parse([HEADER[:4], ["1", "A", "1234", "ya"]])
        self.assertEqual(employees[0]["sections"], ["TRACK"])
        self.assertEqual(len(problems), 1)


if __name__ == "__main__":
    unittest.main()
