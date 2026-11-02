// Which manuals an NRP may see. Every unit in catalog.json has a "section"
// (TRACK, WHEEL, ...; tools/sections.py); an employee has the sections of
// the Section column in karyawan.xlsx. A phone gets a catalog with only its
// sections' units plus SEMUA, and files.ts refuses the files of the others.
// Admins see every section.

/// The section of units in catalogs built before sections, and of
/// employees imported before the Section column.
export const DEFAULT_SECTION = "TRACK";
/// Units every NRP sees (Panduan MLU, Basic Electric, ...).
export const SHARED_SECTION = "SEMUA";

type CatalogUnit = { id: string; section?: string };
export type Catalog = { units: CatalogUnit[]; [k: string]: unknown };

/// null = every section (admins).
export type Allowed = string[] | null;

export const unitSection = (u: CatalogUnit) => (u.section || DEFAULT_SECTION).toUpperCase();

export function sees(allowed: Allowed, section: string): boolean {
  return allowed === null || section === SHARED_SECTION || allowed.includes(section);
}

/// The catalog as [allowed] may see it. hidden_units names the units left
/// out, so a phone whose NRP moved to another section removes their
/// downloaded manuals (a unit taken off the server keeps them).
export function filterCatalog(catalog: Catalog, allowed: Allowed): Catalog {
  if (allowed === null) return catalog;
  const units = catalog.units.filter((u) => sees(allowed, unitSection(u)));
  const hidden = catalog.units.filter((u) => !sees(allowed, unitSection(u))).map((u) => u.id);
  return { ...catalog, units, hidden_units: hidden };
}

/// "PC210" for "units/PC210/sm.pdf"; null for keys outside units/.
export function unitOfKey(key: string): string | null {
  const m = /^units\/([^/]+)\//.exec(key);
  return m ? m[1] : null;
}

/// Section of each unit id in the catalog.
export function sectionMap(catalog: Catalog): Map<string, string> {
  return new Map(catalog.units.map((u) => [u.id, unitSection(u)]));
}

/// Cleaned section names from an import row: ["TRACK", "WHEEL"], or null
/// when the row has none (sent by an upload_karyawan.py from before sections).
export function cleanSections(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const names = [...new Set(value.map((v) => String(v ?? "").trim().toUpperCase()).filter(Boolean))];
  return names.length ? names : null;
}
