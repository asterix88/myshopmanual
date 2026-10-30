// What "Statistik pemakaian" (admin) shows, from one table of events: a
// phone opening a manual, viewing a chapter, downloading, searching, asking
// nyel AI, and the 👍/👎 ratings. Phones keep events while offline and send
// them to POST /stats later (src/stats.ts); the NRP, name and sections come
// from the session, so the section filter is the reader's section.
//
// Plain SQL on the SQLite of one Durable Object; the functions take the
// database as a parameter so the tests run them on node:sqlite.

export interface Sql {
  exec(query: string, ...bindings: unknown[]): { toArray(): Record<string, unknown>[] };
}

export type Kind = "open" | "chapter" | "download" | "search" | "ai" | "rate";

/// One row. q: the search, the chapter title, or the question; hits: search
/// results (0 = not found in any manual), or 1/0 for a 👍/👎 rating; extra:
/// JSON, for "ai" {answer, sources, queries}.
export type StatEvent = {
  at: number;
  kind: Kind;
  unit?: string;
  file?: string;
  title?: string;
  q?: string;
  hits?: number;
  extra?: unknown;
};

export type Who = { nrp: string; name: string; sections: string[] };

const KINDS = new Set<Kind>(["open", "chapter", "download", "search", "ai", "rate"]);
const LIST = 20;

export function setup(sql: Sql): void {
  sql.exec(`CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY,
    at INTEGER NOT NULL,
    nrp TEXT NOT NULL,
    name TEXT NOT NULL,
    secs TEXT NOT NULL,
    kind TEXT NOT NULL,
    unit TEXT NOT NULL DEFAULT '',
    file TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL DEFAULT '',
    q TEXT NOT NULL DEFAULT '',
    hits INTEGER NOT NULL DEFAULT 0,
    extra TEXT NOT NULL DEFAULT ''
  )`);
  sql.exec("CREATE INDEX IF NOT EXISTS events_kind ON events (kind, at)");
  sql.exec("CREATE INDEX IF NOT EXISTS events_nrp ON events (nrp, at)");
  sql.exec("CREATE INDEX IF NOT EXISTS events_file ON events (file, kind)");
  // Searches an admin marked "sudah ditangani": hidden from "Tidak ketemu"
  // until someone searches them again after that.
  sql.exec("CREATE TABLE IF NOT EXISTS handled (q TEXT PRIMARY KEY, at INTEGER NOT NULL)");
}

const str = (v: unknown, max: number) => (typeof v === "string" ? v.trim().slice(0, max) : "");
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? Math.max(0, Math.floor(v)) : 0);

/// Keeps the events that make sense; times outside the last 90 days (a
/// phone with a wrong clock) become now.
export function clean(raw: unknown, now = Date.now()): StatEvent[] {
  if (!Array.isArray(raw)) return [];
  const out: StatEvent[] = [];
  for (const r of raw.slice(0, 500)) {
    if (!r || typeof r !== "object") continue;
    const e = r as Record<string, unknown>;
    const kind = e.kind as Kind;
    if (!KINDS.has(kind) || kind === "rate") continue;
    const at = num(e.at);
    const event: StatEvent = {
      at: at > now - 90 * 86400_000 && at <= now + 3600_000 ? Math.min(at, now) : now,
      kind,
      unit: str(e.unit, 80),
      file: str(e.file, 300),
      title: str(e.title, 200),
      q: str(e.q, 1000),
      hits: num(e.hits),
    };
    if (kind === "ai") {
      const x = (e.extra ?? {}) as Record<string, unknown>;
      const list = (v: unknown, n: number, max: number) =>
        Array.isArray(v) ? v.slice(0, n).map((s) => str(s, max)).filter(Boolean) : [];
      event.extra = { answer: str(x.answer, 6000), sources: list(x.sources, 12, 120), queries: list(x.queries, 12, 200) };
    }
    if ((kind === "search" || kind === "ai" || kind === "chapter") && !event.q) continue;
    if ((kind === "open" || kind === "chapter" || kind === "download") && !event.file) continue;
    out.push(event);
  }
  return out;
}

export function add(sql: Sql, who: Who, events: StatEvent[]): void {
  const secs = `,${who.sections.join(",")},`;
  for (const e of events) {
    sql.exec(
      "INSERT INTO events (at, nrp, name, secs, kind, unit, file, title, q, hits, extra) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      e.at, who.nrp, who.name, secs, e.kind, e.unit ?? "", e.file ?? "", e.title ?? "", e.q ?? "", e.hits ?? 0,
      e.extra === undefined ? "" : JSON.stringify(e.extra),
    );
  }
}

/// since: ms (0 = all time); section: "" = every section.
export type Filter = { since: number; section: string };

const where = (f: Filter, alias = "") =>
  `${alias}at >= ${Math.floor(f.since)} AND (? = '' OR ${alias}secs LIKE ?)`;
const binds = (f: Filter) => [f.section, `%,${f.section},%`];

type Row = Record<string, unknown>;
const rows = (sql: Sql, query: string, ...b: unknown[]) => sql.exec(query, ...b).toArray();
const n = (v: unknown) => Number(v ?? 0);
const s = (v: unknown) => String(v ?? "");
const secsOf = (v: unknown) => s(v).split(",").filter(Boolean);

/// shared: units every section sees (Panduan MLU, Basic Electric); they are
/// listed with the manuals but left out of "Per unit".
export function overview(sql: Sql, f: Filter, sharedUnits: string[]) {
  const shared = (unit: string) => sharedUnits.includes(unit);
  const w = where(f);
  const b = binds(f);
  const count = (kind: Kind) => n(rows(sql, `SELECT COUNT(*) AS c FROM events WHERE kind = '${kind}' AND ${w}`, ...b)[0]?.c);

  const manuals = rows(
    sql,
    `SELECT file, MAX(unit) AS unit, MAX(title) AS title, COUNT(*) AS n, COUNT(DISTINCT nrp) AS people
     FROM events WHERE kind = 'open' AND ${w} GROUP BY file ORDER BY n DESC, title LIMIT ${LIST}`,
    ...b,
  ).map((r) => ({ file: s(r.file), unit: s(r.unit), title: s(r.title), n: n(r.n), people: n(r.people), shared: shared(s(r.unit)) }));

  const units = rows(
    sql,
    `SELECT unit, COUNT(*) AS n FROM events WHERE kind = 'open' AND unit != '' AND ${w} GROUP BY unit ORDER BY n DESC`,
    ...b,
  )
    .filter((r) => !shared(s(r.unit)))
    .map((r) => ({ unit: s(r.unit), n: n(r.n) }));

  const asked = rows(sql, `SELECT extra FROM events WHERE kind = 'ai' AND ${w} ORDER BY at DESC LIMIT 2000`, ...b);
  const rated = rows(sql, `SELECT hits, COUNT(*) AS c FROM events WHERE kind = 'rate' AND ${w} GROUP BY hits`, ...b);

  const questions = rows(
    sql,
    `SELECT id, at, nrp, name, secs, unit, q FROM events WHERE kind = 'ai' AND ${w} ORDER BY at DESC, id DESC LIMIT ${LIST}`,
    ...b,
  ).map(question);

  const searches = rows(
    sql,
    `SELECT LOWER(q) AS q, COUNT(*) AS n, COUNT(DISTINCT nrp) AS people FROM events
     WHERE kind = 'search' AND ${w} GROUP BY LOWER(q) ORDER BY n DESC, q LIMIT ${LIST}`,
    ...b,
  ).map((r) => ({ q: s(r.q), n: n(r.n), people: n(r.people) }));

  // Not found: every search of the term in the period found nothing, and
  // nobody searched it after an admin marked it handled.
  const missing = rows(
    sql,
    `SELECT LOWER(e.q) AS q, COUNT(*) AS n, COUNT(DISTINCT e.nrp) AS people, MAX(e.hits) AS best, MAX(e.at) AS last
     FROM events e WHERE e.kind = 'search' AND ${where(f, "e.")} GROUP BY LOWER(e.q)`,
    ...b,
  )
    .filter((r) => n(r.best) === 0)
    .filter((r) => {
      const h = rows(sql, "SELECT at FROM handled WHERE q = ?", s(r.q))[0];
      return !h || n(r.last) > n(h.at);
    })
    .sort((x, y) => n(y.n) - n(x.n) || s(x.q).localeCompare(s(y.q)))
    .slice(0, LIST)
    .map((r) => ({ q: s(r.q), n: n(r.n), people: n(r.people) }));

  const people = rows(
    sql,
    `SELECT nrp, MAX(name) AS name, MAX(secs) AS secs, MAX(at) AS last,
       SUM(kind = 'open') AS manuals, SUM(kind = 'ai') AS ai, SUM(kind = 'search') AS searches
     FROM events WHERE kind != 'rate' AND ${w} GROUP BY nrp ORDER BY manuals + ai + searches DESC, last DESC`,
    ...b,
  ).map((r) => ({
    nrp: s(r.nrp), name: s(r.name), sections: secsOf(r.secs), last: n(r.last),
    manuals: n(r.manuals), ai: n(r.ai), searches: n(r.searches),
  }));

  return {
    opens: count("open"),
    ai: count("ai"),
    manuals,
    units,
    topics: topics(asked.map((r) => parse(r.extra).queries ?? [])),
    ratings: {
      good: n(rated.find((r) => n(r.hits) === 1)?.c),
      bad: n(rated.find((r) => n(r.hits) === 0)?.c),
    },
    questions,
    searches,
    missing,
    people,
    last: Object.fromEntries(lastSeen(sql)),
  };
}

type Extra = { answer?: string; sources?: string[]; queries?: string[] };
function parse(v: unknown): Extra {
  try {
    return (JSON.parse(s(v)) as Extra) ?? {};
  } catch {
    return {};
  }
}

const question = (r: Row) => ({
  id: n(r.id), at: n(r.at), nrp: s(r.nrp), name: s(r.name), sections: secsOf(r.secs), unit: s(r.unit), q: s(r.q),
});

/// The last time each NRP did anything, any period.
export function lastSeen(sql: Sql): Map<string, number> {
  return new Map(rows(sql, "SELECT nrp, MAX(at) AS last FROM events GROUP BY nrp").map((r) => [s(r.nrp), n(r.last)]));
}

export function manual(sql: Sql, f: Filter, file: string) {
  const w = where(f);
  const b = binds(f);
  const head = rows(
    sql,
    `SELECT MAX(unit) AS unit, MAX(title) AS title, SUM(kind = 'open') AS opens,
       COUNT(DISTINCT CASE WHEN kind = 'open' THEN nrp END) AS people, SUM(kind = 'download') AS downloads
     FROM events WHERE file = ? AND ${w}`,
    file, ...b,
  )[0] ?? {};
  const chapters = rows(
    sql,
    `SELECT q, COUNT(*) AS n FROM events WHERE kind = 'chapter' AND file = ? AND ${w} GROUP BY q ORDER BY n DESC LIMIT 5`,
    file, ...b,
  ).map((r) => ({ title: s(r.q), n: n(r.n) }));
  const readers = rows(
    sql,
    `SELECT nrp, MAX(name) AS name, COUNT(*) AS n FROM events WHERE kind = 'open' AND file = ? AND ${w}
     GROUP BY nrp ORDER BY n DESC LIMIT 3`,
    file, ...b,
  ).map((r) => ({ nrp: s(r.nrp), name: s(r.name), n: n(r.n) }));
  return {
    file, unit: s(head.unit), title: s(head.title), opens: n(head.opens), people: n(head.people),
    downloads: n(head.downloads), chapters, readers,
  };
}

export function person(sql: Sql, f: Filter, nrp: string) {
  const at = `at >= ${Math.floor(f.since)}`;
  const head = rows(
    sql,
    `SELECT MAX(name) AS name, MAX(secs) AS secs, SUM(kind = 'open') AS manuals, SUM(kind = 'ai') AS ai,
       SUM(kind = 'search') AS searches FROM events WHERE nrp = ? AND kind != 'rate' AND ${at}`,
    nrp,
  )[0] ?? {};
  const last = rows(sql, "SELECT MAX(at) AS last FROM events WHERE nrp = ?", nrp)[0];
  const manuals = rows(
    sql,
    `SELECT file, MAX(unit) AS unit, MAX(title) AS title, COUNT(*) AS n FROM events
     WHERE nrp = ? AND kind = 'open' AND ${at} GROUP BY file ORDER BY n DESC LIMIT 10`,
    nrp,
  ).map((r) => ({ file: s(r.file), unit: s(r.unit), title: s(r.title), n: n(r.n) }));
  const questions = rows(
    sql,
    `SELECT id, at, nrp, name, secs, unit, q FROM events WHERE nrp = ? AND kind = 'ai' AND ${at} ORDER BY at DESC LIMIT 5`,
    nrp,
  ).map(question);
  return {
    nrp, name: s(head.name), sections: secsOf(head.secs), last: n(last?.last),
    manuals_opened: n(head.manuals), ai: n(head.ai), searches: n(head.searches), manuals, questions,
  };
}

/// One nyel AI question with its answer and the rating it got, if any.
export function answer(sql: Sql, id: number) {
  const r = rows(sql, "SELECT id, at, nrp, name, secs, unit, q, extra FROM events WHERE id = ? AND kind = 'ai'", id)[0];
  if (!r) return null;
  const x = parse(r.extra);
  const rate = rows(
    sql,
    "SELECT hits FROM events WHERE kind = 'rate' AND nrp = ? AND q = ? AND at >= ? ORDER BY at DESC LIMIT 1",
    s(r.nrp), s(r.q), n(r.at),
  )[0];
  return {
    ...question(r),
    answer: x.answer ?? "",
    sources: x.sources ?? [],
    topic: topics([x.queries ?? []])[0]?.name ?? "",
    rating: rate ? (n(rate.hits) === 1 ? "good" : "bad") : "",
  };
}

export function search(sql: Sql, f: Filter, q: string) {
  const who = rows(
    sql,
    `SELECT nrp, name, secs, at FROM events WHERE kind = 'search' AND LOWER(q) = ? AND ${where(f)} ORDER BY at DESC LIMIT 30`,
    q.toLowerCase(), ...binds(f),
  ).map((r) => ({ nrp: s(r.nrp), name: s(r.name), sections: secsOf(r.secs), at: n(r.at) }));
  return { q: q.toLowerCase(), n: who.length, people: new Set(who.map((w) => w.nrp)).size, who };
}

export function markHandled(sql: Sql, q: string, at = Date.now()): void {
  sql.exec("INSERT INTO handled (q, at) VALUES (?, ?) ON CONFLICT (q) DO UPDATE SET at = excluded.at", q.toLowerCase(), at);
}

// Words that say nothing about the topic of a nyel AI search.
const STOP = new Set(
  `a an and are as at be by for from how in is it of on or the to what when where which with without
   check checking procedure method specification specifications standard value values adjust adjusting
   testing removal installation install remove disassembly assembly troubleshooting unit machine
   cara apa yang dan di ke untuk dengan pada dari berapa bagaimana`.split(/\s+/),
);
const CODE = /^(?:[A-Z]{1,3}\d{2,5}[A-Z]{0,2}|E\d{2})$/;
const MODEL = /^(?:PC|D|HD|WA|GD|CAT|HM|SK|EX)\d{2,4}/i;

/// The subjects nyel AI searched for most: in each question's searches, a
/// pair of neighbouring words ("relief valve", "track roller") or a fault
/// code ("Kode error"); each question counts a subject once.
export function topics(queries: string[][], limit = 8): { name: string; n: number }[] {
  const counts = new Map<string, number>();
  for (const list of queries) {
    const seen = new Set<string>();
    for (const query of list) {
      const words = query.split(/[^\p{L}\p{N}-]+/u).filter(Boolean);
      if (words.some((w) => CODE.test(w) && !MODEL.test(w))) seen.add("Kode error");
      const plain = words.map((w) => w.toLowerCase()).map((w, i) =>
        STOP.has(w) || MODEL.test(words[i]) || CODE.test(words[i]) || /^\d/.test(w) || w.length < 2 ? "" : w,
      );
      for (let i = 0; i + 1 < plain.length; i++) {
        if (plain[i] && plain[i + 1]) seen.add(`${plain[i]} ${plain[i + 1]}`);
      }
    }
    for (const t of seen) counts.set(t, (counts.get(t) ?? 0) + 1);
  }
  return [...counts]
    .sort((x, y) => y[1] - x[1] || x[0].localeCompare(y[0]))
    .slice(0, limit)
    .map(([name, n]) => ({ name: name[0].toUpperCase() + name.slice(1), n }));
}
