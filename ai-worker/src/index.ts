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

Write the answer in Bahasa Indonesia, keeping technical terms, part names and values exactly as the manual writes them. Give values with their units and conditions. Keep it short and practical: steps as a numbered list when there is a procedure, safety warnings from the manual first when they apply. Use plain text: no Markdown headings or tables; "- " for bullet points is fine, and **double stars** may mark a key value or warning in bold.

Cite every fact with the source id of the page it comes from, in square brackets right after the sentence, like [S3]. Use only ids that appear in the search results.

The app can show a page itself as a picture under the answer. When seeing a page would help the mechanic (a component drawing or location, an exploded view or parts figure, a hydraulic or electrical diagram, a connector pin layout, an adjustment illustration), add [Gambar S3] on its own line at the end, using that page's source id. Show at most 3 pictures, only pages whose text shows they carry such a figure (figure numbers, callout numbers, "location", "diagram", parts lists), and none when text alone answers the question.`;

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
            messages: [{ role: "system", content: `${SYSTEM}\n\n${context}` }, ...messages],
            tools: [SEARCH_TOOL],
            tool_choice: "auto",
            temperature: 0.2,
            max_tokens: 2048,
            // Less hidden reasoning means fewer tokens against the limit.
            ...(model.startsWith("openai/gpt-oss") ? { reasoning_effort: "low" } : {}),
          }),
        });
      } catch {
        return json({ error: "upstream", message: "Layanan AI tidak bisa dihubungi. Coba lagi nanti." }, 502);
      }
      const data = (await upstream.json().catch(() => null)) as {
        choices?: { message?: unknown; finish_reason?: string }[];
        error?: { message?: string; code?: string };
      } | null;
      if (upstream.status === 401 || upstream.status === 403) {
        return json({ error: "server_key", message: "Kunci API di server AI tidak valid. Hubungi admin." }, 502);
      }
      const choice = data?.choices?.[0];
      if (upstream.ok && choice?.message) {
        return json({ message: choice.message, finish_reason: choice.finish_reason, model });
      }
      lastStatus = upstream.status;
      if (upstream.status === 429 || upstream.status === 413) rateLimited = true;
      console.log("model failed", model, upstream.status, data?.error?.code, data?.error?.message);
      // 429 and 413 are rate limits; 404 and 400 can mean a retired model.
      if (![400, 404, 413, 429, 498, 500, 502, 503].includes(upstream.status)) break;
    }
    if (rateLimited) {
      return json({ error: "busy", message: "Batas pemakaian AI gratis sedang penuh. Coba lagi dalam 1 menit." }, 429);
    }
    return json(
      { error: "upstream", message: `Layanan AI sedang bermasalah (${lastStatus}). Coba lagi nanti.` },
      502,
    );
  },
} satisfies ExportedHandler<Env>;
