// "Buat draf kuis" and the curator (src/quiz-ai.ts, src/quiz-jobs.ts), with
// a fake nyel AI instead of DeepSeek, on node:sqlite with the real migrations.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import * as quiz from "../src/quiz-db.ts";
import { cleanExplain, curate, stripCallouts, planPages, selfCheck, wantedFor, writeQuestions } from "../src/quiz-ai.ts";
import { createJob, listJobs, mixFrom, runJobs, targets, wantedForPage } from "../src/quiz-jobs.ts";

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

const TABLE = "STANDARD VALUE TABLE\nMain relief pressure (power max) 37.3 MPa {380 kg/cm2}\nSwing relief 28.4 MPa {290 kg/cm2}\nTravel relief 37.3 MPa\nPilot pressure 3.2 MPa {33 kg/cm2} at engine high idle";
const DRAWING = "CONTROL VALVE\n1. Boom spool\n2. Arm spool\n3. Main relief valve\n4. Safety-suction valve\n5. Pressure compensation valve\nA: To boom cylinder head";

/// A fake nyel AI: writes the questions asked for, and the curator gives
/// every question 8 except ones whose prompt says "jelek" (2).
function fakeAsk(calls = []) {
  return async (system, user) => {
    calls.push(system.slice(0, 20));
    if (system.includes("choose pages")) {
      return { pages: [{ page: 402, kind: "teks", topic: "standar" }, { page: 118, kind: "gambar", topic: "struktur" }, { page: 9999, kind: "teks" }] };
    }
    if (system.includes("senior heavy-equipment instructor")) {
      const list = JSON.parse(user.slice(user.indexOf("Questions:\n") + 11));
      return { reviews: list.map((q) => ({ i: q.i, score: q.prompt.includes("jelek") ? 2 : 8, verdict: q.prompt.includes("jelek") ? "buang" : "lolos", note: "Jelas." })) };
    }
    const m = /Write \d+ questions: (.*)\./.exec(user);
    const out = [];
    for (const part of m[1].split(", ")) {
      const [n, , , type] = part.split(" ");
      for (let i = 0; i < Number(n); i++) {
        const t = type.replace(/"/g, "");
        if (t === "gambar") out.push({ type: "gambar", prompt: `Komponen nomor 3 adalah? ${i}`, choices: ["Boom spool", "Main relief valve", "Arm spool", "Safety-suction valve"], answer: 1, explain: "Keterangan nomor 3.", callout: "3" });
        else if (t === "bs") out.push({ type: "bs", prompt: `Main relief 37.3 MPa ${i}`, choices: ["x"], answer: 0, explain: "Tabel." });
        else out.push({ type: "pg", prompt: i === 0 ? "Soal jelek" : `Tekanan main relief? ${i}`, choices: ["37.3 MPa", "28.4 MPa", "3.2 MPa", "31.4 MPa"], answer: 0, explain: "Tabel." });
      }
    }
    return { questions: out };
  };
}

test("mix and targets", () => {
  assert.deepEqual(mixFrom(null), { pg: 60, bs: 20, gambar: 20 });
  assert.deepEqual(mixFrom({ pg: 1, bs: 1, gambar: 0 }), { pg: 50, bs: 50, gambar: 0 });
  assert.deepEqual(targets(30, { pg: 60, bs: 20, gambar: 20 }, true), { pg: 18, bs: 6, gambar: 6 });
  assert.deepEqual(targets(30, { pg: 60, bs: 20, gambar: 20 }, false), { pg: 24, bs: 6, gambar: 0 });
  assert.deepEqual(wantedForPage("gambar", { pg: 10, bs: 2, gambar: 4 }, { teks: 5, gambar: 2 }), { pg: 0, bs: 0, gambar: 3 });
  // Enough pictures already: a drawing page gives text questions.
  assert.equal(wantedForPage("gambar", { pg: 3, bs: 0, gambar: 0 }, { teks: 0, gambar: 1 }).pg, 4);
  assert.deepEqual(wantedForPage("teks", { pg: 0, bs: 0, gambar: 2 }, { teks: 3, gambar: 1 }), { pg: 0, bs: 0, gambar: 0 });
  assert.deepEqual(wantedFor("campur", 5), { pg: 4, bs: 1, gambar: 0 });
  assert.deepEqual(wantedFor("gambar", 2), { pg: 0, bs: 0, gambar: 2 });
});

test("self check: numbers for text, number and name for pictures", () => {
  const base = { section: "TRACK", unit: "PC210", topic: "standar", manual_id: "sm", page: 402, explain: "x" };
  assert.equal(selfCheck({ ...base, type: "pg", prompt: "?", choices: ["37.3 MPa", "9 MPa"], answer: 0 }, TABLE).ok, true);
  assert.match(selfCheck({ ...base, type: "pg", prompt: "?", choices: ["34.8 MPa", "9 MPa"], answer: 0 }, TABLE).note, /34\.8/);
  const pic = { ...base, type: "gambar", prompt: "?", choices: ["Boom spool", "Main relief valve"], answer: 1, callout: "3" };
  assert.equal(selfCheck(pic, DRAWING).ok, true);
  assert.equal(selfCheck({ ...pic, callout: "8" }, DRAWING).ok, false);
  assert.equal(selfCheck({ ...pic, choices: ["Boom spool", "Relief kecil"] }, DRAWING).ok, false);
});

test("writer and curator: bad questions dropped, the rest scored", async () => {
  const ask = fakeAsk();
  const out = await writeQuestions(ask, { section: "TRACK", unit: "PC210", topic: "standar", manual_id: "sm", page: 402 }, TABLE, { pg: 3, bs: 1, gambar: 0 });
  assert.equal(out.drafts.length, 4);
  assert.deepEqual(out.drafts.find((d) => d.type === "bs").choices, ["Benar", "Salah"]);
  const reviewed = await curate(ask, out.drafts, TABLE);
  assert.equal(reviewed.dropped, 1);
  assert.equal(reviewed.kept.length, 3);
  assert.equal(reviewed.kept[0].score, 8);
  // No answer from the curator: kept, unscored.
  const silent = await curate(async () => null, out.drafts, TABLE);
  assert.equal(silent.kept.length, 4);
  assert.equal(silent.kept[0].score, null);
});

test("plan keeps pages inside the manual, no duplicates", async () => {
  const pages = await planPages(fakeAsk(), "1\tCover\n402\tStandard value table", 2454, 5, "semua", true);
  assert.deepEqual(pages.map((p) => [p.page, p.kind]), [[402, "teks"], [118, "gambar"]]);
  const noPictures = await planPages(fakeAsk(), "1\tCover\n402\tStandard value table", 2454, 5, "semua", false);
  assert.equal(noPictures[1].kind, "teks");
});

test("a job runs page by page into drafts; passed ones can be approved at once", async () => {
  const db = fresh();
  const NOW = Date.UTC(2026, 10, 6, 2);
  const id = await createJob(
    db,
    {
      section: "track",
      unit: "PC210",
      manual_id: "PC210/sm",
      title: "Shop Manual",
      topic: "semua",
      count: 6,
      mix: { pg: 60, bs: 20, gambar: 20 },
      pages: [
        { page: 402, kind: "teks", topic: "standar", text: TABLE },
        { page: 118, kind: "gambar", topic: "struktur", text: DRAWING },
        { page: 5, kind: "teks", topic: "standar", text: "short" },
        { page: 410, kind: "teks", topic: "standar", text: TABLE },
      ],
    },
    "ADM",
    NOW,
  );
  // The page without text is not kept.
  assert.equal((await db.first("SELECT COUNT(*) AS n FROM quiz_job_page WHERE job_id = ?", id)).n, 3);
  const worked = await runJobs(db, fakeAsk(), NOW + 60_000, () => NOW);
  assert.equal(worked, 1);
  const [job] = await listJobs(db);
  assert.equal(job.status, "selesai");
  assert.ok(job.passed >= 6, `passed ${job.passed}`);
  assert.ok(job.dropped >= 1);
  const drafts = await quiz.listQuestions(db, "draf", null);
  assert.ok(drafts.every((q) => q.job_id === id && q.curator_score === 8));
  const picture = drafts.find((q) => q.type === "gambar");
  assert.ok(picture.passed);
  // A finished job is not run again.
  assert.equal(await runJobs(db, fakeAsk(), NOW + 60_000, () => NOW), 0);

  // Approve all passed: the picture question waits for its picture.
  const ids = drafts.map((q) => q.id);
  const first = await quiz.approvePassed(db, ids, "ADM", NOW);
  assert.deepEqual(first.left, drafts.filter((q) => q.type === "gambar").map((q) => q.id));
  await quiz.setImage(db, picture.id, "quiz/img/x.png", NOW);
  const second = await quiz.approvePassed(db, first.left, "ADM", NOW);
  assert.ok(second.published >= 1);
  assert.equal((await quiz.listQuestions(db, "terbit", null)).find((q) => q.id === picture.id).image, "quiz/img/x.png");
  // An admin edit keeps the picture.
  const q = (await quiz.listQuestions(db, "terbit", null)).find((x) => x.id === picture.id);
  await quiz.decide(db, q.id, "ubah", "ADM", { ...q, prompt: "Nomor 3?" }, NOW);
  assert.equal((await db.first("SELECT image FROM question WHERE id = ?", q.id)).image, "quiz/img/x.png");
});

test("a job stops when time is up and goes on in the next run", async () => {
  const db = fresh();
  const NOW = Date.UTC(2026, 10, 6, 2);
  await createJob(
    db,
    { section: "TRACK", unit: "PC210", manual_id: "PC210/sm", title: "SM", topic: "semua", count: 30, mix: { pg: 100, bs: 0, gambar: 0 }, pages: [402, 403, 404].map((page) => ({ page, kind: "teks", topic: "standar", text: TABLE })) },
    "ADM",
    NOW,
  );
  // Every AI call takes 40 s: one page (writer + curator) is 80 s.
  let t = NOW;
  const ai = fakeAsk();
  const slow = async (...a) => {
    t += 40_000;
    return ai(...a);
  };
  await runJobs(db, slow, NOW + 100_000, () => t);
  const [half] = await listJobs(db);
  assert.equal(half.status, "jalan");
  assert.ok(half.pages_done >= 1 && half.pages_done < 3);
  await runJobs(db, fakeAsk(), Infinity, () => NOW + 3_600_000);
  const [done] = await listJobs(db);
  assert.equal(done.status, "selesai");
  assert.equal(done.pages_done, 3);
});

test("a job where nyel AI never answers fails with a message", async () => {
  const db = fresh();
  const NOW = Date.UTC(2026, 10, 6, 2);
  await createJob(db, { section: "TRACK", unit: null, manual_id: "m", title: "M", topic: "semua", count: 5, mix: { pg: 100, bs: 0, gambar: 0 }, pages: [{ page: 1, kind: "teks", topic: "standar", text: TABLE }] }, "ADM", NOW);
  await runJobs(db, async () => null, Infinity, () => NOW);
  const [job] = await listJobs(db);
  assert.equal(job.status, "gagal");
  assert.match(job.error, /tidak menjawab/);
});

test("explanations start with the fact", () => {
  assert.equal(cleanExplain("Halaman menyatakan bahwa OLSS mengurangi kerugian."), "OLSS mengurangi kerugian.");
  assert.equal(cleanExplain("Menurut manual, relief valve membuka pada 34,8 MPa."), "Relief valve membuka pada 34,8 MPa.");
  assert.equal(cleanExplain("Halaman ini menjelaskan: pompa diatur oleh PC valve."), "Pompa diatur oleh PC valve.");
  assert.equal(cleanExplain("Relief valve membatasi tekanan."), "Relief valve membatasi tekanan.");
});

test("pg and bs questions lose the drawing's callout numbers", () => {
  const q = stripCallouts({ type: "pg", prompt: "Dari mana oli pilot menuju pilot manifold (35) berasal?", choices: ["Pilot pump (39)", "Pilot accumulator (31)"], answer: 0, explain: "Oli dari pilot pump (39) mensuplai pilot manifold (35)." });
  assert.equal(q.prompt, "Dari mana oli pilot menuju pilot manifold berasal?");
  assert.deepEqual(q.choices, ["Pilot pump", "Pilot accumulator"]);
  assert.equal(q.explain, "Oli dari pilot pump mensuplai pilot manifold.");
  const pic = stripCallouts({ type: "gambar", prompt: "Komponen nomor (3) adalah?", choices: ["A", "B"], answer: 0, explain: "" });
  assert.equal(pic.prompt, "Komponen nomor (3) adalah?");
  assert.match(selfCheck({ type: "pg", page: 4, prompt: "Pada gambar, part ini?", choices: ["A", "B"], answer: 0, explain: "" }, "A").note, /gambar/);
});

test("self check: a labelled photo question needs its label on the page", () => {
  const base = { section: "TRACK", unit: "PC1250", topic: "struktur", manual_id: "m", page: 158, explain: "" };
  const LABELS = "PSV\r\nPressure \r\nreducing valve\r\nTVC output \r\npressure Servo valve\r\nTVC valve\r\nCO NC Valve\r\nPD\r\nPT";
  const q = { ...base, type: "gambar", prompt: "Pada foto pompa PC1250, komponen bertanda [X] adalah?", choices: ["CO NC Valve", "TVC valve", "PSV", "PT"], answer: 0, callout: "CO NC Valve" };
  assert.equal(selfCheck(q, LABELS).ok, true);
  assert.equal(selfCheck({ ...q, choices: ["Main relief", "TVC valve"], callout: "Main relief" }, LABELS).ok, false);
});
