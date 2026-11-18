// Cetok Online per section. Each section with its own Cetok (a Supabase
// project with the same tables and functions as Track's) has one entry in
// ai-worker/cetok.json; a section without one shows "Fitur sedang dalam
// tahap pengembangan" in the app. Changing cetok.json and merging it
// redeploys this server; phones read it at their next start, so adding a
// section's Cetok needs no app update.

import { DEFAULT_SECTION, sees, type Allowed } from "./sections.ts";

/// One section's Cetok, as written in cetok.json.
export type CetokSite = {
  /// The Supabase project, e.g. "https://xxxx.supabase.co".
  url: string;
  /// Its public (anon) key, the one the Cetok website ships.
  key: string;
  /// The Cetok website, for reference.
  web?: string;
  /// Unit models offered in Input.
  unit?: string[];
  /// true: every location; false: hide some; absent: the admin's choice in
  /// the app (menu ⋮ > Data Cetok Online).
  semua_lokasi?: boolean;
};

/// What a phone gets for each of its sections.
export type CetokSiteOut = { url: string; key: string; web: string; unit: string[]; show_all: boolean };

/// The Cetok sites [allowed] may use (null = admin: all), with the
/// location choice settled: the file's semua_lokasi, else [cetokAll].
export function cetokSitesFor(
  sites: Record<string, unknown>,
  allowed: Allowed,
  cetokAll: boolean,
): Record<string, CetokSiteOut> {
  const out: Record<string, CetokSiteOut> = {};
  for (const [name, raw] of Object.entries(sites)) {
    const section = name.trim().toUpperCase() || DEFAULT_SECTION;
    if (!sees(allowed, section)) continue;
    const s = raw as Partial<CetokSite> | null;
    if (!s || typeof s.url !== "string" || !s.url.startsWith("https://") || typeof s.key !== "string" || !s.key) {
      continue; // a half-filled entry: the section stays "in development"
    }
    out[section] = {
      url: s.url.replace(/\/+$/, ""),
      key: s.key,
      web: typeof s.web === "string" ? s.web : "",
      unit: Array.isArray(s.unit) ? s.unit.map((u) => String(u).trim().toUpperCase()).filter(Boolean) : [],
      show_all: typeof s.semua_lokasi === "boolean" ? s.semua_lokasi : cetokAll,
    };
  }
  return out;
}
