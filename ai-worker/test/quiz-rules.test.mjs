import { test } from "node:test";
import assert from "node:assert/strict";
import { daysUntilNext } from "../src/quiz-rules.ts";

test("level 0 (baru salah) diulang besok", () => {
  assert.equal(daysUntilNext(0), 1);
});
// Tulis sendiri 3 tes lagi dengan pola yang sama:
// level 1 → 3 hari, level 6 → 90 hari, level 9 → tetap 90 hari

test("level 1 diulang 3 hari lagi", () => {
  assert.equal(daysUntilNext(1), 3);
});

test("level 6 diulang 90 hari lagi", () => {
  assert.equal(daysUntilNext(6), 90);
});

test("level 9 tetap diulang 90 hari lagi", () => {
  assert.equal(daysUntilNext(9), 90);
});

// ---- Aturan lain (ditambahkan bersama backend Quiz) ----
import {
  addDays, answerXp, capDaily, grade, nextCard, nextRatedCard, nextStreak, numbersMissing, pickSession,
  questionProblem, MAX_CARDS, quizDay, sessionBonus, streakBonus, streakNow, weekId, monthId,
} from "../src/quiz-rules.ts";

test("hari quiz mulai jam 04.00: jam 01.00 WIB masih hari kemarin", () => {
  // 6 Nov 2026 01.00 WIB = 5 Nov 18.00 UTC
  assert.equal(quizDay(Date.UTC(2026, 10, 5, 18), "Asia/Jakarta"), "2026-11-05");
  // 6 Nov 2026 04.30 WIB
  assert.equal(quizDay(Date.UTC(2026, 10, 5, 21, 30), "Asia/Jakarta"), "2026-11-06");
});

test("periode papan: minggu ISO dan bulan", () => {
  assert.equal(weekId("2026-11-02"), "W2026-45"); // Senin
  assert.equal(weekId("2026-11-08"), "W2026-45"); // Minggu
  assert.equal(weekId("2026-11-09"), "W2026-46");
  assert.equal(weekId("2027-01-01"), "W2026-53");
  assert.equal(monthId("2026-11-06"), "M2026-11");
});

test("soal baru dijawab benar: level 1, diulang 3 hari lagi", () => {
  assert.deepEqual(nextCard(null, true, "2026-11-06"), { level: 1, next_date: "2026-11-09", due: true });
});

test("benar tepat waktu naik satu level; level 6 tetap 6", () => {
  assert.equal(nextCard({ level: 3, next_date: "2026-11-06" }, true, "2026-11-06").level, 4);
  assert.equal(nextCard({ level: 3, next_date: "2026-11-06" }, true, "2026-11-06").next_date, addDays("2026-11-06", 30));
  assert.equal(nextCard({ level: 6, next_date: "2026-11-01" }, true, "2026-11-06").level, 6);
});

test("benar sebelum jadwal tidak naik level dan jadwal tetap", () => {
  assert.deepEqual(nextCard({ level: 2, next_date: "2026-11-10" }, true, "2026-11-06"), { level: 2, next_date: "2026-11-10", due: false });
});

test("salah kapan pun kembali ke level 0 dan diulang besok", () => {
  assert.deepEqual(nextCard({ level: 5, next_date: "2026-12-30" }, false, "2026-11-06"), { level: 0, next_date: "2026-11-07", due: false });
});

test("XP jawaban: benar 10, dikuasai 5, salah 2, cepat 0", () => {
  const base = { correct: true, ms: 5000, levelBefore: 1, due: true, correctToday: false };
  assert.equal(answerXp(base), 10);
  assert.equal(answerXp({ ...base, levelBefore: null }), 10);
  assert.equal(answerXp({ ...base, levelBefore: 4 }), 5);
  assert.equal(answerXp({ ...base, correct: false }), 2);
  assert.equal(answerXp({ ...base, ms: 1500 }), 0);
  assert.equal(answerXp({ ...base, correctToday: true }), 0);
  assert.equal(answerXp({ ...base, due: false }), 0);
});

test("batas 400 XP per hari", () => {
  assert.equal(capDaily(395, 10), 5);
  assert.equal(capDaily(400, 10), 0);
  assert.equal(capDaily(0, 10), 10);
});

test("bonus sesi dan streak", () => {
  assert.equal(sessionBonus(10, 10), 30);
  assert.equal(sessionBonus(7, 10), 10);
  assert.equal(streakBonus(3), 15);
  assert.equal(streakBonus(20), 35);
});

test("streak: kemarin +1, hari sama tetap, putus mulai 1", () => {
  const s = { streak: 4, best_streak: 4, last_daily: "2026-11-05", freeze_week: null };
  assert.equal(nextStreak(s, "2026-11-06").streak, 5);
  assert.equal(nextStreak(s, "2026-11-05").streak, 4);
  assert.equal(nextStreak({ ...s, last_daily: "2026-11-02" }, "2026-11-06").streak, 1);
  assert.equal(nextStreak({ ...s, last_daily: "2026-11-02" }, "2026-11-06").best_streak, 4);
});

test("libur streak: satu hari terlewat dipakai otomatis, sekali seminggu", () => {
  const s = { streak: 6, best_streak: 6, last_daily: "2026-11-04", freeze_week: null };
  const used = nextStreak(s, "2026-11-06");
  assert.equal(used.streak, 7);
  assert.equal(used.freezeUsed, true);
  assert.equal(used.freeze_week, "W2026-45");
  // Minggu yang sama sudah dipakai: putus.
  assert.equal(nextStreak({ ...s, freeze_week: "W2026-45" }, "2026-11-06").streak, 1);
  // Yang tampil di Home
  assert.equal(streakNow(s, "2026-11-06"), 6);
  assert.equal(streakNow({ ...s, freeze_week: "W2026-45" }, "2026-11-06"), 0);
  assert.equal(streakNow(s, "2026-11-05"), 6);
});

const q = (id) => ({ id });
test("menyusun 10 soal: maksimal 3 ulangan, sisanya soal baru", () => {
  const due = ["d1", "d2", "d3", "d4"].map(q);
  const fresh = Array.from({ length: 12 }, (_, i) => q(`n${i}`));
  const picked = pickSession(due, fresh, [], () => 0.5);
  assert.equal(picked.length, 10);
  assert.equal(picked.filter((p) => p.review).length, 3);
  assert.ok(!picked.some((p) => p.question.id === "d4"));
});

test("soal baru habis: diisi soal level terendah", () => {
  const picked = pickSession([q("d1")], [q("n1"), q("n2")], [q("f1"), q("f2"), q("n1")], () => 0.5);
  assert.deepEqual(picked.map((p) => p.question.id).sort(), ["d1", "f1", "f2", "n1", "n2"]);
});

const good = {
  section: "TRACK", unit: "PC210", topic: "torsi", type: "pg", prompt: "Torsi baut?",
  choices: ["98 Nm", "120 Nm", "59 Nm", "157 Nm"], answer: 0, explain: "Sesuai tabel.", manual_id: "sm", page: 12,
};
test("bentuk soal dicek sebelum disimpan", () => {
  assert.equal(questionProblem(good), null);
  assert.match(questionProblem({ ...good, answer: 4 }), /Kunci/);
  assert.match(questionProblem({ ...good, topic: "lain" }), /Topik/);
  assert.match(questionProblem({ ...good, choices: ["a", "a"] }), /sama/);
  assert.match(questionProblem({ ...good, page: 0 }), /halaman/);
});

test("angka jawaban dicek di halaman sumber", () => {
  assert.deepEqual(numbersMissing("98 Nm", "Tightening torque 98 Nm {10 kgm}"), []);
  assert.deepEqual(numbersMissing("1,5 l", "capacity 1.5 l"), []);
  assert.deepEqual(numbersMissing("120 Nm", "Tightening torque 98 Nm"), ["120"]);
});

// ---- Kartu ----

const KDAY = "2026-11-18";
const card = (level, next_date = KDAY) => ({ level, next_date, last_correct_day: null });

test("kartu: Lupa ke level 0 besok, Sulit tetap, Bisa naik 1, Mudah naik 2", () => {
  assert.deepEqual(nextRatedCard(card(3), 0, KDAY), { level: 0, next_date: "2026-11-19", due: true });
  assert.equal(nextRatedCard(card(3), 1, KDAY).level, 3);
  assert.equal(nextRatedCard(card(3), 2, KDAY).level, 4);
  assert.equal(nextRatedCard(card(3), 3, KDAY).level, 5);
  // A new card starts at level 0.
  assert.equal(nextRatedCard(null, 1, KDAY).level, 0);
  assert.equal(nextRatedCard(null, 3, KDAY).level, 2);
  // Never above the top level.
  assert.equal(nextRatedCard(card(6), 3, KDAY).level, 6);
});

test("kartu dinilai sebelum jadwalnya: hanya Lupa yang mengubahnya", () => {
  const early = card(2, "2026-11-25");
  assert.deepEqual(nextRatedCard(early, 3, KDAY), { level: 2, next_date: "2026-11-25", due: false });
  assert.equal(nextRatedCard(early, 0, KDAY).level, 0);
});

test("kartu: XP 5 untuk nilai apa pun, 0 kalau dibalik dalam 5 detik", () => {
  const kartu = { type: "kartu", answer: -1 };
  for (const chosen of [0, 1, 2, 3]) assert.equal(grade(kartu, { chosen, ms: 9000, card: null, day: KDAY }).xp, 5);
  assert.equal(grade(kartu, { chosen: 3, ms: 3000, card: null, day: KDAY }).xp, 0);
  assert.equal(grade(kartu, { chosen: 0, ms: 9000, card: null, day: KDAY }).correct, false);
  assert.equal(grade(kartu, { chosen: 2, ms: 9000, card: null, day: KDAY }).correct, true);
  // A normal question is still checked against its key.
  const pg = { type: "pg", answer: 1 };
  assert.equal(grade(pg, { chosen: 1, ms: 9000, card: null, day: KDAY }).correct, true);
  assert.equal(grade(pg, { chosen: 1, ms: 9000, card: null, day: KDAY }).xp, 10);
});

test("kartu tidak punya pilihan; poin kuncinya wajib", () => {
  const base = { section: "TRACK", unit: "PC210", topic: "sistem", type: "kartu", prompt: "Jelaskan cara kerja CLSS.", explain: "Poin 1\nPoin 2", manual_id: "pm", page: 115 };
  assert.equal(questionProblem({ ...base, choices: [], answer: -1 }), null);
  assert.equal(questionProblem({ ...base, choices: ["A", "B"], answer: 0 }), "Kartu tidak punya pilihan jawaban.");
  assert.equal(questionProblem({ ...base, choices: [], answer: -1, explain: " " }), "Poin kunci kosong.");
});

test("satu sesi berisi paling banyak 3 kartu", () => {
  const kartu = Array.from({ length: 8 }, (_, i) => ({ id: `k${i}`, type: "kartu" }));
  const pg = Array.from({ length: 4 }, (_, i) => ({ id: `p${i}`, type: "pg" }));
  const picked = pickSession([], [...kartu, ...pg], [], () => 0.5);
  assert.equal(picked.filter((p) => p.question.type === "kartu").length, MAX_CARDS);
  assert.equal(picked.length, MAX_CARDS + 4);
});
