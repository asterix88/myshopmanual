// node --experimental-strip-types --test test/  (no Cloudflare needed)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readProgress, readSummaryRequest, readTutor, summaryPrompt, tutorInstructions } from "../src/tutor.ts";

test("the normal mode sends no tutor settings", () => {
  assert.equal(readTutor(undefined), null);
  assert.equal(readTutor("belajar"), null);
});

test("tutor settings: kind defaults to question, summary is trimmed", () => {
  assert.deepEqual(readTutor({}), { kind: "question", summary: "" });
  assert.deepEqual(readTutor({ kind: "hint", summary: "  Topik: oli panas.  " }), { kind: "hint", summary: "Topik: oli panas." });
  assert.equal(readTutor({ kind: "hapus semua" }).kind, "question");
});

test("hint and explain add their own instructions, and the summary rides along", () => {
  const hint = tutorInstructions({ kind: "hint", summary: "Topik: oli panas PC210." });
  assert.match(hint, /pressed Petunjuk/);
  assert.match(hint, /Topik: oli panas PC210\./);
  assert.doesNotMatch(tutorInstructions({ kind: "question", summary: "" }), /Petunjuk|accepted your offer|Summary/);
  assert.match(tutorInstructions({ kind: "explain", summary: "" }), /accepted your offer/);
});

test("the hidden progress line is cut out and returned", () => {
  assert.deepEqual(readProgress("Benar.\n\nApa fungsi oil cooler?\n[kemajuan: ya]"), {
    content: "Benar.\n\nApa fungsi oil cooler?",
    progress: true,
  });
  assert.equal(readProgress("Coba lihat lagi?\n[ Kemajuan : TIDAK ]").progress, false);
  assert.deepEqual(readProgress("Tanpa penanda?"), { content: "Tanpa penanda?", progress: null });
  assert.deepEqual(readProgress(null), { content: null, progress: null });
});

test("a summary request keeps only text messages, the newest ones", () => {
  assert.equal(readSummaryRequest({ messages: [] }), null);
  assert.equal(readSummaryRequest({ summary: "x" }), null);
  const many = Array.from({ length: 30 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: `pesan ${i}` }));
  const request = readSummaryRequest({
    summary: "Lama",
    messages: [{ role: "tool", content: "hasil" }, { role: "user", content: "  " }, ...many],
  });
  assert.equal(request.summary, "Lama");
  assert.equal(request.messages.length, 20);
  assert.equal(request.messages.at(-1).content, "pesan 29");
  const prompt = summaryPrompt(request);
  assert.equal(prompt[0].role, "system");
  assert.match(prompt[1].content, /Previous summary:\nLama/);
  assert.match(prompt[1].content, /Tutor: pesan 29/);
});
