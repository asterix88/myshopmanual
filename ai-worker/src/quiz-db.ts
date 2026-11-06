// What the Quiz does with its D1 database (tables in migrations/0001_quiz.sql).
// The functions take the database as a parameter (Db below), so the tests
// run them on node:sqlite with the same migration file, the way the usage
// statistics are tested (src/stats-db.ts). The rules themselves (levels,
// XP, streak) are in quiz-rules.ts.

import {
  answerXp,
  capDaily,
  daysBetween,
  isMastered,
  monthId,
  nextCard,
  nextStreak,
  pickSession,
  quizDay,
  SESSION_SIZE,
  sessionBonus,
  streakBonus,
  streakNow,
  weekId,
  type QuestionInput,
} from "./quiz-rules.ts";

export const DEFAULT_SITE = "SBS";
const DEFAULT_TZ = "Asia/Jakarta";
const SHARED_SECTION = "SEMUA";
export const BOARD_SIZE = 20;
/// Answers sent later than this (phones offline) are refused.
const LATE_LIMIT_MS = 3 * 86400_000;
/// "Soal salah" reports that pull a question until an admin decides.
export const REPORTS_TO_PULL = 2;

type Row = Record<string, unknown>;

/// The few things the code needs from a database: D1 in the Worker,
/// node:sqlite in the tests.
export interface Db {
  all(sql: string, ...bind: unknown[]): Promise<Row[]>;
  first(sql: string, ...bind: unknown[]): Promise<Row | null>;
  run(sql: string, ...bind: unknown[]): Promise<number>;
  /// Several writes that all happen or none do.
  batch(statements: [string, ...unknown[]][]): Promise<void>;
}

/// The Db above on Cloudflare D1.
export function d1(db: D1Database): Db {
  return {
    all: async (sql, ...bind) => (await db.prepare(sql).bind(...bind).all()).results as Row[],
    first: async (sql, ...bind) => (await db.prepare(sql).bind(...bind).first<Row>()) ?? null,
    run: async (sql, ...bind) => (await db.prepare(sql).bind(...bind).run()).meta.changes ?? 0,
    batch: async (statements) => {
      await db.batch(statements.map(([sql, ...bind]) => db.prepare(sql).bind(...bind)));
    },
  };
}

/// The mechanic, from their login: sections null = admin (every section).
export type Who = { nrp: string; name: string; sections: string[] | null; departemen: string; site?: string };

export type Question = {
  id: string;
  section: string;
  unit: string | null;
  topic: string;
  type: string;
  prompt: string;
  choices: string[];
  answer: number;
  explain: string;
  manual_id: string;
  page: number;
  image: string | null;
};

function toQuestion(r: Row): Question {
  let choices: string[] = [];
  try {
    choices = JSON.parse(String(r.choices));
  } catch {
    // A broken row shows no choices; the admin sees it in the list.
  }
  return {
    id: String(r.id),
    section: String(r.section),
    unit: (r.unit as string | null) ?? null,
    topic: String(r.topic),
    type: String(r.type),
    prompt: String(r.prompt),
    choices,
    answer: Number(r.answer),
    explain: String(r.explain),
    manual_id: String(r.manual_id),
    page: Number(r.page),
    image: (r.image as string | null) ?? null,
  };
}

const siteOf = (who: Who) => who.site || DEFAULT_SITE;

const tzCache = new Map<string, string>();

/// The site's time zone (table site), for the quiz day.
export async function siteTz(db: Db, site: string): Promise<string> {
  const known = tzCache.get(site);
  if (known) return known;
  const row = await db.first("SELECT tz FROM site WHERE id = ?", site);
  const tz = row ? String(row.tz) : DEFAULT_TZ;
  tzCache.set(site, tz);
  return tz;
}

export async function today(db: Db, who: Who, now = Date.now()): Promise<string> {
  return quizDay(now, await siteTz(db, siteOf(who)));
}

/// Makes or refreshes the mechanic's row; a new one gets a random avatar.
export async function ensureUser(db: Db, who: Who, random: () => number = Math.random): Promise<void> {
  await db.run(
    `INSERT INTO quiz_user (nrp, name, site, departemen, section, avatar) VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT (nrp) DO UPDATE SET name = excluded.name, site = excluded.site,
       departemen = excluded.departemen, section = excluded.section`,
    who.nrp,
    who.name,
    siteOf(who),
    who.departemen,
    (who.sections ?? []).join(","),
    Math.floor(random() * 10),
  );
}

// ---- Which questions a mechanic may get ----

/// SQL condition and values for the questions of [who]'s sections (plus the
/// shared SEMUA ones), optionally one unit only.
function scope(who: Who, unit: string | null, alias = "q"): { where: string; bind: unknown[] } {
  const parts = [`${alias}.status = 'terbit'`];
  const bind: unknown[] = [];
  if (who.sections) {
    const sections = [...who.sections, SHARED_SECTION];
    parts.push(`${alias}.section IN (${sections.map(() => "?").join(", ")})`);
    bind.push(...sections);
  }
  if (unit) {
    parts.push(`${alias}.unit = ?`);
    bind.push(unit);
  }
  return { where: parts.join(" AND "), bind };
}

// ---- Sessions ----

export type SessionOut = {
  id: string;
  mode: "harian" | "unit";
  unit: string | null;
  questions: (Question & { review: boolean; level: number | null })[];
  answered: { question_id: string; chosen: number; correct: boolean }[];
};

async function loadSession(db: Db, who: Who, row: Row): Promise<SessionOut> {
  const ids = JSON.parse(String(row.questions)) as { id: string; review: boolean }[];
  const marks = ids.map(() => "?").join(", ");
  const qs = await db.all(`SELECT * FROM question WHERE id IN (${marks})`, ...ids.map((i) => i.id));
  const cards = await db.all(
    `SELECT question_id, level FROM card_state WHERE nrp = ? AND question_id IN (${marks})`,
    who.nrp,
    ...ids.map((i) => i.id),
  );
  const byId = new Map(qs.map((r) => [String(r.id), toQuestion(r)]));
  const levels = new Map(cards.map((c) => [String(c.question_id), Number(c.level)]));
  const answered = await db.all(
    "SELECT question_id, chosen, correct FROM review_log WHERE session_id = ? ORDER BY answered_at",
    row.id,
  );
  return {
    id: String(row.id),
    mode: row.mode as "harian" | "unit",
    unit: (row.unit as string | null) ?? null,
    questions: ids
      .filter((i) => byId.has(i.id))
      .map((i) => ({ ...byId.get(i.id)!, review: i.review, level: levels.get(i.id) ?? null })),
    answered: answered.map((a) => ({
      question_id: String(a.question_id),
      chosen: Number(a.chosen),
      correct: Number(a.correct) === 1,
    })),
  };
}

/// Starts a set of 10 (or continues today's unfinished one). Quiz harian
/// once per quiz day: done = {error: "done"}; no questions = {error: "empty"}.
export async function startSession(
  db: Db,
  who: Who,
  mode: "harian" | "unit",
  unit: string | null,
  opts: { now?: number; random?: () => number; id?: string } = {},
): Promise<SessionOut | { error: "done" | "empty" }> {
  const now = opts.now ?? Date.now();
  const day = await today(db, who, now);
  if (mode === "unit" && !unit) return { error: "empty" };
  const open = await db.first(
    `SELECT * FROM session WHERE nrp = ? AND day = ? AND mode = ? AND COALESCE(unit, '') = ? ORDER BY created_at DESC LIMIT 1`,
    who.nrp,
    day,
    mode,
    mode === "unit" ? unit : "",
  );
  if (open && open.done_at == null) return loadSession(db, who, open);
  if (open && mode === "harian") return { error: "done" };

  const s = scope(who, mode === "unit" ? unit : null);
  const due = await db.all(
    `SELECT q.* FROM card_state c JOIN question q ON q.id = c.question_id
     WHERE c.nrp = ? AND c.next_date <= ? AND ${s.where}
     ORDER BY c.next_date, c.level LIMIT 10`,
    who.nrp,
    day,
    ...s.bind,
  );
  const fresh = await db.all(
    `SELECT q.* FROM question q WHERE ${s.where}
     AND NOT EXISTS (SELECT 1 FROM card_state c WHERE c.nrp = ? AND c.question_id = q.id)
     ORDER BY RANDOM() LIMIT ${SESSION_SIZE}`,
    ...s.bind,
    who.nrp,
  );
  const fallback = await db.all(
    `SELECT q.* FROM card_state c JOIN question q ON q.id = c.question_id
     WHERE c.nrp = ? AND c.next_date > ? AND ${s.where}
     ORDER BY c.level, c.next_date LIMIT ${SESSION_SIZE}`,
    who.nrp,
    day,
    ...s.bind,
  );
  const picked = pickSession(due.map(toQuestion), fresh.map(toQuestion), fallback.map(toQuestion), opts.random);
  if (picked.length === 0) return { error: "empty" };
  const id = opts.id ?? crypto.randomUUID();
  await db.run(
    `INSERT INTO session (id, nrp, site, mode, unit, day, questions, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    id,
    who.nrp,
    siteOf(who),
    mode,
    mode === "unit" ? unit : null,
    day,
    JSON.stringify(picked.map((p) => ({ id: p.question.id, review: p.review }))),
    now,
  );
  const row = await db.first("SELECT * FROM session WHERE id = ?", id);
  return loadSession(db, who, row!);
}

// ---- Answers ----

export type AnswerIn = { id: string; session_id: string; question_id: string; chosen: number; ms: number; at?: number };
export type AnswerOut = { correct: boolean; xp: number; level: number; next_days: number; mastered: boolean };

/// Checks and saves one answer. Sending the same answer id again (a phone
/// that lost the reply) gives the first result back without counting twice.
export async function answer(db: Db, who: Who, a: AnswerIn, now = Date.now()): Promise<AnswerOut | { error: string }> {
  const again = await db.first("SELECT correct, xp, level_after, answered_at FROM review_log WHERE id = ? AND nrp = ?", a.id, who.nrp);
  if (again) {
    const day = await today(db, who, Number(again.answered_at));
    return answerOut(db, who, a.question_id, Number(again.correct) === 1, Number(again.xp), Number(again.level_after), day);
  }
  const session = await db.first("SELECT * FROM session WHERE id = ? AND nrp = ?", a.session_id, who.nrp);
  if (!session) return { error: "session" };
  const ids = (JSON.parse(String(session.questions)) as { id: string }[]).map((q) => q.id);
  if (!ids.includes(a.question_id)) return { error: "question" };
  const q = await db.first("SELECT answer, unit FROM question WHERE id = ?", a.question_id);
  if (!q) return { error: "question" };

  // Phones offline send their answers later with the time they answered.
  const createdAt = Number(session.created_at);
  let at = Number.isFinite(a.at) ? Number(a.at) : now;
  at = Math.min(Math.max(at, createdAt), now);
  if (now - at > LATE_LIMIT_MS) return { error: "late" };

  const day = await today(db, who, at);
  const correct = Number(a.chosen) === Number(q.answer);
  const card = await db.first("SELECT level, next_date, last_correct_day FROM card_state WHERE nrp = ? AND question_id = ?", who.nrp, a.question_id);
  const before = card ? { level: Number(card.level), next_date: String(card.next_date), last_correct_day: card.last_correct_day as string | null } : null;
  const next = nextCard(before, correct, day);
  const stats = await db.first("SELECT xp FROM daily_stats WHERE day = ? AND nrp = ?", day, who.nrp);
  const xp = capDaily(
    stats ? Number(stats.xp) : 0,
    answerXp({
      correct,
      ms: Number(a.ms) || 0,
      levelBefore: before?.level ?? null,
      due: next.due,
      correctToday: before?.last_correct_day === day,
    }),
  );
  const c = correct ? 1 : 0;
  await db.batch([
    [
      `INSERT INTO review_log (id, session_id, nrp, site, question_id, chosen, correct, level_after, xp, ms, answered_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      a.id, a.session_id, who.nrp, siteOf(who), a.question_id, Number(a.chosen), c, next.level, xp, Number(a.ms) || 0, at,
    ],
    [
      `INSERT INTO card_state (nrp, question_id, site, unit, level, next_date, last_correct_day, correct, wrong)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (nrp, question_id) DO UPDATE SET level = excluded.level, next_date = excluded.next_date,
         last_correct_day = COALESCE(excluded.last_correct_day, card_state.last_correct_day),
         correct = card_state.correct + excluded.correct, wrong = card_state.wrong + excluded.wrong`,
      who.nrp, a.question_id, siteOf(who), q.unit ?? null, next.level, next.next_date, correct ? day : null, c, 1 - c,
    ],
    [
      `INSERT INTO daily_stats (day, nrp, site, answered, correct, xp) VALUES (?, ?, ?, 1, ?, ?)
       ON CONFLICT (day, nrp) DO UPDATE SET answered = answered + 1, correct = correct + excluded.correct, xp = xp + excluded.xp`,
      day, who.nrp, siteOf(who), c, xp,
    ],
  ]);
  return answerOut(db, who, a.question_id, correct, xp, next.level, day);
}

async function answerOut(db: Db, who: Who, questionId: string, correct: boolean, xp: number, level: number, day: string): Promise<AnswerOut> {
  const card = await db.first("SELECT next_date FROM card_state WHERE nrp = ? AND question_id = ?", who.nrp, questionId);
  const nextDays = card ? Math.max(0, daysBetween(day, String(card.next_date))) : 0;
  return { correct, xp, level, next_days: nextDays, mastered: isMastered(level) };
}

// ---- Finishing a set ----

export type FinishOut = {
  score: number;
  total: number;
  xp_session: number;
  bonus: number;
  streak: number;
  freeze_used: boolean;
  rank: number;
};

/// Ends a set: session bonus, streak (Quiz harian only), and the XP of the
/// whole set onto this week's and this month's leaderboard.
export async function finish(db: Db, who: Who, sessionId: string, now = Date.now()): Promise<FinishOut | { error: string }> {
  const session = await db.first("SELECT * FROM session WHERE id = ? AND nrp = ?", sessionId, who.nrp);
  if (!session) return { error: "session" };
  const day = await today(db, who, now);
  if (session.done_at != null) {
    const u = await db.first("SELECT streak FROM quiz_user WHERE nrp = ?", who.nrp);
    return {
      score: Number(session.score), total: JSON.parse(String(session.questions)).length, xp_session: Number(session.xp),
      bonus: 0, streak: Number(u?.streak ?? 0), freeze_used: false, rank: await rank(db, who, weekId(day)),
    };
  }
  const ids = (JSON.parse(String(session.questions)) as { id: string }[]).map((q) => q.id);
  const log = await db.all(
    "SELECT question_id, correct, xp FROM review_log WHERE session_id = ? ORDER BY answered_at",
    sessionId,
  );
  // Score: the first answer of each question (a wrong one asked again at
  // the end of the set does not count twice).
  const first = new Map<string, boolean>();
  for (const r of log) if (!first.has(String(r.question_id))) first.set(String(r.question_id), Number(r.correct) === 1);
  const score = [...first.values()].filter(Boolean).length;
  const answerXpSum = log.reduce((sum, r) => sum + Number(r.xp), 0);
  const complete = ids.every((id) => first.has(id));

  const user = await db.first("SELECT streak, best_streak, last_daily, freeze_week, departemen, section FROM quiz_user WHERE nrp = ?", who.nrp);
  const before = {
    streak: Number(user?.streak ?? 0),
    best_streak: Number(user?.best_streak ?? 0),
    last_daily: (user?.last_daily as string | null) ?? null,
    freeze_week: (user?.freeze_week as string | null) ?? null,
  };
  const streak = session.mode === "harian" && complete ? nextStreak(before, day) : { ...before, freezeUsed: false };
  let bonus = complete ? sessionBonus(score, ids.length) : 0;
  if (session.mode === "harian" && complete) bonus += streakBonus(streak.streak);
  const stats = await db.first("SELECT xp FROM daily_stats WHERE day = ? AND nrp = ?", day, who.nrp);
  bonus = capDaily(stats ? Number(stats.xp) : 0, bonus);
  const xpSession = answerXpSum + bonus;

  const board = (period: string): [string, ...unknown[]] => [
    `INSERT INTO xp_board (period, site, departemen, nrp, section, xp, reached_at) VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (period, site, departemen, nrp) DO UPDATE SET xp = xp + excluded.xp, section = excluded.section,
       reached_at = CASE WHEN excluded.xp > 0 THEN excluded.reached_at ELSE xp_board.reached_at END`,
    period, siteOf(who), who.departemen, who.nrp, (who.sections ?? []).join(","), xpSession, now,
  ];
  await db.batch([
    ["UPDATE session SET done_at = ?, score = ?, xp = ? WHERE id = ?", now, score, xpSession, sessionId],
    [
      `UPDATE quiz_user SET streak = ?, best_streak = ?, last_daily = ?, freeze_week = ?, xp_total = xp_total + ? WHERE nrp = ?`,
      streak.streak, streak.best_streak, streak.last_daily, streak.freeze_week, xpSession, who.nrp,
    ],
    [
      `INSERT INTO daily_stats (day, nrp, site, xp) VALUES (?, ?, ?, ?)
       ON CONFLICT (day, nrp) DO UPDATE SET xp = xp + excluded.xp`,
      day, who.nrp, siteOf(who), bonus,
    ],
    board(weekId(day)),
    board(monthId(day)),
  ]);
  return {
    score,
    total: ids.length,
    xp_session: xpSession,
    bonus,
    streak: streak.streak,
    freeze_used: streak.freezeUsed,
    rank: await rank(db, who, weekId(day)),
  };
}

// ---- Leaderboard ----

/// [who]'s place on a board (1 = top); 0 when not on it yet.
export async function rank(db: Db, who: Who, period: string): Promise<number> {
  const me = await db.first(
    "SELECT xp, reached_at FROM xp_board WHERE period = ? AND site = ? AND departemen = ? AND nrp = ?",
    period, siteOf(who), who.departemen, who.nrp,
  );
  if (!me) return 0;
  const ahead = await db.first(
    `SELECT COUNT(*) AS n FROM xp_board b JOIN quiz_user u ON u.nrp = b.nrp
     WHERE b.period = ? AND b.site = ? AND b.departemen = ? AND u.hidden = 0
       AND (b.xp > ? OR (b.xp = ? AND b.reached_at < ?))`,
    period, siteOf(who), who.departemen, me.xp, me.xp, me.reached_at,
  );
  return Number(ahead?.n ?? 0) + 1;
}

export type BoardRow = { rank: number; nrp: string; name: string; section: string; avatar: number; xp: number; change: number; me: boolean };

/// The top 20 of [who]'s department and site, plus their own row when it
/// is not among them. change: places up (+) or down (-) since the last
/// nightly run.
export async function leaderboard(db: Db, who: Who, period: "week" | "month", now = Date.now()): Promise<{ period: string; rows: BoardRow[]; me: BoardRow | null }> {
  const day = await today(db, who, now);
  const id = period === "month" ? monthId(day) : weekId(day);
  const rows = await db.all(
    `SELECT * FROM (
       SELECT b.nrp, u.name, b.section, u.avatar, b.xp, b.rank_prev,
         ROW_NUMBER() OVER (ORDER BY b.xp DESC, b.reached_at) AS rank
       FROM xp_board b JOIN quiz_user u ON u.nrp = b.nrp
       WHERE b.period = ? AND b.site = ? AND b.departemen = ? AND u.hidden = 0
     ) WHERE rank <= ? OR nrp = ? ORDER BY rank`,
    id, siteOf(who), who.departemen, BOARD_SIZE, who.nrp,
  );
  const out = rows.map((r): BoardRow => ({
    rank: Number(r.rank),
    nrp: String(r.nrp),
    name: String(r.name),
    section: String(r.section),
    avatar: Number(r.avatar),
    xp: Number(r.xp),
    change: r.rank_prev == null ? 0 : Number(r.rank_prev) - Number(r.rank),
    me: r.nrp === who.nrp,
  }));
  return { period: id, rows: out.filter((r) => r.rank <= BOARD_SIZE), me: out.find((r) => r.me) ?? null };
}

/// Nightly: remembers every board's current ranks, so tomorrow's
/// leaderboard can show who went up or down.
export async function snapshotRanks(db: Db, day: string): Promise<void> {
  for (const period of [weekId(day), monthId(day)]) {
    await db.run(
      `UPDATE xp_board SET rank_prev = (
         SELECT COUNT(*) + 1 FROM xp_board o JOIN quiz_user u ON u.nrp = o.nrp
         WHERE o.period = xp_board.period AND o.site = xp_board.site AND o.departemen = xp_board.departemen
           AND u.hidden = 0 AND (o.xp > xp_board.xp OR (o.xp = xp_board.xp AND o.reached_at < xp_board.reached_at))
       ) WHERE period = ?`,
      period,
    );
  }
}

// ---- Home, units, profile ----

export async function home(db: Db, who: Who, now = Date.now()) {
  const day = await today(db, who, now);
  const u = await db.first("SELECT * FROM quiz_user WHERE nrp = ?", who.nrp);
  const daily = await db.first(
    "SELECT id, done_at FROM session WHERE nrp = ? AND day = ? AND mode = 'harian' ORDER BY created_at DESC LIMIT 1",
    who.nrp, day,
  );
  const week = await db.first(
    "SELECT xp FROM xp_board WHERE period = ? AND site = ? AND departemen = ? AND nrp = ?",
    weekId(day), siteOf(who), who.departemen, who.nrp,
  );
  const s = scope(who, null);
  const counts = await db.first(
    `SELECT COUNT(*) AS questions, SUM(CASE WHEN c.level >= 4 THEN 1 ELSE 0 END) AS mastered
     FROM question q LEFT JOIN card_state c ON c.question_id = q.id AND c.nrp = ?
     WHERE ${s.where}`,
    who.nrp,
    ...s.bind,
  );
  const state = {
    streak: Number(u?.streak ?? 0),
    best_streak: Number(u?.best_streak ?? 0),
    last_daily: (u?.last_daily as string | null) ?? null,
    freeze_week: (u?.freeze_week as string | null) ?? null,
  };
  return {
    day,
    daily: daily ? (daily.done_at != null ? "selesai" : "lanjutkan") : "belum",
    session_id: daily && daily.done_at == null ? String(daily.id) : null,
    streak: streakNow(state, day),
    best_streak: state.best_streak,
    xp_week: Number(week?.xp ?? 0),
    xp_total: Number(u?.xp_total ?? 0),
    rank_week: await rank(db, who, weekId(day)),
    avatar: Number(u?.avatar ?? 0),
    reminder: (u?.reminder as string | null) ?? "07:00",
    last_daily: state.last_daily,
    freeze_week: state.freeze_week,
    // Published questions this mechanic can get (the app hides the Quiz
    // card from mechanics while there are none) and how many they master.
    questions: Number(counts?.questions ?? 0),
    mastered: Number(counts?.mastered ?? 0),
  };
}

/// Units with published questions for [who], with how many they have
/// mastered (level 4+).
export async function units(db: Db, who: Who) {
  const s = scope(who, null);
  const rows = await db.all(
    `SELECT q.unit AS unit, COUNT(*) AS total,
       SUM(CASE WHEN c.level >= 4 THEN 1 ELSE 0 END) AS mastered,
       SUM(CASE WHEN c.question_id IS NOT NULL THEN 1 ELSE 0 END) AS seen
     FROM question q LEFT JOIN card_state c ON c.question_id = q.id AND c.nrp = ?
     WHERE ${s.where} AND q.unit IS NOT NULL AND q.unit <> ''
     GROUP BY q.unit ORDER BY q.unit`,
    who.nrp,
    ...s.bind,
  );
  return rows.map((r) => ({
    unit: String(r.unit),
    total: Number(r.total),
    seen: Number(r.seen ?? 0),
    mastered: Number(r.mastered ?? 0),
  }));
}

export async function setAvatar(db: Db, who: Who, avatar: number): Promise<boolean> {
  if (!Number.isInteger(avatar) || avatar < 0 || avatar > 9) return false;
  await db.run("UPDATE quiz_user SET avatar = ? WHERE nrp = ?", avatar, who.nrp);
  return true;
}

export async function setReminder(db: Db, who: Who, reminder: string): Promise<boolean> {
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(reminder)) return false;
  await db.run("UPDATE quiz_user SET reminder = ? WHERE nrp = ?", reminder, who.nrp);
  return true;
}

// ---- Reports ----

/// A mechanic's "Soal salah". The second open report pulls the question
/// (status ditarik) until an admin decides. XP already given stays.
export async function report(db: Db, who: Who, questionId: string, note: string, now = Date.now()): Promise<{ pulled: boolean } | { error: string }> {
  const q = await db.first("SELECT status FROM question WHERE id = ?", questionId);
  if (!q) return { error: "question" };
  await db.run(
    `INSERT INTO report (id, question_id, nrp, site, note, created_at) VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT (question_id, nrp) DO UPDATE SET note = excluded.note, created_at = excluded.created_at, handled_by = NULL`,
    crypto.randomUUID(), questionId, who.nrp, siteOf(who), note.slice(0, 500), now,
  );
  const open = await db.first("SELECT COUNT(*) AS n FROM report WHERE question_id = ? AND handled_by IS NULL", questionId);
  if (Number(open?.n ?? 0) >= REPORTS_TO_PULL && q.status === "terbit") {
    await db.run(
      "UPDATE question SET status = 'ditarik', check_note = ?, updated_at = ? WHERE id = ?",
      `Ditarik otomatis: ${REPORTS_TO_PULL} laporan soal salah.`, now, questionId,
    );
    return { pulled: true };
  }
  return { pulled: false };
}

// ---- Admin: questions ----

export type QuestionRow = Question & {
  status: string;
  source: string;
  check_note: string | null;
  created_by: string;
  reviewed_by: string | null;
  updated_at: number;
  reports: number;
  answered: number;
  wrong_pct: number | null;
  job_id: string | null;
  curator_score: number | null;
  curator_note: string | null;
  passed: boolean;
};

export async function listQuestions(db: Db, status: string, unit: string | null): Promise<QuestionRow[]> {
  const rows = await db.all(
    `SELECT q.*,
       (SELECT COUNT(*) FROM report r WHERE r.question_id = q.id AND r.handled_by IS NULL) AS reports,
       (SELECT COUNT(*) FROM review_log l WHERE l.question_id = q.id) AS answered,
       (SELECT AVG(1 - l.correct) FROM review_log l WHERE l.question_id = q.id) AS wrong_rate
     FROM question q WHERE q.status = ? ${unit ? "AND q.unit = ?" : ""}
     ORDER BY q.updated_at DESC LIMIT 200`,
    status,
    ...(unit ? [unit] : []),
  );
  return rows.map((r) => ({
    ...toQuestion(r),
    status: String(r.status),
    source: String(r.source),
    check_note: (r.check_note as string | null) ?? null,
    created_by: String(r.created_by),
    reviewed_by: (r.reviewed_by as string | null) ?? null,
    updated_at: Number(r.updated_at),
    reports: Number(r.reports),
    answered: Number(r.answered),
    job_id: (r.job_id as string | null) ?? null,
    curator_score: r.curator_score == null ? null : Number(r.curator_score),
    curator_note: (r.curator_note as string | null) ?? null,
    passed: Number(r.passed ?? 0) === 1,
    wrong_pct: r.wrong_rate == null ? null : Math.round(Number(r.wrong_rate) * 100),
  }));
}

/// Saves a new question (draft from nyel AI, or an admin's own).
export async function addQuestion(
  db: Db,
  q: QuestionInput & { image?: string | null },
  meta: {
    status: "draf" | "terbit";
    source: "ai" | "admin";
    by: string;
    check_note?: string | null;
    now?: number;
    id?: string;
    job_id?: string | null;
    curator_score?: number | null;
    curator_note?: string | null;
    passed?: boolean;
  },
): Promise<string> {
  const id = meta.id ?? crypto.randomUUID();
  const now = meta.now ?? Date.now();
  await db.run(
    `INSERT INTO question (id, section, unit, topic, type, prompt, choices, answer, explain, manual_id, page, image,
       status, source, check_note, created_by, reviewed_by, created_at, updated_at, job_id, curator_score, curator_note, passed)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    id, q.section.toUpperCase(), q.unit || null, q.topic, q.type, q.prompt.trim(), JSON.stringify(q.choices.map((c) => c.trim())),
    q.answer, q.explain.trim(), q.manual_id.trim(), q.page, q.image ?? null, meta.status, meta.source, meta.check_note ?? null,
    meta.by, meta.status === "terbit" ? meta.by : null, now, now,
    meta.job_id ?? null, meta.curator_score ?? null, meta.curator_note ?? null, meta.passed ? 1 : 0,
  );
  return id;
}

/// The picture of a "gambar" question (an R2 key, quiz/img/...).
export async function setImage(db: Db, id: string, key: string, now = Date.now()): Promise<boolean> {
  return (await db.run("UPDATE question SET image = ?, updated_at = ? WHERE id = ?", key, now, id)) > 0;
}

/// "Setujui semua yang lolos": publishes the drafts among [ids] that passed
/// the curator and the checks; a picture question needs its picture first.
/// Returns how many were published and the ids left as drafts.
export async function approvePassed(db: Db, ids: string[], by: string, now = Date.now()): Promise<{ published: number; left: string[] }> {
  let published = 0;
  const left: string[] = [];
  for (const id of ids.slice(0, 200)) {
    const changed = await db.run(
      `UPDATE question SET status = 'terbit', reviewed_by = ?, check_note = NULL, updated_at = ?
       WHERE id = ? AND status = 'draf' AND passed = 1 AND (type <> 'gambar' OR image IS NOT NULL)`,
      by, now, id,
    );
    if (changed) published++;
    else left.push(id);
  }
  return { published, left };
}

/// An admin's decision on a question: setujui (publish), ubah (save edits,
/// stays where it is), tolak (reject a draft), tarik (take a published one
/// out). Approving or pulling closes its open reports.
export async function decide(
  db: Db,
  id: string,
  action: "setujui" | "ubah" | "tolak" | "tarik",
  by: string,
  edit: (QuestionInput & { image?: string | null }) | null,
  now = Date.now(),
): Promise<boolean> {
  const q = await db.first("SELECT id FROM question WHERE id = ?", id);
  if (!q) return false;
  const statements: [string, ...unknown[]][] = [];
  if (edit) {
    statements.push([
      `UPDATE question SET section = ?, unit = ?, topic = ?, type = ?, prompt = ?, choices = ?, answer = ?, explain = ?,
         manual_id = ?, page = ?, image = COALESCE(?, image), updated_at = ? WHERE id = ?`,
      edit.section.toUpperCase(), edit.unit || null, edit.topic, edit.type, edit.prompt.trim(),
      JSON.stringify(edit.choices.map((c) => c.trim())), edit.answer, edit.explain.trim(), edit.manual_id.trim(), edit.page,
      edit.image ?? null, now, id,
    ]);
  }
  const status = { setujui: "terbit", tolak: "ditolak", tarik: "ditarik", ubah: null }[action];
  if (status) {
    statements.push([
      "UPDATE question SET status = ?, reviewed_by = ?, check_note = CASE WHEN ? = 'terbit' THEN NULL ELSE check_note END, updated_at = ? WHERE id = ?",
      status, by, status, now, id,
    ]);
  }
  if (action === "setujui" || action === "tarik") {
    statements.push(["UPDATE report SET handled_by = ? WHERE question_id = ? AND handled_by IS NULL", by, id]);
  }
  if (statements.length) await db.batch(statements);
  return true;
}

export async function openReports(db: Db) {
  const rows = await db.all(
    `SELECT r.question_id, r.nrp, u.name, r.note, r.created_at, q.prompt, q.unit, q.status
     FROM report r JOIN question q ON q.id = r.question_id LEFT JOIN quiz_user u ON u.nrp = r.nrp
     WHERE r.handled_by IS NULL ORDER BY r.created_at DESC LIMIT 200`,
  );
  return rows.map((r) => ({
    question_id: String(r.question_id),
    nrp: String(r.nrp),
    name: (r.name as string | null) ?? String(r.nrp),
    note: (r.note as string | null) ?? "",
    at: Number(r.created_at),
    prompt: String(r.prompt),
    unit: (r.unit as string | null) ?? null,
    status: String(r.status),
  }));
}

export async function hideFromBoard(db: Db, nrp: string, hidden: boolean): Promise<boolean> {
  return (await db.run("UPDATE quiz_user SET hidden = ? WHERE nrp = ?", hidden ? 1 : 0, nrp)) > 0;
}

// ---- Nightly ----

/// Questions wrong more than 80% of the time (20 answers or more) go back
/// to the admins' check list (perlu_cek): the question or its key is
/// probably wrong.
export async function flagHardQuestions(db: Db, now = Date.now()): Promise<number> {
  return db.run(
    `UPDATE question SET status = 'perlu_cek', check_note = 'Lebih dari 80% jawaban salah, cek soal dan kuncinya.', updated_at = ?
     WHERE status = 'terbit' AND id IN (
       SELECT question_id FROM review_log GROUP BY question_id
       HAVING COUNT(*) >= 20 AND AVG(1 - correct) > 0.8)`,
    now,
  );
}

/// Answers older than 6 months are removed (daily_stats keeps the totals),
/// boards older than 13 months too, and sets never finished after 7 days.
export async function tidy(db: Db, now = Date.now()): Promise<{ log: number; boards: number; sessions: number }> {
  const log = await db.run("DELETE FROM review_log WHERE answered_at < ?", now - 183 * 86400_000);
  const cutoff = new Date(now - 400 * 86400_000).toISOString().slice(0, 7);
  const boards = await db.run(
    "DELETE FROM xp_board WHERE (substr(period, 1, 1) = 'M' AND substr(period, 2) < ?) OR (substr(period, 1, 1) = 'W' AND substr(period, 2, 4) < ?)",
    cutoff, cutoff.slice(0, 4),
  );
  const sessions = await db.run(
    "DELETE FROM session WHERE done_at IS NULL AND created_at < ? AND id NOT IN (SELECT DISTINCT session_id FROM review_log)",
    now - 7 * 86400_000,
  );
  return { log, boards, sessions };
}
