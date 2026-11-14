// Daily Inspection Monitoring: the admin's Google Sheet "MASTER DATA
// MONITORING DAILY INSPECTION", read and written for the app through the
// robot account (google.ts). Every call needs the NRP login; an NRP sees
// only the tabs of its sections (admins see all three).
//
//   GET  /inspection          the findings of the caller's sections, the
//                             unit population (POP UNIT) and leader names
//   POST /inspection/action   {section, row, unit, problem, action}: writes
//                             ACTION (the sheet's STATUS formula then says
//                             CLOSE; an empty action makes it OPEN again)
//   POST /inspection/add      {id, section, unit, model, hm, date, leader,
//                             problems: [...]}: new rows, one per problem
//
// Sheet layout (each "INSPECTION <SECTION> OPEN 2026" tab): header in row
// 3, data from row 5, columns B..Q = No, NO CASE, NAME INSPECTOR, NAME
// LEADER, CODE UNIT, MODEL UNIT, HM, DATE, PROBLEM, ACTION, REMARK, STATUS,
// NUMBER WO, ETA PLAN SERVICE, (empty), SECTION; T3 = last update. Rows
// below the data already hold the No, REMARK, STATUS and SECTION formulas,
// so a new finding goes into the first row with no unit and no problem.
// "POP UNIT AMM-SBS": data from row 8, CODE UNIT in C, MODEL UNIT in G,
// SECTION in R.

import { allowedOf, requireSession, type AuthEnv, type Session } from "./auth";
import { googleSheets, parseServiceAccount, SheetsError, type Sheets } from "./google";
import {
  addFindings,
  checkHealth,
  HEALTH_KEY,
  inspectorOf,
  messageOf,
  readAll,
  SECTIONS,
  writeAction,
  type Ctx,
  type Fail,
  type Health,
} from "./inspection-sheet";
import { json, readBody } from "./quiz";

export interface InspectionEnv extends AuthEnv {
  /// The robot's JSON key (secret; see google.ts).
  GOOGLE_SERVICE_ACCOUNT?: string;
  INSPECTION_SHEET_ID: string;
  /// Tab name with {SECTION} in it, e.g. "INSPECTION {SECTION} OPEN 2026".
  INSPECTION_TAB: string;
}

/// The sections of [s] that have a tab; all three for admins.
export function inspectionSections(s: Session): string[] {
  const allowed = allowedOf(s);
  return allowed === null ? [...SECTIONS] : SECTIONS.filter((x) => allowed.includes(x));
}

export function sheetsOf(env: InspectionEnv): Sheets | null {
  const account = parseServiceAccount(env.GOOGLE_SERVICE_ACCOUNT);
  return account ? googleSheets(account, env.INSPECTION_SHEET_ID) : null;
}

/// Nightly: checks the robot's access (index.ts calls it from the cron).
export async function scheduledInspection(env: InspectionEnv): Promise<void> {
  const sheets = sheetsOf(env);
  if (!sheets) return;
  const health = await checkHealth({ sheets, tab: env.INSPECTION_TAB, kv: env.AUTH });
  console.log("inspection health", JSON.stringify(health));
}

/// Handles /inspection*; null for other paths. [make] is replaced in tests.
export async function handleInspection(
  request: Request,
  env: InspectionEnv,
  path: string,
  make: (env: InspectionEnv) => Sheets | null = sheetsOf,
): Promise<Response | null> {
  if (path !== "/inspection" && !path.startsWith("/inspection/")) return null;
  const auth = await requireSession(env, request);
  if (auth.error) return auth.error;
  const s = auth.session;
  const sections = inspectionSections(s);
  if (!sections.length) {
    return json({ error: "section", message: "Daily Inspection hanya untuk section Track, Wheel dan Support." }, 403);
  }
  const sheets = make(env);
  if (!sheets) return json({ error: "setup", message: "Daily Inspection belum disiapkan admin (akun robot Google)." }, 503);
  const ctx: Ctx = { sheets, tab: env.INSPECTION_TAB, kv: env.AUTH };
  const sheetUrl = `https://docs.google.com/spreadsheets/d/${env.INSPECTION_SHEET_ID}/edit`;
  try {
    if (request.method === "GET" && path === "/inspection") {
      const { tabs, pop } = await readAll(ctx, sections);
      const health = s.a ? ((await env.AUTH.get(HEALTH_KEY, "json")) as Health | null) : null;
      return json({
        sections,
        sheet_url: sheetUrl,
        inspector: inspectorOf(s),
        tabs,
        pop: pop.map((u) => [u.unit, u.model, u.section]),
        ...(health && !health.ok ? { health } : {}),
      });
    }
    if (request.method !== "POST") return json({ error: "method" }, 405);
    const b = await readBody(request);
    if (!b) return json({ error: "bad_request" }, 400);
    const section = String(b.section ?? "").toUpperCase();
    if (!sections.includes(section)) {
      return json({ error: "section", message: `NRP ini tidak punya akses ke section ${section || "-"}.` }, 403);
    }
    let result: Record<string, unknown> | Fail;
    if (path === "/inspection/action") {
      result = await writeAction(ctx, {
        section,
        row: Number(b.row) || 0,
        unit: String(b.unit ?? ""),
        problem: String(b.problem ?? ""),
        action: String(b.action ?? ""),
      });
    } else if (path === "/inspection/add") {
      // A queued add sent twice (the answer got lost) is written once.
      const id = String(b.id ?? "").slice(0, 64);
      const doneKey = id ? `inspection:add:${s.n}:${id}` : "";
      const done = doneKey ? await env.AUTH.get(doneKey) : null;
      if (done) return json(JSON.parse(done));
      result = await addFindings(ctx, {
        section,
        unit: String(b.unit ?? ""),
        model: String(b.model ?? ""),
        hm: String(b.hm ?? ""),
        date: String(b.date ?? ""),
        leader: String(b.leader ?? ""),
        problems: Array.isArray(b.problems) ? b.problems.map((p) => String(p ?? "")) : [],
        inspector: inspectorOf(s),
      });
      if (doneKey && !("error" in result)) {
        await env.AUTH.put(doneKey, JSON.stringify(result), { expirationTtl: 7 * 86400 });
      }
    } else {
      return json({ error: "not_found" }, 404);
    }
    if ("error" in result) return json({ error: result.error, message: result.message }, result.status as number);
    return json(result);
  } catch (e) {
    console.log("inspection failed", path, String(e));
    if (e instanceof SheetsError && (e.status === 403 || e.status === 404)) {
      await env.AUTH.put(HEALTH_KEY, JSON.stringify({ ok: false, at: Date.now(), message: messageOf(e) }));
    }
    return json({ error: "sheet", message: `Sheet tidak bisa dibuka sekarang. ${messageOf(e)}` }, 502);
  }
}
