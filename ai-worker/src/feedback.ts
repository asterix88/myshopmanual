import { requireSession, type AuthEnv } from "./auth";

// Ratings of nyel AI answers: 👍 or 👎 "Jawaban salah". A phone sends the
// rating, the question, the answer and the pages it cited; admins list them
// in the app to see where nyel AI goes right and wrong, and the wrong ones
// become questions in the AI test (app/tool/ai_eval.json). Kept in the AUTH
// KV as "fb:<time>", for a year.

const KEEP_SECONDS = 365 * 24 * 3600;
const MAX_TEXT = 8000;
const LIST_LIMIT = 100;

type Report = {
  rating: "good" | "bad";
  at: number;
  nrp: string;
  name: string;
  question: string;
  answer: string;
  sources: string[];
  note: string;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

const text = (value: unknown, max = MAX_TEXT) => (typeof value === "string" ? value.slice(0, max) : "");

export async function feedback(request: Request, env: AuthEnv): Promise<Response> {
  const auth = await requireSession(env, request);
  if (auth.error) return auth.error;
  const s = auth.session;

  if (request.method === "GET") {
    if (!s.a) return json({ error: "forbidden", message: "Hanya admin." }, 403);
    // Keys sort by time; the newest come last, so read them all (few) and
    // keep the newest.
    const keys: string[] = [];
    let cursor: string | undefined;
    do {
      const page = await env.AUTH.list({ prefix: "fb:", cursor });
      keys.push(...page.keys.map((k) => k.name));
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    const newest = keys.sort().reverse().slice(0, LIST_LIMIT);
    const reports = await Promise.all(newest.map((k) => env.AUTH.get<Report>(k, "json")));
    return json({ reports: reports.filter(Boolean) });
  }

  if (request.method !== "POST") return json({ error: "not_found" }, 404);
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const report: Report = {
    // Apps before 👍 sent only reports of wrong answers.
    rating: body.rating === "good" ? "good" : "bad",
    at: Date.now(),
    nrp: s.n,
    name: s.nm,
    question: text(body.question),
    answer: text(body.answer),
    sources: Array.isArray(body.sources) ? body.sources.slice(0, 20).map((x) => text(x, 200)) : [],
    note: text(body.note, 1000),
  };
  if (!report.answer) return json({ error: "bad_request" }, 400);
  const key = `fb:${new Date(report.at).toISOString()}:${s.n}`;
  await env.AUTH.put(key, JSON.stringify(report), { expirationTtl: KEEP_SECONDS });
  return json({ ok: true });
}
