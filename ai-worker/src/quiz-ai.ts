// nyel AI's work for the Quiz: choosing pages of a manual, writing questions
// from one page, and checking them as a second pair of eyes (the curator).
// The calls go to the models in MODEL in order, like nyel AI: DeepSeek
// first, Groq when DeepSeek is busy. Every function takes the "ask"
// function, so the tests run them without the network.

import { numbersMissing, questionProblem, type QuestionInput } from "./quiz-rules.ts";

/// The AI settings the Worker already has (wrangler.toml, secrets).
export interface AiEnv {
  DEEPSEEK_API_KEY?: string;
  GROQ_API_KEY?: string;
  MODEL: string;
  API_URL: string;
}

/// Sends a system and a user message, returns the JSON object the model
/// answered, or null when no model answered with JSON.
export type Ask = (system: string, user: string, maxTokens?: number) => Promise<Record<string, unknown> | null>;

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
export const MAX_PAGE_TEXT = 12_000;

export const TOPIC_NAMES: Record<string, string> = {
  struktur: "structure and function",
  torsi: "tightening torque",
  kapasitas: "oil and fluid capacities",
  standar: "standard values and pressures",
  fault: "failure codes and troubleshooting",
  servis: "periodic maintenance (service hours)",
  sistem: "systems (hydraulic, electrical, power train)",
};

export function askWith(env: AiEnv): Ask {
  return async (system, user, maxTokens = 3000) => {
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
              { role: "system", content: system },
              { role: "user", content: user },
            ],
            temperature: 0.4,
            max_tokens: maxTokens,
            response_format: { type: "json_object" },
            ...(deepseek ? { thinking: { type: "disabled" } } : {}),
            ...(model.startsWith("openai/gpt-oss") ? { reasoning_effort: "low" } : {}),
          }),
          signal: AbortSignal.timeout(90_000),
        });
        if (!response.ok) {
          console.log("quiz ai: model failed", entry, response.status);
          continue;
        }
        const data = (await response.json()) as { choices?: { message?: { content?: string } }[] };
        const text = data.choices?.[0]?.message?.content ?? "";
        const parsed = JSON.parse(text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1));
        if (parsed && typeof parsed === "object") return parsed as Record<string, unknown>;
      } catch (e) {
        console.log("quiz ai: model error", entry, String(e));
      }
    }
    return null;
  };
}

// ---- Writing questions from one page ----

const WRITE_PROMPT = `You write quiz questions for heavy-equipment mechanics, from one page of a Komatsu or Caterpillar technical manual. Each question checks one fact that a mechanic should remember on the job: a value with its unit and condition, the function of a component, the order of a procedure, what a failure code means, a service interval.

Rules:
- Use only what the page says. Every fact in the question, the right answer and the explanation must be on the page. Never use outside knowledge for the answer.
- Write in Bahasa Indonesia, keeping technical terms, part names, codes and values exactly as the page writes them (in English when the page is English).
- Type "pg": 4 choices, exactly one right. The wrong choices must be believable (near values, related parts), never silly.
- Type "bs": a statement; choices ["Benar", "Salah"]. Make about half of them false by changing one value or part name.
- Type "gambar", numbered drawing: a drawing page whose text has a numbered legend (lines like "3. Main relief valve"). The mechanic sees the drawing with its numbers but WITHOUT the legend. Ask what one numbered part is ("Pada gambar <name of the drawing>, komponen nomor 3 adalah?"); 4 choices taken from the same legend, exactly one right; put the number in the field "callout".
- Type "gambar", labelled photo or drawing: a page whose text is mostly short part names placed on a photo or drawing (like "PSV", "TVC valve", "Servo valve", each a label on the picture, few or no sentences). The mechanic sees the picture with every label hidden and replaced by a letter. Ask what one label is, writing [X] where its letter goes ("Pada foto <what the picture shows, with the unit>, komponen bertanda [X] adalah?"); 4 choices taken from the labels on the same page, written exactly as the page writes them, exactly one right; put the right label, exactly as on the page, in the field "callout".
- When the page is such a labelled picture, write only "gambar" questions, whatever types were asked, each about a different label. If a page has neither a numbered legend nor labels, write "pg" instead of "gambar".
- The question must be answerable without seeing the page (except "gambar"); name the unit and the component.
- Types "pg" and "bs" are shown WITHOUT any picture. In them never write callout numbers such as "(35)" or "nomor 3", and never refer to a drawing ("gambar", "ilustrasi", "illustration"); name each part by its name only. A fact that needs the drawing belongs in a "gambar" question or nowhere.
- explain: one or two short sentences giving the fact itself, as the page says it. Start with the fact; never start with "Halaman menyatakan", "Menurut manual" or similar.
- Different questions must check different facts.

Reply with JSON only: {"questions": [{"type": "pg", "prompt": "...", "choices": ["...", "...", "...", "..."], "answer": 0, "explain": "...", "callout": null}]} where answer is the index of the right choice (0 = first).`;

export type Wanted = { pg: number; bs: number; gambar: number };

export type Draft = QuestionInput & { callout?: string | null };

/// How many of each type to ask for on one page chosen by the admin.
export function wantedFor(kind: string, count: number): Wanted {
  switch (kind) {
    case "pg":
      return { pg: count, bs: 0, gambar: 0 };
    case "bs":
      return { pg: 0, bs: count, gambar: 0 };
    case "gambar":
      return { pg: 0, bs: 0, gambar: count };
    default: {
      const bs = count >= 3 ? 1 : 0;
      return { pg: count - bs, bs, gambar: 0 };
    }
  }
}

/// Asks for questions from one page. [wanted] says how many of each type.
export async function writeQuestions(
  ask: Ask,
  base: Omit<QuestionInput, "type" | "prompt" | "choices" | "answer" | "explain">,
  text: string,
  wanted: Wanted,
): Promise<{ drafts: Draft[]; skipped: string[] } | null> {
  const total = wanted.pg + wanted.bs + wanted.gambar;
  const parts = [
    wanted.pg ? `${wanted.pg} of type "pg"` : "",
    wanted.bs ? `${wanted.bs} of type "bs"` : "",
    wanted.gambar ? `${wanted.gambar} of type "gambar"` : "",
  ].filter(Boolean);
  const reply = await ask(
    WRITE_PROMPT,
    `Unit: ${base.unit ?? "umum (semua unit)"}\nTopic: ${TOPIC_NAMES[base.topic] ?? base.topic}\nWrite ${total} questions: ${parts.join(", ")}.\n\nManual page ${base.page}:\n${text.slice(0, MAX_PAGE_TEXT)}`,
  );
  if (!reply || !Array.isArray(reply.questions)) return null;
  const drafts: Draft[] = [];
  const skipped: string[] = [];
  for (const raw of reply.questions.slice(0, total + 2) as Record<string, unknown>[]) {
    const q: Draft = {
      ...base,
      type: String(raw.type ?? "pg"),
      prompt: String(raw.prompt ?? ""),
      choices: Array.isArray(raw.choices) ? raw.choices.map(String) : [],
      answer: Number(raw.answer),
      explain: cleanExplain(String(raw.explain ?? "")),
      callout: raw.callout == null ? null : String(raw.callout),
    };
    if (q.type === "bs") q.choices = ["Benar", "Salah"];
    stripCallouts(q);
    const bad = questionProblem(q);
    if (bad) skipped.push(bad);
    else drafts.push(q);
  }
  return { drafts, skipped };
}

/// What the server can check by itself: numbers in the right answer must be
/// on the page; for a picture question, its number and the part's name too.
export function selfCheck(q: Draft, text: string): { ok: boolean; note: string } {
  if (q.type === "gambar") {
    const name = q.choices[q.answer] ?? "";
    const number = String(q.callout ?? "").trim();
    const flat = text.toLowerCase().replace(/\s+/g, " ");
    const hasName = name.trim().length > 0 && flat.includes(name.toLowerCase().replace(/\s+/g, " ").trim());
    if (q.prompt.includes("[X]")) {
      // A labelled photo: the asked label is the right choice itself.
      return hasName
        ? { ok: true, note: `Label "${name}" ada di halaman ${q.page}.` }
        : { ok: false, note: `Cek gambar: label "${name}" tidak ditemukan di halaman ${q.page}.` };
    }
    const hasNumber = number !== "" && new RegExp(`(^|\\D)${number.replace(/\D/g, "")}(\\D|$)`).test(text);
    if (hasName && hasNumber) return { ok: true, note: `Nomor ${number} dan nama komponen ada di halaman ${q.page}.` };
    return { ok: false, note: `Cek gambar: ${hasNumber ? "" : `nomor ${number || "?"} `}${hasName ? "" : `"${name}" `}tidak ditemukan di keterangan halaman ${q.page}.`.replace("  ", " ") };
  }
  if (PICTURE_WORDS.test(q.prompt)) return { ok: false, note: "Soal menyebut gambar, padahal soal ini tampil tanpa gambar." };
  const missing = numbersMissing(q.choices[q.answer] ?? "", text);
  return missing.length
    ? { ok: false, note: `Cek angka: ${missing.join(", ")} tidak ditemukan di halaman ${q.page}.` }
    : { ok: true, note: "Angka di jawaban ada di halaman sumber." };
}

// ---- The curator ----

const CURATE_PROMPT = `You are a senior heavy-equipment instructor checking quiz questions that another writer made from one manual page, before they are given to mechanics. Judge each question against the page text only.

For each question give a score from 1 to 10:
- 9-10: right answer is clearly stated on the page, question is clear, wrong choices are believable but clearly wrong, useful on the job.
- 7-8: good, small wording issues.
- 4-6: unclear, ambiguous (e.g. the value depends on a condition the question does not name), or wrong choices too easy.
- 1-3: the key is wrong or not on the page, or two choices could be right.
- Type "gambar" on a labelled photo: the mechanic sees the picture with every label replaced by a letter, and [X] in the question becomes the asked label's letter. Judge it by the labels on the page; the right answer is the asked label itself.
- Types "pg" and "bs" are shown without the drawing: one that mentions callout numbers like "(35)" or refers to a picture must be "perbaiki" (rewrite without them) or "buang" when it cannot be answered without the drawing.

verdict: "lolos" (score 7+), "perbaiki" (you can fix it: give the whole fixed question in "fixed", same JSON shape, and score the fixed version), or "buang".
note: one short sentence in Bahasa Indonesia for the admin, saying what is good or what to check.

Reply with JSON only: {"reviews": [{"i": 0, "score": 8, "verdict": "lolos", "note": "...", "fixed": null}]} with one review per question, i = its index.`;

export type Reviewed = Draft & { score: number; note: string };

/// The curator: one call for the questions of one page. Questions it throws
/// away are left out; fixed ones replace the original. When the curator does
/// not answer, the questions stay unscored (the admin checks them).
export async function curate(ask: Ask, drafts: Draft[], text: string): Promise<{ kept: (Draft & { score: number | null; note: string | null })[]; dropped: number }> {
  if (!drafts.length) return { kept: [], dropped: 0 };
  const listed = drafts.map((d, i) => ({ i, type: d.type, prompt: d.prompt, choices: d.choices, answer: d.answer, explain: d.explain, callout: d.callout ?? null }));
  const reply = await ask(CURATE_PROMPT, `Manual page ${drafts[0].page}:\n${text.slice(0, MAX_PAGE_TEXT)}\n\nQuestions:\n${JSON.stringify(listed)}`, 3000);
  if (!reply || !Array.isArray(reply.reviews)) {
    return { kept: drafts.map((d) => ({ ...d, score: null, note: "Kurator belum memeriksa soal ini." })), dropped: 0 };
  }
  const reviews = new Map<number, Record<string, unknown>>();
  for (const r of reply.reviews as Record<string, unknown>[]) reviews.set(Number(r.i), r);
  const kept: (Draft & { score: number | null; note: string | null })[] = [];
  let dropped = 0;
  drafts.forEach((d, i) => {
    const r = reviews.get(i);
    if (!r) {
      kept.push({ ...d, score: null, note: "Kurator belum memeriksa soal ini." });
      return;
    }
    const score = Math.max(1, Math.min(10, Math.round(Number(r.score) || 0)));
    const note = String(r.note ?? "").slice(0, 300);
    if (r.verdict === "buang" || score <= 3) {
      dropped++;
      return;
    }
    let q: Draft = d;
    if (r.verdict === "perbaiki" && r.fixed && typeof r.fixed === "object") {
      const f = r.fixed as Record<string, unknown>;
      const fixed: Draft = {
        ...d,
        prompt: String(f.prompt ?? d.prompt),
        choices: Array.isArray(f.choices) ? f.choices.map(String) : d.choices,
        answer: f.answer === undefined ? d.answer : Number(f.answer),
        explain: cleanExplain(String(f.explain ?? d.explain)),
        callout: f.callout == null ? d.callout : String(f.callout),
      };
      if (d.type === "bs") fixed.choices = ["Benar", "Salah"];
      stripCallouts(fixed);
      if (!questionProblem(fixed)) q = fixed;
    }
    kept.push({ ...q, score, note });
  });
  return { kept, dropped };
}

// ---- Choosing pages of a whole manual ----

const PLAN_PROMPT = `You choose pages of a heavy-equipment technical manual to make quiz questions from, using its table of contents (bookmarks with page numbers).

Good pages: tables of standard values, pressures, capacities and tightening torques; function and structure of components; adjusting and testing procedures; failure codes and troubleshooting; periodic maintenance intervals; drawings of a component whose parts are numbered with a legend (kind "gambar", e.g. "Control valve", "Structure of ...", "Hydraulic pump" under Structure and function); photos or drawings with part names as labels, as in training slides (kind "gambar").
Skip: covers, foreword, safety notices, index pages, part lists, wiring diagrams, blank pages.
Spread the pages over different systems and chapters; do not take several pages of the same table.

Reply with JSON only: {"pages": [{"page": 412, "kind": "teks", "topic": "standar"}]} where kind is "teks" or "gambar" and topic is one of: struktur, torsi, kapasitas, standar, fault, servis, sistem.`;

export type PlannedPage = { page: number; kind: "teks" | "gambar"; topic: string };

/// Picks [want] pages from the table of contents ([toc]: "page<TAB>title"
/// lines). [topic] 'semua' leaves the choice of topics to the AI.
export async function planPages(ask: Ask, toc: string, pages: number, want: number, topic: string, gambar: boolean): Promise<PlannedPage[] | null> {
  const reply = await ask(
    PLAN_PROMPT,
    `The manual has ${pages} pages. Choose ${want} pages${topic === "semua" ? "" : ` about ${TOPIC_NAMES[topic] ?? topic} only (topic "${topic}")`}${gambar ? `, of which about ${Math.max(1, Math.round(want / 4))} drawing pages (kind "gambar")` : ', no drawing pages'}.\n\nTable of contents (page, title):\n${toc.slice(0, 60_000)}`,
    2000,
  );
  if (!reply || !Array.isArray(reply.pages)) return null;
  const seen = new Set<number>();
  const out: PlannedPage[] = [];
  for (const p of reply.pages as Record<string, unknown>[]) {
    const page = Math.round(Number(p.page));
    if (!(page >= 1 && page <= pages) || seen.has(page)) continue;
    seen.add(page);
    out.push({
      page,
      kind: p.kind === "gambar" && gambar ? "gambar" : "teks",
      topic: topic !== "semua" ? topic : TOPIC_NAMES[String(p.topic)] ? String(p.topic) : "struktur",
    });
  }
  return out.slice(0, Math.max(want, 1) + 5);
}

const PICTURE_WORDS = /\b(gambar|ilustrasi|illustration|nomor\s+\d+)\b/i;

/// "Pilot pump (39)" -> "Pilot pump": a question without a picture must not
/// point at the drawing's callout numbers. Picture questions keep theirs.
export function stripCallouts(q: Draft): Draft {
  if (q.type === "gambar") return q;
  const strip = (t: string) => t.replace(/\s*\(\d{1,3}[A-Za-z]?\)/g, "").replace(/\s+([,.;:?])/g, "$1").trim();
  q.prompt = strip(q.prompt);
  q.choices = q.choices.map(strip);
  q.explain = strip(q.explain);
  return q;
}

/// "Halaman menyatakan bahwa OLSS ..." -> "OLSS ...": the explanation starts
/// with the fact. Same rule in the app (quiz.dart) for older questions.
export function cleanExplain(text: string): string {
  const out = text
    .trim()
    .replace(/^(menurut|berdasarkan)\s+(halaman|manual|teks)(\s+(ini|tersebut|sumber))?[,:]?\s+/i, "")
    .replace(/^(halaman|manual|teks)(\s+(ini|tersebut|sumber))?\s+(menyatakan|menyebutkan|menjelaskan|mengatakan)(\s+bahwa)?[,:]?\s+/i, "");
  return out ? out[0].toUpperCase() + out.slice(1) : out;
}
