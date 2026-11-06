// The Quiz's admin endpoints: nyel AI drafts questions from a manual page,
// an admin checks and approves them before mechanics see them (Anas's
// decision in the Quiz PRD). All need an active admin's session.
//
//   POST /admin/quiz/generate           {section, unit, topic, manual_id, page, text, count}
//                                       -> drafts saved with status "draf"
//   POST /admin/quiz/questions          {status, unit?} -> list (draf, terbit, ditarik, ...)
//   POST /admin/quiz/add                an admin's own question {..., publish?}
//   POST /admin/quiz/question/<id>      {action: setujui|ubah|tolak|tarik, question?}
//   POST /admin/quiz/reports            open "Soal salah" reports
//   POST /admin/quiz/leaderboard/hide   {nrp, hidden}
//
// The page text comes from the admin's phone, which already has every
// manual's search index; the server checks that the numbers in the right
// answer are on that page and writes what it found in check_note.

import { requireAdmin, type AuthEnv } from "./auth";
import * as quiz from "./quiz-db.ts";
import { numbersMissing, questionProblem, STATUSES, TOPICS, type QuestionInput } from "./quiz-rules.ts";
import { json, readBody, type QuizEnv } from "./quiz.ts";

/// The AI settings the Worker already has (wrangler.toml, secrets).
export interface AiEnv extends AuthEnv {
  DEEPSEEK_API_KEY?: string;
  GROQ_API_KEY?: string;
  MODEL: string;
  API_URL: string;
}

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
const MAX_DRAFTS = 5;
const MAX_PAGE_TEXT = 12_000;

const TOPIC_NAMES: Record<string, string> = {
  struktur: "structure and function",
  torsi: "tightening torque",
  kapasitas: "oil and fluid capacities",
  standar: "standard values and pressures",
  fault: "failure codes and troubleshooting",
  servis: "periodic maintenance (service hours)",
  sistem: "systems (hydraulic, electrical, power train)",
};

const GENERATE_PROMPT = `You write quiz questions for heavy-equipment mechanics, from one page of a Komatsu or Caterpillar technical manual. Each question checks one fact that a mechanic should remember on the job: a value with its unit and condition, the function of a component, the order of a procedure, what a failure code means, a service interval.

Rules:
- Use only what the page says. Every fact in the question, the right answer and the explanation must be on the page. Never use outside knowledge for the answer.
- Write in Bahasa Indonesia, keeping technical terms, part names, codes and values exactly as the page writes them (in English when the page is English).
- Type "pg": 4 choices, exactly one right. The wrong choices must be believable (near values, related parts), never silly. Type "bs": choices ["Benar", "Salah"].
- The question must be answerable without seeing the page; name the unit and the component.
- explain: one or two sentences saying why the right answer is right, as the page says it.
- Different questions must check different facts.

Reply with JSON only: {"questions": [{"type": "pg", "prompt": "...", "choices": ["...", "...", "...", "..."], "answer": 0, "explain": "..."}]} where answer is the index of the right choice (0 = first).`;

type Draft = { type?: unknown; prompt?: unknown; choices?: unknown; answer?: unknown; explain?: unknown };

/// Asks the models in MODEL in order (like nyel AI) for drafts; the first
/// one that answers with JSON wins.
async function askModels(env: AiEnv, user: string): Promise<Draft[] | null> {
  for (const entry of env.MODEL.split(",").map((m) => m.trim()).filter(Boolean)) {
    const deepseek = entry.startsWith("deepseek:");
    const model = deepseek ? entry.slice("deepseek:".length) : entry;
    const key = deepseek ? env.DEEPSEEK_API_KEY : env.GROQ_API_KEY;
    if (!key) continue;
    try {
      const response = await fetch(deepseek ? DEEPSEEK_URL : env.API_URL, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
        body: JSON.stringify({
          model,
          messages: [
            { role: "system", content: GENERATE_PROMPT },
            { role: "user", content: user },
          ],
          temperature: 0.4,
          max_tokens: 3000,
          response_format: { type: "json_object" },
          ...(deepseek ? { thinking: { type: "disabled" } } : {}),
          ...(model.startsWith("openai/gpt-oss") ? { reasoning_effort: "low" } : {}),
        }),
        signal: AbortSignal.timeout(60_000),
      });
      if (!response.ok) {
        console.log("quiz generate: model failed", entry, response.status);
        continue;
      }
      const data = (await response.json()) as { choices?: { message?: { content?: string } }[] };
      const text = data.choices?.[0]?.message?.content ?? "";
      const parsed = JSON.parse(text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1)) as { questions?: Draft[] };
      if (Array.isArray(parsed.questions)) return parsed.questions;
    } catch (e) {
      console.log("quiz generate: model error", entry, String(e));
    }
  }
  return null;
}

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
    image: String(b.image ?? "").trim() || null,
  };
}

async function generate(env: QuizEnv, b: Record<string, unknown>, by: string): Promise<Response> {
  const base = questionFrom({ ...b, choices: ["a", "b"], answer: 0, prompt: "x", explain: "x" });
  const text = String(b.text ?? "").slice(0, MAX_PAGE_TEXT);
  const count = Math.min(Math.max(Number(b.count) || 3, 1), MAX_DRAFTS);
  const problem = base && questionProblem(base);
  if (!base || problem) return json({ error: "bad_request", message: problem ?? "Data soal tidak lengkap." }, 400);
  if (text.trim().length < 80) return json({ error: "bad_request", message: "Teks halaman terlalu pendek untuk dibuat soal." }, 400);

  const drafts = await askModels(
    env,
    `Unit: ${base.unit ?? "umum (semua unit)"}\nTopic: ${TOPIC_NAMES[base.topic] ?? base.topic}\nWrite ${count} questions.\n\nManual page ${base.page}:\n${text}`,
  );
  if (!drafts) return json({ error: "upstream", message: "nyel AI belum bisa membuat soal sekarang. Coba lagi nanti." }, 502);

  const db = quiz.d1(env.QUIZ);
  const saved: string[] = [];
  const skipped: string[] = [];
  for (const d of drafts.slice(0, count)) {
    const q = { ...base, type: String(d.type ?? "pg"), prompt: String(d.prompt ?? ""), choices: Array.isArray(d.choices) ? d.choices.map(String) : [], answer: Number(d.answer), explain: String(d.explain ?? "") };
    if (q.type === "bs") q.choices = ["Benar", "Salah"];
    const bad = questionProblem(q);
    if (bad) {
      skipped.push(bad);
      continue;
    }
    const missing = numbersMissing(q.choices[q.answer], text);
    const note = missing.length
      ? `Cek angka: ${missing.join(", ")} tidak ditemukan di halaman ${q.page}.`
      : "Angka di jawaban ada di halaman sumber.";
    saved.push(await quiz.addQuestion(db, q, { status: "draf", source: "ai", by, check_note: note }));
  }
  return json({ ok: true, saved: saved.length, ids: saved, skipped });
}

/// Handles /admin/quiz/*.
export async function handleQuizAdmin(request: Request, env: QuizEnv, path: string): Promise<Response> {
  if (request.method !== "POST" && request.method !== "GET") return json({ error: "method" }, 405);
  const auth = await requireAdmin(env, request);
  if (auth.error) return auth.error;
  const by = auth.session.n;
  const b = await readBody(request);
  if (!b) return json({ error: "bad_request" }, 400);
  const db = quiz.d1(env.QUIZ);

  if (path === "/admin/quiz/generate") return generate(env, b, by);
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
