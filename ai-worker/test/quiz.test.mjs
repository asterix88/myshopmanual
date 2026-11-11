// The Quiz database code (src/quiz-db.ts) on node:sqlite, with the real
// migration file, so the tables and the SQL are tested together.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import * as quiz from "../src/quiz-db.ts";
import { runNightly } from "../src/quiz-cron.ts";

function fresh() {
  const d = new DatabaseSync(":memory:");
  for (const file of ["0001_quiz.sql", "0002_quiz_jobs.sql", "0003_quiz_image_edit.sql"]) {
    d.exec(readFileSync(new URL(`../migrations/${file}`, import.meta.url), "utf8"));
  }
  const run = (sql, b) => d.prepare(sql).run(...b.map((v) => (v === undefined ? null : v)));
  return {
    all: async (sql, ...b) => d.prepare(sql).all(...b),
    first: async (sql, ...b) => d.prepare(sql).get(...b) ?? null,
    run: async (sql, ...b) => Number(run(sql, b).changes),
    batch: async (list) => {
      d.exec("BEGIN");
      try {
        for (const [sql, ...b] of list) run(sql, b);
        d.exec("COMMIT");
      } catch (e) {
        d.exec("ROLLBACK");
        throw e;
      }
    },
  };
}

// 6 Nov 2026 08.00 WIB
const NOW = Date.UTC(2026, 10, 6, 1);
const DAY = 86400_000;
const ali = { nrp: "A1", name: "Ali", sections: ["TRACK"], departemen: "PLANT" };
const budi = { nrp: "B2", name: "Budi", sections: ["TRACK"], departemen: "PLANT" };
const wati = { nrp: "W3", name: "Wati", sections: ["WHEEL"], departemen: "PLANT" };

async function seed(db, n = 12, unit = "PC210", section = "TRACK") {
  for (let i = 0; i < n; i++) {
    await quiz.addQuestion(
      db,
      { section, unit, topic: "torsi", type: "pg", prompt: `Soal ${unit} ${i}`, choices: ["A", "B", "C", "D"], answer: 1, explain: "x", manual_id: "sm", page: i + 1 },
      { status: "terbit", source: "admin", by: "ADM", id: `${unit}-${i}`, now: NOW },
    );
  }
}

let seq = 0;
async function play(db, who, s, { wrong = 0, now = NOW, ms = 5000 } = {}) {
  for (const [i, q] of s.questions.entries()) {
    await quiz.answer(db, who, { id: `a${seq++}`, session_id: s.id, question_id: q.id, chosen: i < wrong ? 0 : 1, ms }, now);
  }
  return quiz.finish(db, who, s.id, now);
}

test("migration keeps itself: running it twice changes nothing", async () => {
  const d = new DatabaseSync(":memory:");
  const sql = readFileSync(new URL("../migrations/0001_quiz.sql", import.meta.url), "utf8");
  d.exec(sql);
  d.exec(sql);
  assert.equal(d.prepare("SELECT COUNT(*) AS n FROM site").get().n, 1);
});

test("a mechanic gets 10 questions of their section, with answers", async () => {
  const db = fresh();
  await seed(db, 12);
  await seed(db, 5, "WA500", "WHEEL");
  await quiz.ensureUser(db, ali, () => 0.35);
  const s = await quiz.startSession(db, ali, "harian", null, { now: NOW });
  assert.equal(s.questions.length, 10);
  assert.ok(s.questions.every((q) => q.unit === "PC210" && q.choices.length === 4 && q.answer === 1));
  const u = await db.first("SELECT avatar, site FROM quiz_user WHERE nrp = 'A1'");
  assert.deepEqual({ ...u }, { avatar: 3, site: "SBS" });
});

test("an unfinished Quiz harian comes back the same; a finished one is done for the day", async () => {
  const db = fresh();
  await seed(db, 12);
  await quiz.ensureUser(db, ali);
  const s = await quiz.startSession(db, ali, "harian", null, { now: NOW });
  const again = await quiz.startSession(db, ali, "harian", null, { now: NOW + 60_000 });
  assert.equal(again.id, s.id);
  await play(db, ali, s);
  assert.deepEqual(await quiz.startSession(db, ali, "harian", null, { now: NOW + 120_000 }), { error: "done" });
  // Quiz per unit may be played again and again.
  const unit = await quiz.startSession(db, ali, "unit", "PC210", { now: NOW + 180_000 });
  assert.equal(unit.questions.length, 10);
});

test("answers: XP, level, resend counted once, 400 XP limit", async () => {
  const db = fresh();
  await seed(db, 12);
  await quiz.ensureUser(db, ali);
  const s = await quiz.startSession(db, ali, "harian", null, { now: NOW });
  const q = s.questions[0];
  const a = { id: "x1", session_id: s.id, question_id: q.id, chosen: 1, ms: 4000 };
  assert.deepEqual(await quiz.answer(db, ali, a, NOW), { correct: true, xp: 10, level: 1, next_days: 3, mastered: false });
  await quiz.answer(db, ali, a, NOW);
  assert.equal((await db.first("SELECT answered, xp FROM daily_stats")).answered, 1);
  const wrong = await quiz.answer(db, ali, { ...a, id: "x2", question_id: s.questions[1].id, chosen: 3 }, NOW);
  assert.deepEqual(wrong, { correct: false, xp: 2, level: 0, next_days: 1, mastered: false });
  assert.deepEqual(await quiz.answer(db, ali, { ...a, id: "x3", question_id: "nope" }, NOW), { error: "question" });
  await db.run("UPDATE daily_stats SET xp = 395");
  assert.equal((await quiz.answer(db, ali, { ...a, id: "x4", question_id: s.questions[2].id }, NOW)).xp, 5);
});

test("finish: bonus, streak and the leaderboard", async () => {
  const db = fresh();
  await seed(db, 30);
  for (const who of [ali, budi, wati]) await quiz.ensureUser(db, who);
  const s = await quiz.startSession(db, ali, "harian", null, { now: NOW });
  const out = await play(db, ali, s);
  // 10 x 10 + finish 10 + perfect 20 + streak 1 day 5
  assert.deepEqual(out, { score: 10, total: 10, xp_session: 135, bonus: 35, streak: 1, freeze_used: false, rank: 1 });
  const sb = await quiz.startSession(db, budi, "harian", null, { now: NOW });
  const ob = await play(db, budi, sb, { wrong: 3 });
  assert.equal(ob.score, 7);
  assert.equal(ob.xp_session, 7 * 10 + 3 * 2 + 10 + 5);
  assert.equal(ob.rank, 2);
  const board = await quiz.leaderboard(db, budi, "week", NOW);
  assert.equal(board.period, "W2026-45");
  assert.deepEqual(board.rows.map((r) => [r.rank, r.nrp, r.xp]), [[1, "A1", 135], [2, "B2", 91]]);
  assert.equal(board.me.nrp, "B2");
  assert.equal(board.count, 2);
  // Wati (WHEEL) is on the same department board, across sections.
  assert.equal((await quiz.leaderboard(db, wati, "month", NOW)).rows.length, 2);
  // Hidden accounts leave the board.
  await quiz.hideFromBoard(db, "A1", true);
  assert.equal((await quiz.leaderboard(db, budi, "week", NOW)).rows[0].nrp, "B2");
});

test("next day: wrong answers come back as reviews, streak goes on", async () => {
  const db = fresh();
  await seed(db, 30);
  await quiz.ensureUser(db, ali);
  const s1 = await quiz.startSession(db, ali, "harian", null, { now: NOW });
  await play(db, ali, s1, { wrong: 4 });
  const s2 = await quiz.startSession(db, ali, "harian", null, { now: NOW + DAY });
  const reviews = s2.questions.filter((q) => q.review);
  assert.equal(reviews.length, 3);
  assert.ok(reviews.every((q) => q.level === 0));
  const out = await play(db, ali, s2, { now: NOW + DAY });
  assert.equal(out.streak, 2);
  const home = await quiz.home(db, ali, NOW + DAY);
  assert.equal(home.daily, "selesai");
  assert.equal(home.streak, 2);
  assert.equal(home.rank_week, 1);
  assert.equal(home.questions, 30);
});

test("streak freeze after one missed day", async () => {
  const db = fresh();
  await seed(db, 40);
  await quiz.ensureUser(db, ali);
  await play(db, ali, await quiz.startSession(db, ali, "harian", null, { now: NOW }));
  const later = NOW + 2 * DAY; // 7 Nov missed
  const out = await play(db, ali, await quiz.startSession(db, ali, "harian", null, { now: later }), { now: later });
  assert.equal(out.streak, 2);
  assert.equal(out.freeze_used, true);
});

test("units list shows mastered questions (level 4+)", async () => {
  const db = fresh();
  await seed(db, 12);
  await quiz.ensureUser(db, ali);
  await db.run("INSERT INTO card_state (nrp, question_id, unit, level, next_date) VALUES ('A1', 'PC210-0', 'PC210', 4, '2026-12-01')");
  assert.deepEqual(await quiz.units(db, ali), [{ unit: "PC210", total: 12, seen: 1, mastered: 1 }]);
});

test("two reports pull a question; approving brings it back", async () => {
  const db = fresh();
  await seed(db, 3);
  for (const who of [ali, budi]) await quiz.ensureUser(db, who);
  assert.deepEqual(await quiz.report(db, ali, "PC210-0", "angka salah", NOW), { pulled: false });
  assert.deepEqual(await quiz.report(db, budi, "PC210-0", "", NOW), { pulled: true });
  assert.equal((await db.first("SELECT status FROM question WHERE id = 'PC210-0'")).status, "ditarik");
  assert.equal((await quiz.openReports(db)).length, 2);
  await quiz.decide(db, "PC210-0", "setujui", "ADM", null, NOW);
  assert.equal((await db.first("SELECT status FROM question WHERE id = 'PC210-0'")).status, "terbit");
  assert.equal((await quiz.openReports(db)).length, 0);
});

test("drafts wait for an admin; edits are saved", async () => {
  const db = fresh();
  const id = await quiz.addQuestion(
    db,
    { section: "track", unit: "PC210", topic: "torsi", type: "pg", prompt: "?", choices: ["1", "2"], answer: 0, explain: "x", manual_id: "sm", page: 3 },
    { status: "draf", source: "ai", by: "ADM", check_note: "ok", now: NOW },
  );
  await quiz.ensureUser(db, ali);
  assert.deepEqual(await quiz.startSession(db, ali, "harian", null, { now: NOW }), { error: "empty" });
  assert.equal((await quiz.listQuestions(db, "draf", null))[0].section, "TRACK");
  const edit = { section: "TRACK", unit: "PC210", topic: "torsi", type: "pg", prompt: "Baru?", choices: ["1", "2", "3"], answer: 2, explain: "y", manual_id: "sm", page: 3 };
  await quiz.decide(db, id, "setujui", "ADM", edit, NOW);
  const [q] = await quiz.listQuestions(db, "terbit", "PC210");
  assert.equal(q.prompt, "Baru?");
  assert.equal(q.answer, 2);
  assert.equal(q.reviewed_by, "ADM");
});

test("nightly: rank change, hard questions flagged, old answers removed", async () => {
  const db = fresh();
  await seed(db, 30);
  for (const who of [ali, budi]) await quiz.ensureUser(db, who);
  await play(db, ali, await quiz.startSession(db, ali, "harian", null, { now: NOW }));
  await play(db, budi, await quiz.startSession(db, budi, "harian", null, { now: NOW }), { wrong: 5 });
  await runNightly(db, NOW);
  // Budi overtakes Ali with a unit quiz after the nightly run.
  for (let i = 0; i < 2; i++) await play(db, budi, await quiz.startSession(db, budi, "unit", "PC210", { now: NOW + 1000 + i }), { now: NOW + 1000 + i });
  const board = await quiz.leaderboard(db, ali, "week", NOW);
  assert.deepEqual(board.rows.map((r) => [r.nrp, r.change]), [["B2", 1], ["A1", -1]]);

  for (let i = 0; i < 20; i++) {
    await db.run("INSERT INTO review_log (id, session_id, nrp, question_id, chosen, correct, level_after, xp, ms, answered_at) VALUES (?, 's', 'X', 'PC210-29', 0, 0, 0, 2, 3000, ?)", `h${i}`, NOW);
  }
  await db.run("INSERT INTO review_log (id, session_id, nrp, question_id, chosen, correct, level_after, xp, ms, answered_at) VALUES ('old', 's', 'X', 'PC210-1', 0, 1, 1, 10, 3000, ?)", NOW - 200 * DAY);
  await runNightly(db, NOW);
  assert.equal((await db.first("SELECT status FROM question WHERE id = 'PC210-29'")).status, "perlu_cek");
  assert.equal(await db.first("SELECT id FROM review_log WHERE id = 'old'"), null);
});

test("quiz statistics: players, weak topics, hard questions, never played", async () => {
  const { quizStats, questionStats } = await import("../src/quiz-stats.ts");
  const db = fresh();
  // One set's worth, so both play every question and each has 2 answers.
  await seed(db, 10);
  for (const who of [ali, budi]) await quiz.ensureUser(db, who, () => 0.1);
  await play(db, ali, await quiz.startSession(db, ali, "harian", null, { now: NOW }), { wrong: 2 });
  await play(db, budi, await quiz.startSession(db, budi, "harian", null, { now: NOW }), { wrong: 6 });
  const staff = [
    { nrp: "A1", name: "Ali", sections: ["TRACK"] },
    { nrp: "B2", name: "Budi", sections: ["TRACK"] },
    { nrp: "C3", name: "Cahyo", sections: ["TRACK"] },
    { nrp: "W3", name: "Wati", sections: ["WHEEL"] },
  ];
  const s = await quizStats(db, { since: NOW - 7 * DAY, section: "" }, staff, ["TRACK", "WHEEL"], NOW + 60_000);
  assert.equal(s.players, 2);
  assert.equal(s.users, 4);
  assert.equal(s.correct, 60); // 8 + 4 of 20
  assert.equal(s.sets, 2);
  assert.deepEqual(s.per_section, [
    { section: "TRACK", players: 2, total: 3 },
    { section: "WHEEL", players: 0, total: 1 },
  ]);
  assert.deepEqual(s.topics, [{ topic: "torsi", answers: 20, correct: 60 }]);
  assert.deepEqual(s.top.map((p) => p.nrp), ["A1", "B2"]);
  assert.equal(s.top[0].streak, 1);
  assert.deepEqual(s.never.map((p) => p.nrp), ["C3", "W3"]);
  assert.equal(s.people.find((p) => p.nrp === "B2").correct, 40);
  // Only 2 answers per question: none is "hard" yet.
  assert.deepEqual(s.hard, []);
  // One section: the others' people are left out.
  const wheel = await quizStats(db, { since: NOW - 7 * DAY, section: "WHEEL" }, staff, ["TRACK", "WHEEL"], NOW + 60_000);
  assert.equal(wheel.players, 0);
  assert.deepEqual(wheel.never.map((p) => p.nrp), ["W3"]);

  const asked = (await db.first("SELECT question_id FROM review_log WHERE nrp = 'B2' AND chosen = 0")).question_id;
  const q = await questionStats(db, asked);
  assert.equal(q.answers, 2);
  assert.equal(q.picks.reduce((a, b) => a + b, 0), 2);
  assert.equal(q.picks[0] >= 1, true);
  assert.equal(await questionStats(db, "nope"), null);
});

test("a labelled photo's letter takes the place of [X] when its picture is saved", async () => {
  const db = fresh();
  await quiz.addQuestion(
    db,
    { section: "TRACK", unit: "PC1250", topic: "struktur", type: "gambar", prompt: "Pada foto pompa, komponen bertanda [X] adalah?", choices: ["PSV", "PT", "PD", "TVC valve"], answer: 0, explain: "x", manual_id: "m", page: 158 },
    { status: "draf", source: "ai", by: "ADM", id: "L1", now: NOW },
  );
  assert.equal(await quiz.setImage(db, "L1", "quiz/img/a.png", NOW, "C"), true);
  assert.equal((await db.first("SELECT prompt, image FROM question WHERE id = 'L1'")).prompt, "Pada foto pompa, komponen bertanda C adalah?");
  // Drawn again later: the letter is already there; nothing else changes.
  assert.equal(await quiz.setImage(db, "L1", "quiz/img/b.png", NOW, "C"), true);
  assert.equal((await db.first("SELECT image FROM question WHERE id = 'L1'")).image, "quiz/img/b.png");
  // Edited in "Atur gambar": the asked label is now E, and the question says so.
  assert.equal(await quiz.setImage(db, "L1", "quiz/img/c.png", NOW, "E"), true);
  assert.equal((await db.first("SELECT prompt FROM question WHERE id = 'L1'")).prompt, "Pada foto pompa, komponen bertanda E adalah?");
  // The editor's data comes back with the question.
  const edit = { v: 1, crop: [0, 0, 100, 50], labels: [{ box: [1, 2, 3, 4], text: "PSV" }] };
  assert.equal(await quiz.setImageEdit(db, "L1", edit), true);
  assert.deepEqual((await quiz.questionRow(db, "L1")).image_edit, edit);
  assert.equal(await quiz.setImageEdit(db, "nope", edit), false);
  // The admin rewrites the question: the [X] text is dropped with it.
  const row = await quiz.questionRow(db, "L1");
  await quiz.decide(db, "L1", "ubah", "ADM", { ...row, prompt: "Komponen bertanda E pada foto adalah?" }, NOW);
  assert.equal(await quiz.setImage(db, "L1", "quiz/img/d.png", NOW, "B"), true);
  assert.equal((await db.first("SELECT prompt FROM question WHERE id = 'L1'")).prompt, "Komponen bertanda E pada foto adalah?");
});

test("a pg question can get a picture and lose it again; a picture question keeps its own", async () => {
  const db = fresh();
  await quiz.addQuestion(
    db,
    { section: "TRACK", unit: "PC210", topic: "standar", type: "pg", prompt: "Set pressure safety valve travel motor?", choices: ["27.4 MPa", "41.7 MPa", "34.8 MPa", "3.9 MPa"], answer: 1, explain: "x", manual_id: "pm", page: 206 },
    { status: "draf", source: "ai", by: "ADM", id: "P1", now: NOW },
  );
  await quiz.addQuestion(
    db,
    { section: "TRACK", unit: "PC210", topic: "struktur", type: "gambar", prompt: "Komponen nomor 3 adalah?", choices: ["A", "B", "C", "D"], answer: 0, explain: "x", manual_id: "pm", page: 206 },
    { status: "draf", source: "ai", by: "ADM", id: "G1", now: NOW },
  );
  assert.equal(await quiz.setImage(db, "P1", "quiz/img/p.png", NOW), true);
  assert.equal(await quiz.setImageEdit(db, "P1", { v: 1, crop: [0, 0, 10, 10] }), true);
  assert.equal((await quiz.questionRow(db, "P1")).image, "quiz/img/p.png");
  assert.equal(await quiz.removeImage(db, "P1", NOW), true);
  const row = await quiz.questionRow(db, "P1");
  assert.equal(row.image, null);
  assert.equal(row.image_edit, null);
  await quiz.setImage(db, "G1", "quiz/img/g.png", NOW);
  assert.equal(await quiz.removeImage(db, "G1", NOW), false);
  assert.equal((await quiz.questionRow(db, "G1")).image, "quiz/img/g.png");
});

test("saving or removing a picture keeps the draft in its place in the list", async () => {
  const db = fresh();
  const add = (id, at) =>
    quiz.addQuestion(
      db,
      { section: "TRACK", unit: "PC210", topic: "standar", type: "pg", prompt: `Soal ${id}?`, choices: ["1", "2", "3", "4"], answer: 0, explain: "x", manual_id: "pm", page: 1 },
      { status: "draf", source: "ai", by: "ADM", id, now: at },
    );
  await add("old", NOW);
  await add("new", NOW + 1000);
  const order = async () => (await quiz.listQuestions(db, "draf", null)).map((q) => q.id);
  assert.deepEqual(await order(), ["new", "old"]);
  await quiz.setImageEdit(db, "old", { v: 1, crop: [0, 0, 1, 1] }, NOW + 5000);
  await quiz.setImage(db, "old", "quiz/img/o.png", NOW + 5000);
  assert.deepEqual(await order(), ["new", "old"]);
  await quiz.removeImage(db, "old", NOW + 6000);
  assert.deepEqual(await order(), ["new", "old"]);
  assert.equal((await quiz.listQuestions(db, "draf", null)).length, 2);
});
