// Daily Inspection's sheet logic (no Cloudflare or login parts, so the
// tests run it with a fake sheet); the endpoints are in inspection.ts.

import type { Session } from "./auth.ts";
import { SheetsError, type Sheets } from "./google.ts";

export const SECTIONS = ["TRACK", "WHEEL", "SUPPORT"] as const;
export const POP_TAB = "POP UNIT AMM-SBS";
const FIRST_ROW = 5;
const LAST_ROW = 3000;
export const HEALTH_KEY = "inspection:health";

// Column positions inside B..Q.
const C = { no: 0, kase: 1, inspector: 2, leader: 3, unit: 4, model: 5, hm: 6, date: 7, problem: 8, action: 9, status: 11, section: 15 };

export type Finding = {
  row: number;
  case: string;
  inspector: string;
  leader: string;
  unit: string;
  model: string;
  hm: string;
  date: string;
  problem: string;
  action: string;
  status: "OPEN" | "CLOSE";
};

export type PopUnit = { unit: string; model: string; section: string };

export const tabName = (pattern: string, section: string) => pattern.replace("{SECTION}", section);
const q = (tab: string) => `'${tab.replace(/'/g, "''")}'`;
const cell = (row: string[] | undefined, i: number) => (row?.[i] ?? "").trim();

/// "e-51 38" -> "E5138": how unit codes are compared.
export const unitKey = (s: string) => s.toUpperCase().replace(/[\s.\-]/g, "");

/// Rows B5:Q of a tab -> its findings (rows with a problem).
export function parseFindings(values: string[][]): Finding[] {
  const out: Finding[] = [];
  values.forEach((r, i) => {
    const problem = cell(r, C.problem);
    if (!problem) return;
    const action = cell(r, C.action);
    out.push({
      row: FIRST_ROW + i,
      case: cell(r, C.kase),
      inspector: cell(r, C.inspector),
      leader: cell(r, C.leader),
      unit: cell(r, C.unit),
      model: cell(r, C.model),
      hm: cell(r, C.hm),
      date: cell(r, C.date),
      problem,
      action,
      status: action ? "CLOSE" : "OPEN",
    });
  });
  return out;
}

/// The first row with neither a unit nor a problem.
export function firstFreeRow(values: string[][]): number {
  for (let i = 0; i < values.length; i++) {
    if (!cell(values[i], C.unit) && !cell(values[i], C.problem)) return FIRST_ROW + i;
  }
  return FIRST_ROW + values.length;
}

/// Rows B8:R of POP UNIT -> its units (group title rows have no code).
export function parsePop(values: string[][]): PopUnit[] {
  const out: PopUnit[] = [];
  for (const r of values) {
    const unit = cell(r, 1);
    const section = cell(r, 16).toUpperCase();
    if (!unit || !unitKey(unit)) continue;
    out.push({ unit: unit.toUpperCase(), model: cell(r, 5), section });
  }
  return out;
}

export function popIndex(pop: PopUnit[]): Map<string, PopUnit> {
  return new Map(pop.map((u) => [unitKey(u.unit), u]));
}

function distance(a: string, b: string): number {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
  }
  return d[a.length][b.length];
}

/// Group leaders of a tab, most frequent first: the first name of NAME
/// LEADER ("EKO. W" -> EKO), typos folded into the common spelling
/// (SOFIYAN -> SOFYAN), unit codes typed into the column skipped.
export function leaderNames(findings: Finding[], pop: Map<string, PopUnit>, max = 8): string[] {
  const counts = new Map<string, number>();
  for (const f of findings) {
    const name = f.leader.toUpperCase().replace(/[^A-Z\s]/g, " ").trim().split(/\s+/)[0] ?? "";
    if (name.length < 3 || pop.has(unitKey(f.leader)) || /\d/.test(f.leader.split(/\s+/)[0] ?? "")) continue;
    counts.set(name, (counts.get(name) ?? 0) + 1);
  }
  const ranked = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const kept: string[] = [];
  for (const [name] of ranked) {
    if (kept.some((k) => k.length >= 4 && distance(k, name) <= 1)) continue;
    kept.push(name);
  }
  return kept.slice(0, max);
}

/// Text typed by a mechanic, kept as text (not read as a formula).
export const asText = (s: string) => (/^[=+\-@]/.test(s) ? `'${s}` : s);

/// Now in WIB as the sheet's LAST UPDATE is typed: "14/11/2026 13:05:00".
export function wibStamp(now = Date.now()): string {
  const d = new Date(now + 7 * 3600_000);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getUTCDate())}/${p(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} ${d.getUTCHours()}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`;
}

/// The first word of the login name, as the sheet writes inspectors.
export const inspectorOf = (s: Session) => (s.nm || s.n).trim().toUpperCase().split(/\s+/)[0] ?? s.n;

export type Health = { ok: boolean; at: number; message?: string };

/// Everything inspection needs; [sheets] and [kv] are fakes in the tests.
export type Ctx = { sheets: Sheets; tab: string; kv?: KVNamespace; now?: number };

const tabOf = (ctx: Ctx, section: string) => tabName(ctx.tab, section);

export async function readAll(ctx: Ctx, sections: string[]) {
  const ranges = sections.flatMap((s) => [`${q(tabOf(ctx, s))}!B${FIRST_ROW}:Q${LAST_ROW}`, `${q(tabOf(ctx, s))}!T3`]);
  const got = await ctx.sheets.read([...ranges, `${q(POP_TAB)}!B8:R2000`]);
  const pop = parsePop(got[got.length - 1] ?? []);
  const index = popIndex(pop);
  const tabs: Record<string, { updated: string; rows: Finding[]; leaders: string[] }> = {};
  sections.forEach((s, i) => {
    const rows = parseFindings(got[i * 2] ?? []);
    tabs[s] = { updated: cell(got[i * 2 + 1]?.[0], 0), rows, leaders: leaderNames(rows, index) };
  });
  return { tabs, pop };
}

export type Fail = { error: string; message: string; status: number };
const fail = (status: number, error: string, message: string): Fail => ({ status, error, message });

/// Writes ACTION of the finding [row]; when rows moved (the admin sorted
/// the sheet), finds it again by unit and problem.
export async function writeAction(
  ctx: Ctx,
  b: { section: string; row: number; unit: string; problem: string; action: string },
): Promise<{ row: number; status: "OPEN" | "CLOSE" } | Fail> {
  const tab = q(tabOf(ctx, b.section));
  const same = (r: string[] | undefined) =>
    unitKey(cell(r, C.unit)) === unitKey(b.unit) && cell(r, C.problem).toUpperCase() === b.problem.trim().toUpperCase();
  let row = b.row;
  const [one] = await ctx.sheets.read([`${tab}!B${row}:Q${row}`]);
  if (row < FIRST_ROW || !same(one?.[0])) {
    const [all] = await ctx.sheets.read([`${tab}!B${FIRST_ROW}:Q${LAST_ROW}`]);
    const hits = (all ?? []).map((r, i) => (same(r) ? FIRST_ROW + i : 0)).filter(Boolean);
    if (hits.length !== 1) {
      return fail(409, "moved", "Temuan ini sudah berubah atau dihapus di sheet. Tarik ulang daftar lalu coba lagi.");
    }
    row = hits[0];
  }
  const action = b.action.trim().toUpperCase();
  await ctx.sheets.write([
    { range: `${tab}!K${row}`, values: [[asText(action)]] },
    { range: `${tab}!T3`, values: [[wibStamp(ctx.now)]] },
  ]);
  return { row, status: action ? "CLOSE" : "OPEN" };
}

export type NewFindings = {
  section: string;
  unit: string;
  model: string;
  hm: string;
  date: string;
  leader: string;
  problems: string[];
  inspector: string;
};

/// dd/mm/yyyy, or null.
export function cleanDate(s: string): string | null {
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(s.trim());
  if (!m) return null;
  const [d, mo] = [Number(m[1]), Number(m[2])];
  if (d < 1 || d > 31 || mo < 1 || mo > 12) return null;
  return `${m[1].padStart(2, "0")}/${m[2].padStart(2, "0")}/${m[3]}`;
}

/// Puts one row per problem into the first free rows of the tab.
export async function addFindings(ctx: Ctx, b: NewFindings): Promise<{ rows: number[] } | Fail> {
  const problems = b.problems.map((p) => p.trim().toUpperCase()).filter(Boolean);
  const unit = b.unit.trim().toUpperCase();
  const date = cleanDate(b.date);
  const hm = b.hm.trim().replace(",", ".");
  const leader = b.leader.trim().toUpperCase();
  if (!unitKey(unit) || !problems.length || !leader || !date || !/^\d+(\.\d+)?$/.test(hm)) {
    return fail(400, "bad_request", "Isian belum lengkap: kode unit, HM, tanggal, leader dan problem.");
  }
  const tab = q(tabOf(ctx, b.section));
  const [all, popRows] = await ctx.sheets.read([`${tab}!B${FIRST_ROW}:Q${LAST_ROW}`, `${q(POP_TAB)}!B8:R2000`]);
  const known = popIndex(parsePop(popRows ?? [])).get(unitKey(unit));
  if (known && known.section && known.section !== b.section) {
    return fail(400, "other_section", `Unit ${known.unit} milik section ${known.section}.`);
  }
  const model = known?.model || b.model.trim().toUpperCase();
  if (!model) return fail(400, "model", "Unit ini belum ada di POP UNIT, isi model unitnya.");
  const code = known?.unit ?? unit;
  const start = firstFreeRow(all ?? []);
  const data: { range: string; values: string[][] }[] = [];
  const rows: number[] = [];
  problems.forEach((problem, i) => {
    const r = start + i;
    rows.push(r);
    const no = r === FIRST_ROW ? "1" : `=B${r - 1}+1`;
    data.push(
      {
        range: `${tab}!B${r}:J${r}`,
        values: [[no, String(i + 1), asText(b.inspector), asText(leader), asText(code), asText(model), hm, date, asText(problem)]],
      },
      { range: `${tab}!M${r}`, values: [[`=IF(J${r}="","",IF(K${r}="","OPEN","CLOSE"))`]] },
      {
        // As the admin's rows: the section looked up in POP UNIT; a unit
        // not in POP UNIT yet gets the inspector's section as text.
        range: `${tab}!Q${r}`,
        values: [[known ? `=IFERROR(VLOOKUP(F${r},${q(POP_TAB)}!$C:$R,16,0)," ")` : b.section]],
      },
    );
  });
  data.push({ range: `${tab}!T3`, values: [[wibStamp(ctx.now)]] });
  await ctx.sheets.write(data);
  return { rows };
}

/// Can the robot still read and write the sheet? Run every night; a
/// failure is shown to admins on the Daily Inspection screen.
export async function checkHealth(ctx: Ctx): Promise<Health> {
  const at = ctx.now ?? Date.now();
  let health: Health;
  try {
    const got = await ctx.sheets.read([...SECTIONS.map((s) => `${q(tabOf(ctx, s))}!T3`), `${q(POP_TAB)}!C7`]);
    if (got.length < SECTIONS.length + 1) throw new SheetsError(500, "Sebagian tab tidak terbaca.");
    health = { ok: true, at };
  } catch (e) {
    health = { ok: false, at, message: messageOf(e) };
  }
  await ctx.kv?.put(HEALTH_KEY, JSON.stringify(health));
  return health;
}

export function messageOf(e: unknown): string {
  if (e instanceof SheetsError && (e.status === 403 || e.status === 404)) {
    return "Robot tidak punya akses ke sheet lagi (izin link mungkin diubah). Tambahkan e-mail robot sebagai editor sheet.";
  }
  if (e instanceof SheetsError && e.status === 400) {
    return `Nama tab di sheet berubah atau tidak ditemukan (${e.message}).`;
  }
  return e instanceof Error ? e.message : String(e);
}

