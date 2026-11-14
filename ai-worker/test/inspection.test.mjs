// Daily Inspection against a fake sheet (no Google needed).
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  addFindings,
  checkHealth,
  cleanDate,
  firstFreeRow,
  leaderNames,
  parseFindings,
  parsePop,
  popIndex,
  readAll,
  unitKey,
  wibStamp,
  writeAction,
} from "../src/inspection-sheet.ts";
import { SheetsError } from "../src/google.ts";

const TAB = "INSPECTION {SECTION} OPEN 2026";
const row = (no, kase, insp, leader, unit, model, hm, date, problem, action = "") =>
  [no, kase, insp, leader, unit, model, hm, date, problem, action, "NEXT SERVICE", action ? "CLOSE" : "OPEN", "", "", "", "TRACK"];
const empty = (no) => [no, "", "", "", "", "", "", "", "", "", "NEXT SERVICE", "", "", "", "", " "];

// Cells as the sheet's B..R columns of POP UNIT.
const pop = (code, model, section) => ["1", code, "", "", "", model, "", "", "", "", "", "", "", "", "", "", section];

/// A sheet held in memory: tabs of A1-addressed cells.
function fakeSheet() {
  const cells = new Map();
  const set = (tab, col, r, v) => cells.set(`${tab}!${col}${r}`, v);
  const colIdx = (c) => c.charCodeAt(0) - 65;
  const colName = (i) => String.fromCharCode(65 + i);
  const writes = [];
  const parse = (range) => {
    const m = /^'(.+)'!([A-Z])(\d+)(?::([A-Z])(\d+))?$/.exec(range);
    const tab = m[1].replace(/''/g, "'");
    return { tab, c0: colIdx(m[2]), r0: +m[3], c1: colIdx(m[4] ?? m[2]), r1: +(m[5] ?? m[3]) };
  };
  return {
    cells,
    writes,
    fail: null,
    load(tab, firstRow, firstCol, rows) {
      rows.forEach((r, i) => r.forEach((v, j) => set(tab, colName(colIdx(firstCol) + j), firstRow + i, v)));
    },
    async read(ranges) {
      if (this.fail) throw this.fail;
      return ranges.map((range) => {
        const { tab, c0, r0, c1, r1 } = parse(range);
        const out = [];
        for (let r = r0; r <= Math.min(r1, 400); r++) {
          const line = [];
          for (let c = c0; c <= c1; c++) line.push(cells.get(`${tab}!${colName(c)}${r}`) ?? "");
          out.push(line);
        }
        while (out.length && out[out.length - 1].every((v) => v === "")) out.pop();
        return out;
      });
    },
    async write(data) {
      if (this.fail) throw this.fail;
      for (const { range, values } of data) {
        writes.push(range);
        const { tab, c0, r0 } = parse(range);
        values.forEach((line, i) => line.forEach((v, j) => set(tab, colName(c0 + j), r0 + i, v)));
      }
    },
  };
}

function seeded() {
  const s = fakeSheet();
  const track = "INSPECTION TRACK OPEN 2026";
  s.load(track, 3, "T", [["12/11/2026 9:10:00"]]);
  s.load(track, 5, "B", [
    row("1", "1", "TAUFIK", "NOVAL", "D5143", "D155A-6R", "10615,0", "04/11/2026", "HOSE RETURN FUEL LEAKING"),
    row("2", "1", "TAUFIK", "SOFIYAN", "D5145", "D155A-6R", "9828,0", "01/11/2026", "REPLACE END BIT"),
    row("3", "1", "CAESAR HABIBI", "SOFYAN", "E5138", "PC210-10M0", "1200", "02/11/2026", "PIN BUCKET AUS", "DONE"),
    row("4", "1", "TAUFIK", "SOFYAN", "E5138", "PC210-10M0", "1200", "02/11/2026", "SEAL CYLINDER BOCOR"),
    row("5", "2", "TAUFIK", "E5138", "E5141", "PC210-10M0", "800", "03/11/2026", "LAMPU KERJA MATI"),
    row("6", "1", "TAUFIK", "EKO. W", "E5142", "PC210-10M0", "800", "03/11/2026", "AC KURANG DINGIN"),
    empty("7"),
    empty("8"),
  ]);
  s.load("INSPECTION WHEEL OPEN 2026", 3, "T", [["10/11/2026 8:00:00"]]);
  s.load("INSPECTION WHEEL OPEN 2026", 5, "B", [empty("1")]);
  s.load("INSPECTION SUPPORT OPEN 2026", 3, "T", [["10/11/2026 8:00:00"]]);
  s.load("POP UNIT AMM-SBS", 7, "C", [["CODE UNIT"]]);
  s.load("POP UNIT AMM-SBS", 8, "B", [
    [],
    ["EXCAVATOR PC210"],
    pop("E5138", "PC210-10M0", "TRACK"),
    pop("E5141", "PC210-10M0", "TRACK"),
    pop("E5142", "PC210-10M0", "TRACK"),
    pop("D5143", "D155A-6R", "TRACK"),
    pop("C577067", "777", "WHEEL"),
  ]);
  return s;
}

const ctx = (sheets) => ({ sheets, tab: TAB, now: Date.UTC(2026, 10, 14, 6, 5, 0) });

test("unit codes are compared without spaces, dots and dashes", () => {
  assert.equal(unitKey(" e-51.38 "), "E5138");
});

test("findings are the rows with a problem; status follows ACTION", async () => {
  const { tabs, pop: units } = await readAll(ctx(seeded()), ["TRACK"]);
  const t = tabs.TRACK;
  assert.equal(t.updated, "12/11/2026 9:10:00");
  assert.equal(t.rows.length, 6);
  assert.deepEqual(t.rows.map((r) => r.row), [5, 6, 7, 8, 9, 10]);
  assert.equal(t.rows[2].status, "CLOSE");
  assert.equal(t.rows[3].status, "OPEN");
  assert.equal(units.length, 5);
  assert.deepEqual(units[1], { unit: "E5141", model: "PC210-10M0", section: "TRACK" });
});

test("POP UNIT skips group title rows", () => {
  const units = parsePop([[], ["EXCAVATOR PC2000"], pop("E52027", "PC2000-11R", "TRACK")]);
  assert.deepEqual(units, [{ unit: "E52027", model: "PC2000-11R", section: "TRACK" }]);
});

test("leaders: first names, typos folded, unit codes skipped", async () => {
  const s = seeded();
  const [values, popRows] = await s.read(["'INSPECTION TRACK OPEN 2026'!B5:Q400", "'POP UNIT AMM-SBS'!B8:R400"]);
  const names = leaderNames(parseFindings(values), popIndex(parsePop(popRows)));
  assert.deepEqual(names, ["SOFYAN", "EKO", "NOVAL"]);
});

test("the first free row is the first without unit and problem", () => {
  assert.equal(firstFreeRow([row("1", "1", "A", "B", "E1", "M", "1", "01/01/2026", "X"), empty("2")]), 6);
  assert.equal(firstFreeRow([]), 5);
});

test("closing writes ACTION in uppercase and LAST UPDATE", async () => {
  const s = seeded();
  const r = await writeAction(ctx(s), { section: "TRACK", row: 8, unit: "E5138", problem: "seal cylinder bocor", action: "done replace" });
  assert.deepEqual(r, { row: 8, status: "CLOSE" });
  assert.equal(s.cells.get("INSPECTION TRACK OPEN 2026!K8"), "DONE REPLACE");
  assert.equal(s.cells.get("INSPECTION TRACK OPEN 2026!T3"), "14/11/2026 13:05:00");
});

test("an empty action opens the finding again (Urungkan)", async () => {
  const s = seeded();
  const r = await writeAction(ctx(s), { section: "TRACK", row: 7, unit: "E5138", problem: "PIN BUCKET AUS", action: "" });
  assert.equal(r.status, "OPEN");
  assert.equal(s.cells.get("INSPECTION TRACK OPEN 2026!K7"), "");
});

test("a finding that moved (sheet sorted) is found by unit and problem", async () => {
  const s = seeded();
  const r = await writeAction(ctx(s), { section: "TRACK", row: 5, unit: "E5142", problem: "AC KURANG DINGIN", action: "OK" });
  assert.equal(r.row, 10);
  assert.equal(s.cells.get("INSPECTION TRACK OPEN 2026!K10"), "OK");
  assert.equal(s.cells.get("INSPECTION TRACK OPEN 2026!K5") ?? "", "");
});

test("a finding that is gone is not written", async () => {
  const s = seeded();
  const r = await writeAction(ctx(s), { section: "TRACK", row: 5, unit: "E9999", problem: "X", action: "OK" });
  assert.equal(r.error, "moved");
  assert.equal(s.writes.length, 0);
});

test("text that looks like a formula stays text", async () => {
  const s = seeded();
  await writeAction(ctx(s), { section: "TRACK", row: 8, unit: "E5138", problem: "SEAL CYLINDER BOCOR", action: "=1+1" });
  assert.equal(s.cells.get("INSPECTION TRACK OPEN 2026!K8"), "'=1+1");
});

test("new findings go into the first free rows, one per problem", async () => {
  const s = seeded();
  const r = await addFindings(ctx(s), {
    section: "TRACK", unit: "e 5141", model: "", hm: "1234,5", date: "3/11/2026", leader: "noval",
    problems: ["hose ppc fatigue", " ", "baut cover hilang"], inspector: "ANAS",
  });
  assert.deepEqual(r, { rows: [11, 12] });
  const c = (a) => s.cells.get(`INSPECTION TRACK OPEN 2026!${a}`);
  assert.deepEqual(["B", "C", "D", "E", "F", "G", "H", "I", "J"].map((k) => c(`${k}11`)),
    ["=B10+1", "1", "ANAS", "NOVAL", "E5141", "PC210-10M0", "1234.5", "03/11/2026", "HOSE PPC FATIGUE"]);
  assert.equal(c("C12"), "2");
  assert.equal(c("J12"), "BAUT COVER HILANG");
  assert.equal(c("M11"), '=IF(J11="","",IF(K11="","OPEN","CLOSE"))');
  assert.equal(c("Q11"), `=IFERROR(VLOOKUP(F11,'POP UNIT AMM-SBS'!$C:$R,16,0)," ")`);
  assert.equal(c("L11"), "NEXT SERVICE", "REMARK is left alone");
});

test("a unit not in POP UNIT needs a model and gets the section as text", async () => {
  const s = seeded();
  const base = { section: "TRACK", unit: "E9001", hm: "10", date: "01/11/2026", leader: "NOVAL", problems: ["X"], inspector: "ANAS" };
  assert.equal((await addFindings(ctx(s), { ...base, model: "" })).error, "model");
  const r = await addFindings(ctx(s), { ...base, model: "pc210-11" });
  assert.deepEqual(r, { rows: [11] });
  assert.equal(s.cells.get("INSPECTION TRACK OPEN 2026!G11"), "PC210-11");
  assert.equal(s.cells.get("INSPECTION TRACK OPEN 2026!Q11"), "TRACK");
});

test("a unit of another section is refused", async () => {
  const s = seeded();
  const r = await addFindings(ctx(s), {
    section: "TRACK", unit: "C577067", model: "", hm: "10", date: "01/11/2026", leader: "NOVAL", problems: ["X"], inspector: "ANAS",
  });
  assert.equal(r.error, "other_section");
  assert.match(r.message, /WHEEL/);
});

test("incomplete forms are refused", async () => {
  const s = seeded();
  const r = await addFindings(ctx(s), {
    section: "TRACK", unit: "E5141", model: "", hm: "abc", date: "01/11/2026", leader: "NOVAL", problems: ["X"], inspector: "ANAS",
  });
  assert.equal(r.error, "bad_request");
  assert.equal(cleanDate("31/13/2026"), null);
  assert.equal(cleanDate("1/2/2026"), "01/02/2026");
});

test("WIB stamp", () => {
  assert.equal(wibStamp(Date.UTC(2026, 10, 14, 20, 0, 9)), "15/11/2026 3:00:09");
});

test("health check records lost access", async () => {
  const s = seeded();
  const store = new Map();
  const kv = { put: async (k, v) => store.set(k, v) };
  assert.equal((await checkHealth({ ...ctx(s), kv })).ok, true);
  s.fail = new SheetsError(403, "The caller does not have permission");
  const h = await checkHealth({ ...ctx(s), kv });
  assert.equal(h.ok, false);
  assert.match(h.message, /editor/);
  assert.equal(JSON.parse(store.get("inspection:health")).ok, false);
});
