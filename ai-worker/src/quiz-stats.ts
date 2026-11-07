// The "Quiz" tab of Statistik pemakaian: who plays, how well, which topics
// and questions are hard, who has never played. Read from the quiz tables
// (D1), for the staff list the admin screen counts (src/stats.ts).

import { DEFAULT_SITE, questionRow, siteTz, type Db } from "./quiz-db.ts";
import { quizDay, streakNow } from "./quiz-rules.ts";

export type Person = { nrp: string; name: string; sections: string[] };
export type Range = { since: number; until?: number; section: string };

/// A question needs this many answers before it counts as "hard".
const HARD_MIN = 5;

const pct = (part: number, whole: number) => (whole > 0 ? Math.round((part / whole) * 100) : 0);

type Row = Record<string, unknown>;

/// [sections]: the section chips in their usual order.
export async function quizStats(db: Db, f: Range, staff: Person[], sections: string[], now = Date.now()) {
  const until = f.until ?? now;
  const people = new Map(staff.filter((p) => !f.section || p.sections.includes(f.section)).map((p) => [p.nrp, p]));
  const mine = (r: Row) => people.has(String(r.nrp));
  const length = f.since ? until - f.since : 0;

  const [answers, before, topics, perQuestion, sessions, ever, users] = await Promise.all([
    db.all(
      `SELECT nrp, COUNT(*) AS n, SUM(correct) AS c FROM review_log
       WHERE answered_at >= ? AND answered_at < ? GROUP BY nrp`,
      f.since,
      until,
    ),
    length
      ? db.all(
          `SELECT nrp, COUNT(*) AS n, SUM(correct) AS c FROM review_log
           WHERE answered_at >= ? AND answered_at < ? GROUP BY nrp`,
          f.since - length,
          f.since,
        )
      : Promise.resolve([] as Row[]),
    db.all(
      `SELECT l.nrp, q.topic, COUNT(*) AS n, SUM(l.correct) AS c FROM review_log l
       JOIN question q ON q.id = l.question_id
       WHERE l.answered_at >= ? AND l.answered_at < ? GROUP BY l.nrp, q.topic`,
      f.since,
      until,
    ),
    db.all(
      `SELECT l.question_id AS id, l.nrp, COUNT(*) AS n, SUM(l.correct) AS c FROM review_log l
       WHERE l.answered_at >= ? AND l.answered_at < ? GROUP BY l.question_id, l.nrp`,
      f.since,
      until,
    ),
    db.all(
      `SELECT nrp, COUNT(*) AS n, SUM(COALESCE(xp, 0)) AS xp FROM session
       WHERE done_at IS NOT NULL AND done_at >= ? AND done_at < ? GROUP BY nrp`,
      f.since,
      until,
    ),
    db.all("SELECT DISTINCT nrp FROM review_log"),
    db.all("SELECT nrp, streak, best_streak, last_daily, freeze_week FROM quiz_user"),
  ]);

  const sum = (rows: Row[]) =>
    rows.filter(mine).reduce<{ n: number; c: number }>((t, r) => ({ n: t.n + Number(r.n), c: t.c + Number(r.c ?? 0) }), { n: 0, c: 0 });
  const total = sum(answers);
  const earlier = sum(before);
  const players = new Set(answers.filter(mine).map((r) => String(r.nrp)));

  // Topics, weakest first.
  const byTopic = new Map<string, { n: number; c: number }>();
  for (const r of topics.filter(mine)) {
    const t = byTopic.get(String(r.topic)) ?? { n: 0, c: 0 };
    t.n += Number(r.n);
    t.c += Number(r.c ?? 0);
    byTopic.set(String(r.topic), t);
  }

  // Questions most often answered wrong.
  const byQuestion = new Map<string, { n: number; c: number }>();
  for (const r of perQuestion.filter(mine)) {
    const q = byQuestion.get(String(r.id)) ?? { n: 0, c: 0 };
    q.n += Number(r.n);
    q.c += Number(r.c ?? 0);
    byQuestion.set(String(r.id), q);
  }
  const hardIds = [...byQuestion]
    .filter(([, q]) => q.n >= HARD_MIN)
    .sort(([, a], [, b]) => a.c / a.n - b.c / b.n || b.n - a.n)
    .slice(0, 5);
  const hard = [];
  for (const [id, q] of hardIds) {
    const row = await db.first("SELECT prompt, unit, topic FROM question WHERE id = ?", id);
    if (!row) continue;
    hard.push({ id, prompt: String(row.prompt), unit: String(row.unit ?? ""), topic: String(row.topic), answers: q.n, correct: pct(q.c, q.n) });
  }

  // Most diligent: XP of the sets finished in the period.
  const day = quizDay(now, await siteTz(db, DEFAULT_SITE));
  const streaks = new Map(
    users.map((u) => [
      String(u.nrp),
      streakNow({ streak: Number(u.streak), last_daily: (u.last_daily as string | null) ?? null, freeze_week: (u.freeze_week as string | null) ?? null } as Parameters<typeof streakNow>[0], day),
    ]),
  );
  const best = new Map(users.map((u) => [String(u.nrp), Number(u.best_streak ?? 0)]));
  const done = sessions.filter(mine);
  const setsOf = new Map(done.map((r) => [String(r.nrp), { n: Number(r.n), xp: Number(r.xp) }]));
  // Everyone who answered in the period, for the Excel report.
  const everyone = [...players]
    .map((nrp) => {
      const p = people.get(nrp)!;
      const a = answers.find((r) => String(r.nrp) === nrp)!;
      return {
        nrp,
        name: p.name,
        section: f.section || p.sections[0] || "",
        sets: setsOf.get(nrp)?.n ?? 0,
        answers: Number(a.n),
        correct: pct(Number(a.c ?? 0), Number(a.n)),
        xp: setsOf.get(nrp)?.xp ?? 0,
        streak: streaks.get(nrp) ?? 0,
        best_streak: best.get(nrp) ?? 0,
      };
    })
    .sort((a, b) => b.xp - a.xp || a.name.localeCompare(b.name));
  const top = everyone
    .filter((p) => p.sets > 0)
    .slice(0, 5)
    .map(({ nrp, name, section, xp, streak }) => ({ nrp, name, section, xp, streak }));

  const played = new Set(ever.map((r) => String(r.nrp)));
  const never = [...people.values()]
    .filter((p) => !played.has(p.nrp))
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((p) => ({ nrp: p.nrp, name: p.name, sections: p.sections, never: true, last: 0 }));

  return {
    players: players.size,
    users: people.size,
    correct: pct(total.c, total.n),
    trend_correct: earlier.n > 0 && total.n > 0 ? pct(total.c, total.n) - pct(earlier.c, earlier.n) : null,
    sets: done.reduce((t, r) => t + Number(r.n), 0),
    per_section: (f.section ? [f.section] : sections).map((section) => {
      const members = staff.filter((p) => p.sections.includes(section));
      return { section, players: members.filter((p) => players.has(p.nrp)).length, total: members.length };
    }),
    topics: [...byTopic]
      .map(([topic, t]) => ({ topic, answers: t.n, correct: pct(t.c, t.n) }))
      .sort((a, b) => a.correct - b.correct || b.answers - a.answers),
    hard,
    top,
    never,
    people: everyone,
  };
}

/// One question for the stats sheet: its row, and how often each choice was
/// picked.
export async function questionStats(db: Db, id: string) {
  const row = await questionRow(db, id);
  if (!row) return null;
  const picks = row.choices.map(() => 0);
  const rows = await db.all("SELECT chosen, COUNT(*) AS n FROM review_log WHERE question_id = ? GROUP BY chosen", id);
  let answers = 0;
  for (const r of rows) {
    const i = Number(r.chosen);
    answers += Number(r.n);
    if (i >= 0 && i < picks.length) picks[i] += Number(r.n);
  }
  return { ...row, picks, answers };
}
