import { test } from "node:test";
import assert from "node:assert/strict";
import { daysUntilNext } from "../src/quiz-rules.ts";

test("level 0 (baru salah) diulang besok", () => {
  assert.equal(daysUntilNext(0), 1);
});
// Tulis sendiri 3 tes lagi dengan pola yang sama:
// level 1 → 3 hari, level 6 → 90 hari, level 9 → tetap 90 hari
