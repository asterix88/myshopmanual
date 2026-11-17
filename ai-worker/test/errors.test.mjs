// Automatic error reports (src/error-groups.ts): cleaning a phone's list and
// grouping reports for the admin screen.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanItems, groupReports, signature } from "../src/error-groups.ts";

const now = 1_800_000_000_000;

test("cleanItems keeps sensible items and drops the rest", () => {
  const items = cleanItems(
    [
      { kind: "CRASH_NATIVE", message: "Aplikasi tertutup paksa", stack: "log", count: 2, first: now - 50, last: now - 10 },
      { kind: "error", message: "   " }, // empty message
      "rubbish",
      { message: "x".repeat(900), count: -4, last: now + 999_999 }, // clock in the future
    ],
    now,
  );
  assert.equal(items.length, 2);
  assert.deepEqual(items[0], {
    kind: "CRASH_NATIVE", message: "Aplikasi tertutup paksa", stack: "log", count: 2, first: now - 50, last: now - 10,
  });
  assert.equal(items[1].kind, "error");
  assert.equal(items[1].message.length, 500);
  assert.equal(items[1].count, 1);
  assert.equal(items[1].last, now);
  assert.deepEqual(cleanItems("not a list"), []);
  assert.equal(cleanItems(Array.from({ length: 50 }, () => ({ message: "a" }))).length, 20);
});

test("signature ignores numbers and spacing", () => {
  assert.equal(signature("error", "RangeError: index 12 out of 30"), signature("error", "RangeError:  index 7 out of 9"));
  assert.notEqual(signature("error", "x"), signature("ANR", "x"));
});

test("groupReports joins the same problem from several phones", () => {
  const item = (message, count, last, kind = "error") => ({ kind, message, stack: `at ${message}`, count, first: last - 5, last });
  const groups = groupReports([
    { at: now, nrp: "A1", name: "Ali", app: "1.1.215", model: "Samsung A15", items: [item("Bad state: page 3", 2, now - 100)] },
    { at: now, nrp: "B2", name: "Budi", app: "1.1.214", model: "Redmi 12", items: [item("Bad state: page 9", 1, now - 50), item("ANR", 1, now - 500, "ANR")] },
    { at: now, nrp: "A1", name: "Ali", app: "1.1.215", model: "Samsung A15", items: [item("Bad state: page 3", 1, now - 10)] },
  ]);
  assert.equal(groups.length, 2);
  const [bad, anr] = groups;
  assert.equal(bad.count, 4);
  assert.equal(bad.phones, 2);
  assert.deepEqual(bad.people, ["Ali (A1)", "Budi (B2)"]);
  assert.deepEqual(bad.apps, ["1.1.215", "1.1.214"]);
  assert.equal(bad.last, now - 10);
  assert.equal(bad.message, "Bad state: page 3");
  assert.equal(anr.kind, "ANR");
  assert.equal(anr.phones, 1);
});
