// The statistics queries (src/stats-db.ts) on node:sqlite, the same SQLite
// a Durable Object has.
import { test } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import * as db from "../src/stats-db.ts";

function fresh() {
  const d = new DatabaseSync(":memory:");
  const sql = {
    exec: (q, ...b) => {
      const st = d.prepare(q);
      if (/^\s*(SELECT|WITH)/i.test(q)) return { toArray: () => st.all(...b) };
      st.run(...b);
      return { toArray: () => [] };
    },
  };
  db.setup(sql);
  return sql;
}

const day = 86400_000;
const now = Date.now();
const ali = { nrp: "A1", name: "Ali", sections: ["TRACK"] };
const budi = { nrp: "B2", name: "Budi", sections: ["WHEEL"] };
const all = { since: 0, section: "" };
const last30 = { since: now - 30 * day, section: "" };

function seed(sql) {
  const sm = { file: "units/PC210/sm.pdf", unit: "PC210", title: "Shop Manual PC210" };
  const mlu = { file: "units/PANDUAN MLU/mlu.pdf", unit: "PANDUAN MLU", title: "Panduan MLU" };
  db.add(sql, ali, [
    { at: now - day, kind: "open", ...sm },
    { at: now - day, kind: "chapter", ...sm, q: "Testing and adjusting" },
    { at: now - 2 * day, kind: "open", ...sm },
    { at: now - 40 * day, kind: "open", ...sm },
    { at: now - day, kind: "download", ...sm },
    { at: now - day, kind: "open", ...mlu },
    { at: now - day, kind: "search", q: "Relief Valve", hits: 12 },
    { at: now - day, kind: "search", q: "xyz123 seal", hits: 0 },
    {
      at: now - day, kind: "ai", unit: "PC210", q: "Berapa tekanan main relief?",
      extra: { answer: "37,3 MPa", sources: ["SM PC210 · hal. 412"], queries: ["main relief valve pressure PC210"] },
    },
    { at: now - day + 1, kind: "rate", q: "Berapa tekanan main relief?", hits: 1 },
  ]);
  db.add(sql, budi, [
    { at: now - day, kind: "open", ...mlu },
    { at: now - day, kind: "search", q: "xyz123 SEAL", hits: 0 },
    { at: now - day, kind: "ai", q: "Kode CA234?", extra: { queries: ["CA234", "relief valve D375"] } },
  ]);
}

test("clean drops what makes no sense and fixes wrong clocks", () => {
  const events = db.clean(
    [
      { kind: "open", file: "units/PC210/sm.pdf", at: now - 1000 },
      { kind: "open" }, // no file
      { kind: "rate", q: "x" }, // only the server records ratings
      { kind: "search", q: "seal", hits: 3, at: now + 10 * day },
      "junk",
    ],
    now,
  );
  assert.deepEqual(events.map((e) => e.kind), ["open", "search"]);
  assert.equal(events[1].at, now);
});

test("overview counts, lists and keeps shared manuals out of Per unit", () => {
  const sql = fresh();
  seed(sql);
  const o = db.overview(sql, last30, ["PANDUAN MLU"]);
  assert.equal(o.opens, 4);
  assert.equal(o.ai, 2);
  assert.deepEqual(o.manuals.map((m) => [m.title, m.n, m.people, m.shared]), [
    ["Panduan MLU", 2, 2, true],
    ["Shop Manual PC210", 2, 1, false],
  ]);
  assert.deepEqual(o.units, [{ unit: "PC210", n: 2 }]);
  assert.deepEqual(o.ratings, { good: 1, bad: 0 });
  assert.deepEqual(o.questions.map((q) => q.name), ["Budi", "Ali"]);
  assert.deepEqual(o.missing, [{ q: "xyz123 seal", n: 2, people: 2 }]);
  assert.equal(o.people[0].nrp, "A1");
  assert.equal(o.people[0].manuals, 3);
  assert.equal(db.overview(sql, all, []).opens, 5);
});

test("the section filter is the reader's section", () => {
  const sql = fresh();
  seed(sql);
  const wheel = db.overview(sql, { since: 0, section: "WHEEL" }, ["PANDUAN MLU"]);
  assert.deepEqual(wheel.manuals.map((m) => [m.title, m.n]), [["Panduan MLU", 1]]);
  assert.deepEqual(wheel.people.map((p) => p.nrp), ["B2"]);
  assert.deepEqual(wheel.units, []);
});

test("a handled search stays hidden until searched again", () => {
  const sql = fresh();
  seed(sql);
  db.markHandled(sql, "XYZ123 seal", now);
  assert.deepEqual(db.overview(sql, all, []).missing, []);
  db.add(sql, ali, [{ at: now + 1, kind: "search", q: "xyz123 seal", hits: 0 }]);
  assert.equal(db.overview(sql, all, []).missing.length, 1);
});

test("details: manual, person, answer, search", () => {
  const sql = fresh();
  seed(sql);
  const m = db.manual(sql, last30, "units/PC210/sm.pdf");
  assert.deepEqual([m.opens, m.people, m.downloads], [2, 1, 1]);
  assert.deepEqual(m.chapters, [{ title: "Testing and adjusting", n: 1 }]);
  assert.deepEqual(m.readers, [{ nrp: "A1", name: "Ali", n: 2 }]);

  const p = db.person(sql, last30, "A1");
  assert.deepEqual([p.manuals_opened, p.ai, p.searches], [3, 1, 2]);
  assert.equal(p.questions.length, 1);

  const a = db.answer(sql, p.questions[0].id);
  assert.equal(a.answer, "37,3 MPa");
  assert.deepEqual(a.sources, ["SM PC210 · hal. 412"]);
  assert.equal(a.rating, "good");
  assert.equal(a.topic, "Main relief");

  const s = db.search(sql, all, "XYZ123 Seal");
  assert.equal(s.n, 2);
  assert.deepEqual(s.who.map((w) => w.name).sort(), ["Ali", "Budi"]);
});

test("topics count each question once and group fault codes", () => {
  assert.deepEqual(
    db.topics([
      ["relief valve pressure", "main relief valve PC210"],
      ["relief valve D375", "CA234"],
      ["track roller removal"],
    ]),
    [
      { name: "Relief valve", n: 2 },
      { name: "Kode error", n: 1 },
      { name: "Main relief", n: 1 },
      { name: "Track roller", n: 1 },
      { name: "Valve pressure", n: 1 },
    ],
  );
});
