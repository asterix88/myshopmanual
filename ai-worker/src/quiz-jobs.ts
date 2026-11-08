// "Buat draf kuis": nyel AI makes drafts from a whole manual in the
// background, so the admin can close the app.
//
// 1. The admin's phone sends the manual's table of contents; nyel AI picks
//    pages (planPages, answered at once).
// 2. The phone reads those pages' text from its search index and sends them;
//    a job is saved (createJob).
// 3. Every minute Cloudflare runs runJobs (cron in wrangler.toml): page by
//    page nyel AI writes questions, the curator checks them, the server
//    checks the numbers, and the drafts are saved with their score. It stops
//    when enough questions are kept or the pages run out.
// 4. The admin approves in Kelola soal quiz > Draf.

import { curate, isRepeat, MAX_PAGE_TEXT, selfCheck, writeQuestions, type Ask, type Wanted } from "./quiz-ai.ts";
import { addQuestion, DEFAULT_SITE, madeFrom, type Db } from "./quiz-db.ts";
import { TOPICS } from "./quiz-rules.ts";

export const MAX_JOB_QUESTIONS = 50;
export const MAX_JOB_PAGES = 40;
/// A run holds its job this long; a run that died is picked up after it.
const LEASE_MS = 14 * 60_000;
/// Curator score from which a question counts as "lolos".
export const PASS_SCORE = 7;

export type Mix = { pg: number; bs: number; gambar: number };
export const DEFAULT_MIX: Mix = { pg: 60, bs: 20, gambar: 20 };

/// The mix from the app, in whole percents adding up to 100.
export function mixFrom(raw: unknown): Mix {
  const m = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const n = (v: unknown) => Math.max(0, Math.min(100, Math.round(Number(v) || 0)));
  const mix = { pg: n(m.pg), bs: n(m.bs), gambar: n(m.gambar) };
  const sum = mix.pg + mix.bs + mix.gambar;
  if (!sum) return { ...DEFAULT_MIX };
  const pg = Math.round((mix.pg * 100) / sum);
  const bs = Math.round((mix.bs * 100) / sum);
  return { pg, bs, gambar: 100 - pg - bs };
}

/// How many questions of each type the job should end with.
export function targets(count: number, mix: Mix, hasDrawings: boolean): Wanted {
  const gambar = hasDrawings ? Math.round((count * mix.gambar) / 100) : 0;
  const bs = Math.round((count * mix.bs) / 100);
  return { pg: Math.max(0, count - gambar - bs), bs, gambar };
}

/// What to ask for on one page: enough to reach the targets over the pages
/// left, plus one extra, since the curator throws some away. At most 5.
export function wantedForPage(kind: "teks" | "gambar", need: Wanted, pagesLeft: { teks: number; gambar: number }): Wanted {
  if (kind === "gambar" && need.gambar > 0) {
    return { pg: 0, bs: 0, gambar: Math.min(3, Math.ceil(need.gambar / Math.max(1, pagesLeft.gambar)) + 1) };
  }
  const textNeed = need.pg + need.bs;
  if (textNeed <= 0) return { pg: 0, bs: 0, gambar: 0 };
  const pages = Math.max(1, pagesLeft.teks + (need.gambar > 0 ? 0 : pagesLeft.gambar));
  const total = Math.min(5, Math.ceil(textNeed / pages) + 1);
  const bs = need.bs > 0 ? Math.max(1, Math.round((total * need.bs) / textNeed)) : 0;
  return { pg: Math.max(0, total - bs), bs: Math.min(bs, total), gambar: 0 };
}

export type JobPage = { page: number; kind: "teks" | "gambar"; topic: string; text: string };

export async function createJob(
  db: Db,
  job: { section: string; unit: string | null; manual_id: string; title: string; topic: string; count: number; mix: Mix; pages: JobPage[] },
  by: string,
  now = Date.now(),
): Promise<string> {
  const id = crypto.randomUUID();
  const statements: [string, ...unknown[]][] = [
    [
      `INSERT INTO quiz_job (id, site, section, unit, manual_id, title, topic, count, mix, status, created_by, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'antri', ?, ?, ?)`,
      id, DEFAULT_SITE, job.section.toUpperCase(), job.unit, job.manual_id, job.title, job.topic,
      Math.max(1, Math.min(MAX_JOB_QUESTIONS, Math.round(job.count))), JSON.stringify(job.mix), by, now, now,
    ],
  ];
  const seen = new Set<number>();
  for (const p of job.pages.slice(0, MAX_JOB_PAGES)) {
    if (seen.has(p.page) || p.text.trim().length < 80) continue;
    seen.add(p.page);
    statements.push([
      "INSERT INTO quiz_job_page (job_id, page, kind, topic, text) VALUES (?, ?, ?, ?, ?)",
      id, p.page, p.kind === "gambar" ? "gambar" : "teks", TOPICS.includes(p.topic) ? p.topic : "struktur", p.text.slice(0, MAX_PAGE_TEXT),
    ]);
  }
  await db.batch(statements);
  return id;
}

export async function listJobs(db: Db, limit = 10) {
  const rows = await db.all(
    `SELECT j.*, (SELECT COUNT(*) FROM quiz_job_page p WHERE p.job_id = j.id) AS pages,
       (SELECT COUNT(*) FROM quiz_job_page p WHERE p.job_id = j.id AND p.done = 1) AS pages_done
     FROM quiz_job j ORDER BY j.created_at DESC LIMIT ?`,
    limit,
  );
  return rows.map((r) => ({
    id: String(r.id),
    unit: (r.unit as string | null) ?? null,
    manual_id: String(r.manual_id),
    title: String(r.title),
    topic: String(r.topic),
    count: Number(r.count),
    status: String(r.status),
    pages: Number(r.pages),
    pages_done: Number(r.pages_done),
    written: Number(r.written),
    passed: Number(r.passed),
    flagged: Number(r.flagged),
    dropped: Number(r.dropped),
    error: (r.error as string | null) ?? null,
    created_at: Number(r.created_at),
    updated_at: Number(r.updated_at),
  }));
}

/// Works on waiting jobs until [deadline] (ms since epoch). Called by the
/// cron every minute; a job is held by one run at a time (lease_until).
export async function runJobs(db: Db, ask: Ask, deadline: number, now: () => number = Date.now): Promise<number> {
  let worked = 0;
  while (now() < deadline) {
    const t = now();
    const job = await db.first(
      "SELECT * FROM quiz_job WHERE status IN ('antri', 'jalan') AND lease_until < ? ORDER BY created_at LIMIT 1",
      t,
    );
    if (!job) break;
    const id = String(job.id);
    // Take the job; another run that read it at the same moment gets 0 rows.
    const took = await db.run(
      "UPDATE quiz_job SET status = 'jalan', lease_until = ?, updated_at = ? WHERE id = ? AND lease_until < ?",
      t + LEASE_MS, t, id, t,
    );
    if (!took) continue;
    worked++;
    const finished = await runOne(db, ask, job, deadline, now);
    await db.run(
      "UPDATE quiz_job SET status = ?, lease_until = 0, updated_at = ? WHERE id = ?",
      finished ? (finished === "gagal" ? "gagal" : "selesai") : "jalan", now(), id,
    );
  }
  return worked;
}

/// Pages of one job until it has enough questions, its pages run out
/// ("selesai"), every page failed ("gagal"), or time is up (null).
async function runOne(db: Db, ask: Ask, job: Record<string, unknown>, deadline: number, now: () => number): Promise<"selesai" | "gagal" | null> {
  const id = String(job.id);
  const count = Number(job.count);
  let mix: Mix = DEFAULT_MIX;
  try {
    mix = mixFrom(JSON.parse(String(job.mix)));
  } catch {
    // keep the default
  }
  const pages = (await db.all("SELECT page, kind, topic, text FROM quiz_job_page WHERE job_id = ? AND done = 0 ORDER BY page", id)).map((r) => ({
    page: Number(r.page),
    kind: String(r.kind) === "gambar" ? ("gambar" as const) : ("teks" as const),
    topic: String(r.topic),
    text: String(r.text),
  }));
  const anyDrawings = !!(await db.first("SELECT 1 FROM quiz_job_page WHERE job_id = ? AND kind = 'gambar' LIMIT 1", id));
  const goal = targets(count, mix, anyDrawings);
  const have = async (): Promise<Wanted> => {
    const rows = await db.all("SELECT type, COUNT(*) AS n FROM question WHERE job_id = ? GROUP BY type", id);
    const got: Wanted = { pg: 0, bs: 0, gambar: 0 };
    for (const r of rows) if (String(r.type) in got) got[String(r.type) as keyof Wanted] = Number(r.n);
    return got;
  };
  let failures = 0;
  for (const [i, p] of pages.entries()) {
    if (now() >= deadline) return null;
    const got = await have();
    if (got.pg + got.bs + got.gambar >= count) return "selesai";
    const need: Wanted = {
      pg: Math.max(0, goal.pg - got.pg),
      bs: Math.max(0, goal.bs - got.bs),
      gambar: Math.max(0, goal.gambar - got.gambar),
    };
    // Picture questions not needed any more: count the drawing pages as text.
    const rest = pages.slice(i);
    const left = { teks: rest.filter((x) => x.kind === "teks").length, gambar: rest.filter((x) => x.kind === "gambar").length };
    const wanted = wantedForPage(p.kind, need, left);
    let written = 0;
    let passed = 0;
    let flagged = 0;
    let dropped = 0;
    if (wanted.pg + wanted.bs + wanted.gambar > 0) {
      const base = {
        section: String(job.section),
        unit: (job.unit as string | null) ?? null,
        topic: p.topic,
        manual_id: String(job.manual_id),
        page: p.page,
      };
      // Questions made before from this manual (earlier drafts, this job's
      // pages so far): the AI is told this page's, and repeats are dropped.
      const made = await madeFrom(db, String(job.manual_id));
      const avoid = made.filter((m) => m.page === p.page).map((m) => m.prompt);
      const out = await writeQuestions(ask, base, p.text, wanted, avoid);
      if (!out) {
        failures++;
      } else {
        written = out.drafts.length + out.skipped.length;
        dropped += out.skipped.length;
        const fresh = [];
        for (const q of out.drafts) {
          if (isRepeat(q, made)) {
            dropped++;
            continue;
          }
          fresh.push(q);
          made.push({ page: p.page, prompt: q.prompt, answer: q.choices[q.answer] ?? "" });
        }
        const reviewed = await curate(ask, fresh, p.text);
        dropped += reviewed.dropped;
        for (const q of reviewed.kept) {
          const check = selfCheck(q, p.text);
          const ok = check.ok && q.score !== null && q.score >= PASS_SCORE;
          await addQuestion(db, q, {
            status: "draf",
            source: "ai",
            by: String(job.created_by),
            check_note: check.note,
            job_id: id,
            curator_score: q.score,
            curator_note: q.note,
            passed: ok,
          });
          if (ok) passed++;
          else flagged++;
        }
      }
    }
    await db.batch([
      ["UPDATE quiz_job_page SET done = 1 WHERE job_id = ? AND page = ?", id, p.page],
      [
        "UPDATE quiz_job SET written = written + ?, passed = passed + ?, flagged = flagged + ?, dropped = dropped + ?, updated_at = ? WHERE id = ?",
        written, passed, flagged, dropped, now(), id,
      ],
    ]);
  }
  if (failures && failures === pages.length && !(await db.first("SELECT 1 FROM question WHERE job_id = ? LIMIT 1", id))) {
    await db.run("UPDATE quiz_job SET error = ? WHERE id = ?", "nyel AI tidak menjawab. Coba lagi nanti.", id);
    return "gagal";
  }
  return "selesai";
}
