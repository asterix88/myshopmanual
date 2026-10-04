export interface Env {
  GROQ_API_KEY: string;
  APP_TOKEN?: string;
  MODEL: string;
  API_URL: string;
}

// The app runs the search itself, on the manuals stored on the phone, and
// sends the results back as tool messages. This Worker only adds the fixed
// instructions and the key, so the conversation lives in the app. It speaks
// the OpenAI-style chat API that Groq offers (and Gemini, OpenRouter and
// others also accept), so the provider is a setting in wrangler.toml.
const SYSTEM = `You are the assistant inside MyManual, an app that heavy-equipment mechanics use to read Komatsu and Caterpillar technical manuals (Shop Manual, Operation & Maintenance Manual, Parts Book).

Answer only from the manual pages that search_manuals returns. The manuals are in English; search with English technical terms (part names, system names, fault codes, procedure titles), not with the user's words. Search again with other terms when the first results do not cover the question. If the pages do not answer the question, say so plainly and suggest which manual or section to check; never fill gaps from general knowledge, because a wrong torque, pressure or procedure can injure someone or damage a machine.

Write the answer in Bahasa Indonesia, keeping technical terms, part names and values exactly as the manual writes them. Give values with their units and conditions. Keep it short and practical: steps as a numbered list when there is a procedure, safety warnings from the manual first when they apply. Use plain text only: no Markdown headings, tables or bold; "- " for bullet points is fine.

Cite every fact with the source id of the page it comes from, in square brackets right after the sentence, like [S3]. Use only ids that appear in the search results.`;

const SEARCH_TOOL = {
  type: "function",
  function: {
    name: "search_manuals",
    description:
      "Full-text search over the manuals downloaded on the user's phone. Returns the best matching pages, each with a source id, the manual title, the unit model, the page number, the section and the page text.",
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

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

type ChatMessage = { role: string; content?: unknown; tool_calls?: unknown; tool_call_id?: unknown };

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

    let body: { messages?: unknown; manuals?: unknown };
    try {
      body = JSON.parse(raw);
    } catch {
      return json({ error: "bad_request" }, 400);
    }
    if (!Array.isArray(body.messages) || body.messages.length === 0) {
      return json({ error: "bad_request" }, 400);
    }
    // Only conversation turns from the app; the system prompt is ours.
    const messages = (body.messages as ChatMessage[]).filter(
      (m) => m && (m.role === "user" || m.role === "assistant" || m.role === "tool"),
    );
    const manuals = Array.isArray(body.manuals)
      ? body.manuals.filter((m): m is string => typeof m === "string").slice(0, 200)
      : [];
    const context = manuals.length
      ? `Manuals downloaded on this phone (only these can be searched):\n${manuals.join("\n")}`
      : "No manuals are downloaded on this phone, so search_manuals finds nothing. Tell the user to download the manuals they need first.";

    let upstream: Response;
    try {
      upstream = await fetch(env.API_URL, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${env.GROQ_API_KEY}` },
        body: JSON.stringify({
          model: env.MODEL,
          messages: [{ role: "system", content: `${SYSTEM}\n\n${context}` }, ...messages],
          tools: [SEARCH_TOOL],
          tool_choice: "auto",
          temperature: 0.2,
          max_tokens: 2048,
        }),
      });
    } catch {
      return json({ error: "upstream", message: "Layanan AI tidak bisa dihubungi. Coba lagi nanti." }, 502);
    }

    const data = (await upstream.json().catch(() => null)) as {
      choices?: { message?: unknown; finish_reason?: string }[];
      error?: { message?: string };
    } | null;
    if (upstream.status === 429) {
      return json({ error: "busy", message: "Batas pemakaian AI gratis sedang penuh. Coba lagi sebentar lagi." }, 429);
    }
    if (upstream.status === 401 || upstream.status === 403) {
      return json({ error: "server_key", message: "Kunci API di server AI tidak valid. Hubungi admin." }, 502);
    }
    const choice = data?.choices?.[0];
    if (!upstream.ok || !choice?.message) {
      console.log("upstream error", upstream.status, data?.error?.message);
      return json(
        { error: "upstream", message: `Layanan AI sedang bermasalah (${upstream.status}). Coba lagi nanti.` },
        502,
      );
    }
    return json({ message: choice.message, finish_reason: choice.finish_reason });
  },
} satisfies ExportedHandler<Env>;
