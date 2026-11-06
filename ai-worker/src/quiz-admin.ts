// The Quiz's admin endpoints: nyel AI drafts questions from the manuals, an
// admin checks and approves them before mechanics see them (Anas's
// decision in the Quiz PRD). All need an active admin's session.
//
//   POST /admin/quiz/generate           {section, unit, topic, manual_id, page, text, count, kind}
//                                       one page -> drafts (kind: campur | pg | bs | gambar)
//   POST /admin/quiz/plan               {unit, topic, toc, pages, count, mix} -> pages to use
//   POST /admin/quiz/job                {section, unit, manual_id, title, topic, count, mix, pages}
//                                       -> a "Buat draf kuis" job, run by the cron (quiz-jobs.ts)
//   POST /admin/quiz/jobs               recent jobs with their progress
//   POST /admin/quiz/approve            {ids} -> publishes those that passed the curator
//   PUT  /admin/quiz/image/<id>         PNG body: the picture of a "gambar" question
//   POST /admin/quiz/questions          {status, unit?} -> list (draf, terbit, ditarik, ...)
//   POST /admin/quiz/add                an admin's own question {..., publish?}
//   POST /admin/quiz/question/<id>      {action: setujui|ubah|tolak|tarik, question?}
//   POST /admin/quiz/reports            open "Soal salah" reports
//   POST /admin/quiz/leaderboard/hide   {nrp, hidden}
//
// Page text comes from the admin's phone, which already has every manual's
// search index; the server checks that the numbers in the right answer are
// on that page and writes what it found in check_note.

import { requireAdmin } from "./auth";
import { askWith, curate, planPages, selfCheck, wantedFor, writeQuestions, MAX_PAGE_TEXT } from "./quiz-ai.ts";
import * as quiz from "./quiz-db.ts";
import { createJob, listJobs, mixFrom, MAX_JOB_PAGES, MAX_JOB_QUESTIONS, PASS_SCORE, targets, type JobPage } from "./quiz-jobs.ts";
import { questionProblem, STATUSES, TOPICS, type QuestionInput } from "./quiz-rules.ts";
import { json, readBody, type QuizEnv } from "./quiz.ts";

export type { AiEnv } from "./quiz-ai.ts";

const MAX_DRAFTS = 5;
const MAX_IMAGE = 2_000_000;

/// A question from a request body; null when a field is missing.
function questionFrom(b: Record<string, unknown>): (QuestionInput & { image: string | null }) | null {
  if (!Array.isArray(b.choices)) return null;
  return {
    section: String(b.section ?? "").trim().toUpperCase(),
    unit: String(b.unit ?? "").trim() || null,
    topic: String(b.topic ?? "").trim(),
    type: String(b.type ?? "pg").trim(),
    prompt: String(b.prompt ?? ""),
    choices: b.choices.map((c) => String(c ?? "")),
    answer: Number(b.answer),
    explain: String(b.explain ?? ""),
    manual_id: String(b.manual_id ?? ""),
    page: Number(b.page),
    image: null,
  };
}

/// Manual: questions from the one page the admin has open, checked by the
/// curator and the server, saved as drafts.
async function generate(env: QuizEnv, b: Record<string, unknown>, by: string): Promise<Response> {
  const base = questionFrom({ ...b, choices: ["a", "b"], answer: 0, prompt: "x", explain: "x" });
  const text = String(b.text ?? "").slice(0, MAX_PAGE_TEXT);
  const count = Math.min(Math.max(Number(b.count) || 3, 1), MAX_DRAFTS);
  const problem = base && questionProblem(base);
  if (!base || problem) return json({ error: "bad_request", message: problem ?? "Data soal tidak lengkap." }, 400);
  if (text.trim().length < 80) return json({ error: "bad_request", message: "Teks halaman terlalu pendek untuk dibuat soal." }, 400);
  const kind = ["pg", "bs", "gambar"].includes(String(b.kind)) ? String(b.kind) : "campur";

  const ask = askWith(env);
  const { image: _image, type: _type, prompt: _p, choices: _c, answer: _a, explain: _e, ...where } = base;
  const out = await writeQuestions(ask, where, text, wantedFor(kind, count));
  if (!out) return json({ error: "upstream", message: "nyel AI belum bisa membuat soal sekarang. Coba lagi nanti." }, 502);
  const reviewed = await curate(ask, out.drafts, text);

  const db = quiz.d1(env.QUIZ);
  const saved: { id: string; type: string }[] = [];
  for (const q of reviewed.kept) {
    const check = selfCheck(q, text);
    const id = await quiz.addQuestion(db, q, {
      status: "draf",
      source: "ai",
      by,
      check_note: check.note,
      curator_score: q.score,
      curator_note: q.note,
      passed: check.ok && q.score !== null && q.score >= PASS_SCORE,
    });
    saved.push({ id, type: q.type });
  }
  return json({
    ok: true,
    saved: saved.length,
    ids: saved.map((s) => s.id),
    pictures: saved.filter((s) => s.type === "gambar").map((s) => s.id),
    skipped: out.skipped,
    dropped: reviewed.dropped,
  });
}

/// "Buat draf kuis", step 1: pages to use, chosen from the table of contents.
async function plan(env: QuizEnv, b: Record<string, unknown>): Promise<Response> {
  const toc = String(b.toc ?? "");
  const pages = Math.round(Number(b.pages) || 0);
  const count = Math.max(1, Math.min(MAX_JOB_QUESTIONS, Math.round(Number(b.count) || 20)));
  const topic = TOPICS.includes(String(b.topic)) ? String(b.topic) : "semua";
  if (toc.trim().length < 20 || pages < 1) {
    return json({ error: "bad_request", message: "File ini tidak punya daftar isi (bookmark), jadi halaman tidak bisa dipilih otomatis." }, 400);
  }
  const mix = mixFrom(b.mix);
  // About 2-3 kept questions per page; a few spare pages for the curator.
  const want = Math.min(MAX_JOB_PAGES, Math.ceil(count / 2.5) + 3);
  const chosen = await planPages(askWith(env), toc, pages, want, topic, targets(count, mix, true).gambar > 0);
  if (!chosen) return json({ error: "upstream", message: "nyel AI belum bisa memilih halaman sekarang. Coba lagi nanti." }, 502);
  if (!chosen.length) return json({ error: "empty", message: "nyel AI tidak menemukan halaman yang cocok di daftar isi file ini." }, 404);
  return json({ pages: chosen });
}

/// "Buat draf kuis", step 2: the pages with their text; the cron does the rest.
async function startJob(env: QuizEnv, b: Record<string, unknown>, by: string): Promise<Response> {
  const section = String(b.section ?? "").trim().toUpperCase();
  const manualId = String(b.manual_id ?? "").trim();
  const raw = Array.isArray(b.pages) ? (b.pages as Record<string, unknown>[]) : [];
  const pages: JobPage[] = raw.map((p) => ({
    page: Math.round(Number(p.page)),
    kind: p.kind === "gambar" ? "gambar" : "teks",
    topic: String(p.topic ?? "struktur"),
    text: String(p.text ?? ""),
  }));
  const usable = pages.filter((p) => p.page >= 1 && p.text.trim().length >= 80);
  if (!section || !manualId) return json({ error: "bad_request", message: "Data file tidak lengkap." }, 400);
  if (!usable.length) return json({ error: "bad_request", message: "Halaman yang dipilih tidak punya teks (mungkin hasil scan)." }, 400);
  const id = await createJob(
    quiz.d1(env.QUIZ),
    {
      section,
      unit: String(b.unit ?? "").trim() || null,
      manual_id: manualId,
      title: String(b.title ?? manualId).slice(0, 120),
      topic: TOPICS.includes(String(b.topic)) ? String(b.topic) : "semua",
      count: Number(b.count) || 20,
      mix: mixFrom(b.mix),
      pages: usable,
    },
    by,
  );
  return json({ ok: true, id, pages: usable.length });
}

/// The picture of a "gambar" question, made on the admin's phone: the
/// manual page with its words covered, so the legend does not give the
/// answer away. Kept in the bucket next to the manuals.
async function putImage(request: Request, env: QuizEnv, id: string): Promise<Response> {
  const bytes = new Uint8Array(await request.arrayBuffer());
  const png = bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  if (!png || bytes.length > MAX_IMAGE) return json({ error: "bad_request", message: "Gambar harus PNG, maksimal 2 MB." }, 400);
  const key = `quiz/img/${id}-${Date.now().toString(36)}.png`;
  await env.BUCKET.put(key, bytes, { httpMetadata: { contentType: "image/png" } });
  const ok = await quiz.setImage(quiz.d1(env.QUIZ), id, key);
  if (!ok) {
    await env.BUCKET.delete(key);
    return json({ error: "not_found", message: "Soal tidak ditemukan." }, 404);
  }
  return json({ ok: true, image: key });
}

/// Handles /admin/quiz/*.
export async function handleQuizAdmin(request: Request, env: QuizEnv, path: string): Promise<Response> {
  if (request.method !== "POST" && request.method !== "GET" && request.method !== "PUT") return json({ error: "method" }, 405);
  const auth = await requireAdmin(env, request);
  if (auth.error) return auth.error;
  const by = auth.session.n;
  if (path.startsWith("/admin/quiz/image/")) {
    if (request.method !== "PUT") return json({ error: "method" }, 405);
    return putImage(request, env, decodeURIComponent(path.slice("/admin/quiz/image/".length)));
  }
  const b = await readBody(request);
  if (!b) return json({ error: "bad_request" }, 400);
  const db = quiz.d1(env.QUIZ);

  if (path === "/admin/quiz/generate") return generate(env, b, by);
  if (path === "/admin/quiz/plan") return plan(env, b);
  if (path === "/admin/quiz/job") return startJob(env, b, by);
  if (path === "/admin/quiz/jobs") return json({ jobs: await listJobs(db) });
  if (path === "/admin/quiz/approve") {
    const ids = Array.isArray(b.ids) ? b.ids.map(String) : [];
    return json({ ok: true, ...(await quiz.approvePassed(db, ids, by)) });
  }
  if (path === "/admin/quiz/questions") {
    const status = String(b.status ?? "draf");
    if (!STATUSES.includes(status)) return json({ error: "bad_request" }, 400);
    return json({ questions: await quiz.listQuestions(db, status, String(b.unit ?? "").trim() || null), topics: TOPICS });
  }
  if (path === "/admin/quiz/add") {
    const q = questionFrom(b);
    const problem = q ? questionProblem(q) : "Data soal tidak lengkap.";
    if (!q || problem) return json({ error: "bad_request", message: problem }, 400);
    const id = await quiz.addQuestion(db, q, { status: b.publish === true ? "terbit" : "draf", source: "admin", by });
    return json({ ok: true, id });
  }
  if (path.startsWith("/admin/quiz/question/")) {
    const id = decodeURIComponent(path.slice("/admin/quiz/question/".length));
    const action = String(b.action ?? "");
    if (!["setujui", "ubah", "tolak", "tarik"].includes(action)) return json({ error: "bad_request" }, 400);
    let edit = null;
    if (b.question && typeof b.question === "object") {
      edit = questionFrom(b.question as Record<string, unknown>);
      const problem = edit ? questionProblem(edit) : "Data soal tidak lengkap.";
      if (!edit || problem) return json({ error: "bad_request", message: problem }, 400);
    } else if (action === "ubah") {
      return json({ error: "bad_request", message: "Tidak ada perubahan." }, 400);
    }
    const ok = await quiz.decide(db, id, action as "setujui" | "ubah" | "tolak" | "tarik", by, edit);
    return ok ? json({ ok: true }) : json({ error: "not_found", message: "Soal tidak ditemukan." }, 404);
  }
  if (path === "/admin/quiz/reports") return json({ reports: await quiz.openReports(db) });
  if (path === "/admin/quiz/leaderboard/hide") {
    const ok = await quiz.hideFromBoard(db, String(b.nrp ?? "").trim(), b.hidden === true);
    return ok ? json({ ok: true }) : json({ error: "not_found", message: "NRP ini belum pernah ikut quiz." }, 404);
  }
  return json({ error: "not_found" }, 404);
}
