// Usage statistics for admins ("Statistik pemakaian" in the app's ⋮ menu).
// Phones send what their user did to POST /stats (also what they did
// offline, later); the events live in the SQLite of one Durable Object
// (src/stats-db.ts). Admins read them through /admin/stats*.

import { DurableObject } from "cloudflare:workers";
import { employeeRows, requireAdmin, requireSession, type Row, type Session } from "./auth";
import { readCatalog, type FilesEnv } from "./files";
import { DEFAULT_SECTION, SHARED_SECTION, unitSection } from "./sections";
import * as db from "./stats-db";
import { xlsx, type Cell } from "./xlsx";

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

  totals(f: db.Filter) {
    return db.totals(this.sql, f);
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
  if (s.a) return;
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
    // Admins test the app; their use is not what the statistics are about.
    if (auth.session.a) return json({ ok: true, saved: 0 });
    const events = db.clean(b.events);
    if (events.length) await stub(env).add(who(auth.session), events);
    return json({ ok: true, saved: events.length });
  }

  const auth = await requireAdmin(env, request);
  if (auth.error) return auth.error;
  const section = typeof b.section === "string" ? b.section.trim().toUpperCase() : "";
  const days = b.period === "all" ? 0 : b.period === "7" ? 7 : 30;
  const f: db.Filter = { since: days ? Date.now() - days * 86400_000 : 0, section };
  const text = (v: unknown) => (typeof v === "string" ? v.trim() : "");

  switch (path) {
    case "/admin/stats":
      return json(await overview(env, f));
    case "/admin/stats/report": {
      const month = monthOf(text(b.month));
      if (!month) return json({ error: "bad_request" }, 400);
      return new Response(await report(env, { since: month.since, until: month.until, section }, month.label), {
        headers: {
          "content-type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          "content-disposition": `attachment; filename="statistik-${text(b.month)}.xlsx"`,
        },
      });
    }
    case "/admin/stats/manual":
      return json(await stub(env).manual(f, text(b.file)));
    case "/admin/stats/person": {
      const nrp = text(b.nrp).toUpperCase();
      const [p, employees] = await Promise.all([stub(env).person(f, nrp), employeeRows(env)]);
      return json({ ...p, app: employees.get(nrp)?.app ?? "" });
    }
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

/// Sections with a manual of their own (not counting the ones every section
/// sees); people of the others cannot be expected to use the app yet.
function sectionsWithManuals(catalog: Awaited<ReturnType<typeof readCatalog>>): Set<string> {
  return new Set((catalog?.units ?? []).map(unitSection).filter((x) => x !== SHARED_SECTION));
}

/// Change against the period before, in percent; null when there is
/// nothing to compare with.
const change = (now: number, before: number) => (before > 0 ? Math.round(((now - before) / before) * 100) : null);

async function overview(env: StatsEnv, f: db.Filter) {
  const [catalog, employees] = await Promise.all([readCatalog(env), employeeRows(env)]);
  const shared = (catalog?.units ?? []).filter((u) => unitSection(u) === SHARED_SECTION).map((u) => u.id);
  const withManuals = sectionsWithManuals(catalog);
  const length = f.since ? (f.until ?? Date.now()) - f.since : 0;
  const [o, before] = await Promise.all([
    stub(env).overview(f, shared),
    length ? stub(env).totals({ since: f.since - length, until: f.since, section: f.section }) : null,
  ]);

  // Admins are not counted (their use is not recorded either).
  const staff = [...employees].filter(([, r]) => r.active && !r.admin);
  const all = [...new Set(staff.flatMap(([, r]) => r.sections))].filter((x) => x !== SHARED_SECTION);
  const sections = [...ORDER, ...all.filter((x) => !ORDER.includes(x)).sort()];
  // On "Semua", people whose sections have no manual yet are left out of
  // "Pengguna aktif" and "belum aktif"; their section says so instead.
  const inSection = (r: Row) =>
    f.section ? r.sections.includes(f.section) : r.sections.some((x) => withManuals.has(x));
  const users = staff.filter(([, r]) => inSection(r));
  const busy = new Set(o.people.map((p) => p.nrp));
  const { last, by_section, ...rest } = o;
  const active = users.filter(([nrp]) => busy.has(nrp)).length;
  const wasBusy = new Set(before?.nrps ?? []);

  return {
    ...rest,
    section_list: sections,
    no_manual: sections.filter((x) => !withManuals.has(x)),
    users: users.length,
    active,
    trend: before
      ? {
          active: change(active, users.filter(([nrp]) => wasBusy.has(nrp)).length),
          opens: change(o.opens, before.opens),
          ai: change(o.ai, before.ai),
        }
      : null,
    per_section: (f.section ? [f.section] : sections).map((sec) => {
      const members = staff.filter(([, r]) => r.sections.includes(sec));
      const there = new Set(by_section[sec] ?? []);
      return {
        section: sec,
        total: members.length,
        active: members.filter(([nrp]) => there.has(nrp)).length,
        has_manual: withManuals.has(sec),
      };
    }),
    // Names from the employee list, which follows karyawan.xlsx.
    people: o.people
      .filter((p) => !employees.get(p.nrp)?.admin)
      .map((p) => ({ ...p, name: employees.get(p.nrp)?.name ?? p.name })),
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
        // Logged in on a phone whose APK is older than the statistics, so
        // what they do is not recorded.
        old_app: r.devices.length > 0 && !r.app,
      }))
      .sort((x, y) => x.name.localeCompare(y.name)),
  };
}

const MONTHS = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
// The site's clock (WIB).
const ZONE = 7 * 3600_000;

/// "2026-10": that month in WIB.
function monthOf(v: string): { since: number; until: number; label: string } | null {
  const m = /^(\d{4})-(\d{2})$/.exec(v);
  if (!m) return null;
  const y = Number(m[1]);
  const i = Number(m[2]) - 1;
  if (i < 0 || i > 11) return null;
  return { since: Date.UTC(y, i, 1) - ZONE, until: Date.UTC(y, i + 1, 1) - ZONE, label: `${MONTHS[i]} ${y}` };
}

const day = (ms: number) => {
  const d = new Date(ms + ZONE);
  return `${String(d.getUTCDate()).padStart(2, "0")}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${d.getUTCFullYear()}`;
};

/// The monthly report: what the screen shows, one sheet per list.
export async function report(env: StatsEnv, f: db.Filter, label: string): Promise<Uint8Array> {
  const o = await overview(env, f);
  const head = (...cells: Cell[]) => cells;
  return xlsx([
    {
      name: "Ringkasan",
      rows: [
        head("Statistik pemakaian MyManual", ""),
        ["Bulan", label],
        ["Section", f.section || "Semua section"],
        ["Pengguna aktif", o.active],
        ["Jumlah pengguna", o.users],
        ["Manual dibuka", o.opens],
        ["Tanya nyel AI", o.ai],
        ["Jawaban membantu", o.ratings.good],
        ["Jawaban dinilai salah", o.ratings.bad],
        ["Kata tidak ketemu", o.missing.length],
      ],
    },
    {
      name: "Per section",
      rows: [
        head("Section", "Aktif", "Jumlah orang", "Keterangan"),
        ...o.per_section.map((p) => [p.section, p.active, p.total, p.has_manual ? "" : "belum ada manual"]),
      ],
    },
    {
      name: "Manual teratas",
      rows: [
        head("Manual", "Unit", "Dibuka", "Orang"),
        ...o.manuals.map((m) => [m.title, m.shared ? "Semua section" : m.unit, m.n, m.people]),
      ],
    },
    { name: "Paling dicari", rows: [head("Kata", "Dicari", "Orang"), ...o.searches.map((x) => [x.q, x.n, x.people])] },
    { name: "Tidak ketemu", rows: [head("Kata", "Dicari", "Orang"), ...o.missing.map((x) => [x.q, x.n, x.people])] },
    { name: "Topik nyel AI", rows: [head("Topik", "Pertanyaan"), ...o.topics.map((t) => [t.name, t.n])] },
    {
      name: "Pengguna",
      rows: [
        head("NRP", "Nama", "Section", "Manual dibuka", "Tanya nyel AI", "Cari", "Terakhir aktif"),
        ...o.people.map((p) => [p.nrp, p.name, p.sections.join(", "), p.manuals, p.ai, p.searches, day(p.last)]),
      ],
    },
    {
      name: "Belum aktif",
      rows: [
        head("NRP", "Nama", "Section", "Keterangan"),
        ...o.inactive.map((p) => [
          p.nrp, p.name, p.sections.join(", "),
          p.never || !p.last ? "Belum pernah login" : `Terakhir ${day(p.last)}${p.old_app ? " (app lama)" : ""}`,
        ]),
      ],
    },
  ]);
}
