// Usage statistics for admins ("Statistik pemakaian" in the app's ⋮ menu).
// Phones send what their user did to POST /stats (also what they did
// offline, later); the events live in the SQLite of one Durable Object
// (src/stats-db.ts). Admins read them through /admin/stats*.

import { DurableObject } from "cloudflare:workers";
import { employeeRows, requireAdmin, requireSession, type Row, type Session } from "./auth";
import { readCatalog, type FilesEnv } from "./files";
import { DEFAULT_SECTION, SHARED_SECTION, unitSection } from "./sections";
import * as db from "./stats-db";

export interface StatsEnv extends FilesEnv {
  STATS: DurableObjectNamespace<Stats>;
}

export class Stats extends DurableObject<StatsEnv> {
  private sql: db.Sql;

  constructor(ctx: DurableObjectState, env: StatsEnv) {
    super(ctx, env);
    this.sql = ctx.storage.sql as unknown as db.Sql;
    db.setup(this.sql);
  }

  add(who: db.Who, events: db.StatEvent[]) {
    db.add(this.sql, who, events);
  }

  overview(f: db.Filter, sharedUnits: string[]) {
    return db.overview(this.sql, f, sharedUnits);
  }

  manual(f: db.Filter, file: string) {
    return db.manual(this.sql, f, file);
  }

  person(f: db.Filter, nrp: string) {
    return db.person(this.sql, f, nrp);
  }

  answer(id: number) {
    return db.answer(this.sql, id);
  }

  search(f: db.Filter, q: string) {
    return db.search(this.sql, f, q);
  }

  markHandled(q: string) {
    db.markHandled(this.sql, q);
  }
}

const stub = (env: StatsEnv) => env.STATS.get(env.STATS.idFromName("stats"));

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

const who = (s: Session): db.Who => ({ nrp: s.n, name: s.nm, sections: s.s?.length ? s.s : [DEFAULT_SECTION] });

/// A 👍/👎 on a nyel AI answer (src/feedback.ts).
export async function recordRating(env: StatsEnv, s: Session, good: boolean, question: string): Promise<void> {
  await stub(env).add(who(s), [{ at: Date.now(), kind: "rate", q: question.trim().slice(0, 1000), hits: good ? 1 : 0 }]);
}

// The usual order of the section chips; others follow alphabetically.
const ORDER = ["TRACK", "WHEEL", "SUPPORT"];

export async function handleStats(request: Request, env: StatsEnv, path: string): Promise<Response | null> {
  if (request.method !== "POST" || (path !== "/stats" && !path.startsWith("/admin/stats"))) return null;
  let b: Record<string, unknown>;
  try {
    b = (await request.json()) as Record<string, unknown>;
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  if (path === "/stats") {
    const auth = await requireSession(env, request);
    if (auth.error) return auth.error;
    const events = db.clean(b.events);
    if (events.length) await stub(env).add(who(auth.session), events);
    return json({ ok: true, saved: events.length });
  }

  const auth = await requireAdmin(env, request);
  if (auth.error) return auth.error;
  const section = typeof b.section === "string" ? b.section.trim().toUpperCase() : "";
  const f: db.Filter = { since: b.period === "all" ? 0 : Date.now() - 30 * 86400_000, section };
  const text = (v: unknown) => (typeof v === "string" ? v.trim() : "");

  switch (path) {
    case "/admin/stats":
      return json(await overview(env, f));
    case "/admin/stats/manual":
      return json(await stub(env).manual(f, text(b.file)));
    case "/admin/stats/person":
      return json(await stub(env).person(f, text(b.nrp).toUpperCase()));
    case "/admin/stats/answer": {
      const found = await stub(env).answer(Number(b.id) || 0);
      return found ? json(found) : json({ error: "not_found", message: "Pertanyaan tidak ditemukan." }, 404);
    }
    case "/admin/stats/search":
      return json(await stub(env).search(f, text(b.q)));
    case "/admin/stats/handled":
      if (!text(b.q)) return json({ error: "bad_request" }, 400);
      await stub(env).markHandled(text(b.q));
      return json({ ok: true });
  }
  return json({ error: "not_found" }, 404);
}

async function overview(env: StatsEnv, f: db.Filter) {
  const [catalog, employees] = await Promise.all([readCatalog(env), employeeRows(env)]);
  const shared = (catalog?.units ?? []).filter((u) => unitSection(u) === SHARED_SECTION).map((u) => u.id);
  const o = await stub(env).overview(f, shared);

  const staff = [...employees].filter(([, r]) => r.active);
  const all = [...new Set(staff.flatMap(([, r]) => r.sections))].filter((x) => x !== SHARED_SECTION);
  const sections = [...ORDER, ...all.filter((x) => !ORDER.includes(x)).sort()];
  const inSection = (r: Row) => !f.section || r.sections.includes(f.section);
  const users = staff.filter(([, r]) => inSection(r));
  const busy = new Set(o.people.map((p) => p.nrp));
  const { last, ...rest } = o;

  return {
    ...rest,
    section_list: sections,
    users: users.length,
    active: users.filter(([nrp]) => busy.has(nrp)).length,
    per_section: (f.section ? [f.section] : sections).map((sec) => {
      const members = staff.filter(([, r]) => r.sections.includes(sec));
      return { section: sec, total: members.length, active: members.filter(([nrp]) => busy.has(nrp)).length };
    }),
    // Names from the employee list, which follows karyawan.xlsx.
    people: o.people.map((p) => ({ ...p, name: employees.get(p.nrp)?.name ?? p.name })),
    inactive: users
      .filter(([nrp]) => !busy.has(nrp))
      .map(([nrp, r]) => ({
        nrp,
        name: r.name,
        sections: r.sections,
        // Never logged in, or the last time they used the app (or, before
        // statistics, logged in).
        never: r.status === "new" && !last[nrp],
        last: last[nrp] ?? r.seen * 1000,
      }))
      .sort((x, y) => x.name.localeCompare(y.name)),
  };
}
