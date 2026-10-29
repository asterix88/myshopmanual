"""Which section and folder (kelompok) each unit folder in source/ belongs to.

Two layouts are read, and may be mixed while folders are being moved:

    source/
      SECTION TRACK/              a section: "SECTION " + its name
        EXCAVATOR/                a kelompok: a folder on the app's Home
          PC210/  ...pdf          a unit
        BULLDOZER/
          D85/
      SECTION WHEEL/
        HD/
          HD785-7/
      SECTION SEMUA/              shown to every NRP (Panduan MLU, Basic Electric)
        UMUM/
          PANDUAN MLU/
      PC500LC-10/                 the old layout: a unit straight in source/,
                                  section TRACK, kelompok guessed by the app

A phone sees only the units of its NRP's sections (the Section column of
karyawan.xlsx) plus SEMUA; the server filters catalog.json and refuses the
files of other sections (ai-worker/src/sections.ts).
"""

from pathlib import Path

SECTION_PREFIX = "SECTION "
# The section of units in the old layout, and of NRPs with no Section column.
DEFAULT_SECTION = "TRACK"
# Units every NRP sees.
SHARED_SECTION = "SEMUA"


def section_name(folder: Path) -> str | None:
    """"TRACK" for a folder named "SECTION TRACK" (any case), else None."""
    name = folder.name
    if name.upper().startswith(SECTION_PREFIX) and name[len(SECTION_PREFIX):].strip():
        return name[len(SECTION_PREFIX):].strip().upper()
    return None


def find_units(source: Path) -> tuple[list[tuple[Path, str, str]], list[str]]:
    """Every unit folder as (folder, section, kelompok), sorted by unit name,
    and the problems found: a unit name used twice (units are stored by name
    alone, units/<UNIT>/, so names must be unique across sections), PDFs
    where a section or kelompok folder was expected."""
    units: list[tuple[Path, str, str]] = []
    problems: list[str] = []
    for top in sorted(d for d in source.iterdir() if d.is_dir()):
        section = section_name(top)
        if section is None:
            # Folders starting with "." or "_" (dist caches, notes) are not units.
            if not top.name.startswith((".", "_")):
                units.append((top, DEFAULT_SECTION, ""))
            continue
        if any(top.glob("*.pdf")):
            problems.append(f"{top.name}: PDF langsung di folder section diabaikan, "
                            f"taruh di {top.name}\\<KELOMPOK>\\<UNIT>\\")
        for kelompok in sorted(d for d in top.iterdir() if d.is_dir()):
            if any(kelompok.glob("*.pdf")):
                problems.append(f"{top.name}\\{kelompok.name}: PDF langsung di folder kelompok diabaikan, "
                                f"taruh di folder unit di dalamnya")
            for unit in sorted(d for d in kelompok.iterdir() if d.is_dir()):
                units.append((unit, section, kelompok.name.strip().upper()))

    seen: dict[str, Path] = {}
    for unit, _, _ in units:
        key = unit.name.upper()
        if key in seen:
            problems.append(f"nama unit {unit.name} dipakai dua kali: {seen[key].relative_to(source)} "
                            f"dan {unit.relative_to(source)}")
        else:
            seen[key] = unit
    units.sort(key=lambda u: u[0].name)
    return units, problems


def is_duplicate_problem(problem: str) -> bool:
    return problem.startswith("nama unit ")
