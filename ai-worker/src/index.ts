export interface Env {
  GROQ_API_KEY: string;
  APP_TOKEN?: string;
  MODEL: string;
  API_URL: string;
  // Page text of every manual, filled by tools/sync_search.py.
  DB: D1Database;
}

// The whole Tanya AI loop runs here: the model asks for searches, this Worker
// runs them on the D1 copy of the manuals' text and feeds the pages back, so
// the phone downloads nothing to ask about any manual. It speaks the
// OpenAI-style chat API that Groq offers (and Gemini, OpenRouter and others
// also accept), so the provider is a setting in wrangler.toml. The app keeps
// the conversation and sends it with every question.
const SYSTEM = `You are the assistant inside MyManual, an app that heavy-equipment mechanics use to read Komatsu and Caterpillar technical manuals (Shop Manual, Operation & Maintenance Manual, Parts Book).

Answer only from the manual pages that search_manuals returns. The manuals are in English; search with English technical terms (part names, system names, fault codes, procedure titles), not with the user's words. Search again with other terms when the first results do not cover the question. If the pages do not answer the question, say so plainly and suggest which manual or section to check; never fill gaps from general knowledge, because a wrong torque, pressure or procedure can injure someone or damage a machine.

Write the answer in Bahasa Indonesia, keeping technical terms, part names and values exactly as the manual writes them. Give values with their units and conditions. Keep it short and practical: steps as a numbered list when there is a procedure, safety warnings from the manual first when they apply. Use plain text: no Markdown headings or tables; "- " for bullet points is fine, and **double stars** may mark a key value or warning in bold.

Cite every fact with the source id of the page it comes from, in square brackets right after the sentence, like [S3]. Use only ids that appear in the search results.

The app can show a page itself as a picture under the answer. When seeing a page would help the mechanic (a component drawing or location, an exploded view or parts figure, a hydraulic or electrical diagram, a connector pin layout, an adjustment illustration), add [Gambar S3] on its own line at the end, using that page's source id. Show at most 3 pictures, only pages whose text shows they carry such a figure (figure numbers, callout numbers, "location", "diagram", parts lists), and none when text alone answers the question.`;

const SEARCH_TOOL = {
  type: "function",
  function: {
    name: "search_manuals",
    description:
      "Full-text search over all the manuals in the app. Returns the best matching pages, each with a source id, the manual title, the unit model, the page number, the section and the page text.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: 'English keywords, e.g. "hydraulic oil filter clogging" or "swing motor relief pressure".',
        },
        unit: {
          type: "string",
          description: 'Unit model to limit the search to, e.g. "PC210". Empty string searches every unit.',
        },
      },
      required: ["query", "unit"],
    },
  },
};

const MAX_BODY_BYTES = 400_000;
// Model calls per question: each search the AI asks for costs one more.
const MAX_ROUNDS = 4;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

type ChatMessage = { role: string; content?: unknown; tool_calls?: unknown; tool_call_id?: unknown };
type ToolCall = { id: string; function?: { name?: string; arguments?: string } };
type Manual = { key: string; unit_id: string; unit_name: string; title: string; type: string };
type Source = { id: number; key: string; unit: string; title: string; type: string; page: number };

/** An error answer for the app, with a message the user can read. */
class Fail extends Error {
  constructor(readonly response: Response) {
    super("fail");
  }
}

const normalize = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");

/** Words of [text] as an FTS5 query matching any of them, best pages first. */
function ftsAnyQuery(text: string): string {
  const words = new Set(text.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 1));
  return [...words].map((w) => `"${w}"`).join(" OR ");
}

async function loadManuals(db: D1Database): Promise<Manual[]> {
  try {
    const { results } = await db
      .prepare("SELECT key, unit_id, unit_name, title, type FROM manuals ORDER BY unit_name, title")
      .all<Manual>();
    return results;
  } catch (e) {
    console.log("manuals table unavailable", String(e));
    return [];
  }
}

/** Runs one search_manuals call; new pages get ids from [nextId] on. */
async function search(
  db: D1Database,
  manuals: Manual[],
  args: { query?: unknown; unit?: unknown },
  nextId: number,
): Promise<{ text: string; sources: Source[] }> {
  const query = ftsAnyQuery(typeof args.query === "string" ? args.query : "");
  if (!query) return { text: "Empty query.", sources: [] };
  const wanted = normalize(typeof args.unit === "string" ? args.unit : "");
  let scope = wanted
    ? manuals.filter((m) => normalize(m.unit_name).includes(wanted) || normalize(m.unit_id).includes(wanted))
    : manuals;
  if (scope.length === 0) scope = manuals; // unknown unit: search everything
  const byKey = new Map(manuals.map((m) => [m.key, m]));

  const { results } = await db
    .prepare(
      `SELECT file_key, page, section, text FROM pages
       WHERE pages MATCH ?1 AND file_key IN (SELECT value FROM json_each(?2))
       ORDER BY bm25(pages) LIMIT 4`,
    )
    .bind(query, JSON.stringify(scope.map((m) => m.key)))
    .all<{ file_key: string; page: number; section: string | null; text: string }>();
  if (results.length === 0) return { text: `No matching pages for "${args.query}".`, sources: [] };

  const sources: Source[] = [];
  const lines: string[] = [];
  for (const row of results) {
    const manual = byKey.get(row.file_key);
    if (!manual) continue;
    const id = nextId + sources.length;
    sources.push({ id, key: row.file_key, unit: manual.unit_name, title: manual.title, type: manual.type, page: row.page });
    // Kept short: free tiers limit tokens per minute.
    const text = row.text.replace(/[ \t]+/g, " ").trim();
    lines.push(
      `[S${id}] ${manual.unit_name} · ${manual.title} · page ${row.page}${row.section ? ` · section: ${row.section}` : ""}`,
      text.length > 1200 ? `${text.slice(0, 1200)}…` : text,
      "",
    );
  }
  return { text: lines.join("\n"), sources };
}

/** One model turn, trying the models in MODEL in order. */
async function callModel(env: Env, messages: unknown[]): Promise<{ message: ChatMessage; model: string }> {
  // Free tiers limit tokens per minute per model, so when one model is
  // full (or retired) the same request goes to the next one in MODEL.
  const models = env.MODEL.split(",").map((m) => m.trim()).filter(Boolean);
  let lastStatus = 0;
  let rateLimited = false;
  for (const model of models) {
    let upstream: Response;
    try {
      upstream = await fetch(env.API_URL, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${env.GROQ_API_KEY}` },
        body: JSON.stringify({
          model,
          messages,
          tools: [SEARCH_TOOL],
          tool_choice: "auto",
          temperature: 0.2,
          max_tokens: 2048,
          // Less hidden reasoning means fewer tokens against the limit.
          ...(model.startsWith("openai/gpt-oss") ? { reasoning_effort: "low" } : {}),
        }),
      });
    } catch {
      throw new Fail(json({ error: "upstream", message: "Layanan AI tidak bisa dihubungi. Coba lagi nanti." }, 502));
    }
    const data = (await upstream.json().catch(() => null)) as {
      choices?: { message?: ChatMessage }[];
      error?: { message?: string; code?: string };
    } | null;
    if (upstream.status === 401 || upstream.status === 403) {
      throw new Fail(json({ error: "server_key", message: "Kunci API di server AI tidak valid. Hubungi admin." }, 502));
    }
    const message = data?.choices?.[0]?.message;
    if (upstream.ok && message) return { message, model };
    lastStatus = upstream.status;
    if (upstream.status === 429 || upstream.status === 413) rateLimited = true;
    console.log("model failed", model, upstream.status, data?.error?.code, data?.error?.message);
    // 429 and 413 are rate limits; 404 and 400 can mean a retired model.
    if (![400, 404, 413, 429, 498, 500, 502, 503].includes(upstream.status)) break;
  }
  if (rateLimited) {
    throw new Fail(json({ error: "busy", message: "Batas pemakaian AI gratis sedang penuh. Coba lagi dalam 1 menit." }, 429));
  }
  throw new Fail(json({ error: "upstream", message: `Layanan AI sedang bermasalah (${lastStatus}). Coba lagi nanti.` }, 502));
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return json({ ok: true, model: env.MODEL });
    }
    if (request.method !== "POST" || url.pathname !== "/chat") {
      return json({ error: "not_found" }, 404);
    }
    if (env.APP_TOKEN && request.headers.get("authorization") !== `Bearer ${env.APP_TOKEN}`) {
      return json({ error: "unauthorized" }, 401);
    }
    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) {
      return json({ error: "too_large", message: "Percakapan terlalu panjang. Mulai percakapan baru." }, 413);
    }

    let body: { messages?: unknown; source_start?: unknown };
    try {
      body = JSON.parse(raw);
    } catch {
      return json({ error: "bad_request" }, 400);
    }
    if (!Array.isArray(body.messages) || body.messages.length === 0) {
      return json({ error: "bad_request" }, 400);
    }
    // Only conversation turns from the app; the system prompt is ours.
    const history = (body.messages as ChatMessage[]).filter(
      (m) => m && (m.role === "user" || m.role === "assistant" || m.role === "tool"),
    );
    // Source ids keep counting across the conversation, so [S3] in an earlier
    // answer still means the same page.
    let nextId = typeof body.source_start === "number" && body.source_start > 0 ? Math.floor(body.source_start) : 1;

    const manuals = await loadManuals(env.DB);
    const context = manuals.length
      ? `Manuals in the app (pass unit when the question is about one unit model):\n${manuals
          .map((m) => `${m.unit_name}: ${m.title} (${m.type})`)
          .join("\n")}`
      : "The manual text is not on the server yet, so search_manuals finds nothing. Tell the user that the AI's copy of the manuals is still being prepared and to try again later.";

    const added: ChatMessage[] = [];
    const sources: Source[] = [];
    try {
      for (let round = 0; round < MAX_ROUNDS; round++) {
        const { message, model } = await callModel(env, [
          { role: "system", content: `${SYSTEM}\n\n${context}` },
          ...history,
          ...added,
        ]);
        const calls = (Array.isArray(message.tool_calls) ? message.tool_calls : []) as ToolCall[];
        added.push({ role: "assistant", content: message.content ?? null, ...(calls.length ? { tool_calls: calls } : {}) });
        if (calls.length === 0) return json({ messages: added, sources, model });
        for (const call of calls) {
          let args: { query?: unknown; unit?: unknown } = {};
          try {
            args = JSON.parse(call.function?.arguments ?? "{}");
          } catch {
            // Malformed arguments: an empty search, which tells the model.
          }
          const found = manuals.length
            ? await search(env.DB, manuals, args, nextId).catch((e) => {
                console.log("search failed", String(e));
                return { text: "Search failed.", sources: [] as Source[] };
              })
            : { text: "No manuals on the server yet.", sources: [] as Source[] };
          nextId += found.sources.length;
          sources.push(...found.sources);
          added.push({ role: "tool", tool_call_id: call.id, content: found.text });
        }
      }
    } catch (e) {
      if (e instanceof Fail) return e.response;
      throw e;
    }
    // Out of rounds: the app says no answer was found.
    return json({ messages: added, sources, model: null });
  },
} satisfies ExportedHandler<Env>;
