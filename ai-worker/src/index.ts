export interface Env {
  GROQ_API_KEY?: string;
  DEEPSEEK_API_KEY?: string;
  APP_TOKEN?: string;
  // The admin code that lifts the app's daily question limit on a phone.
  OWNER_CODE?: string;
  MODEL: string;
  VISION_MODEL: string;
  API_URL: string;
}

// The app runs the search itself, on the manuals' search indexes, and
// sends the results back as tool messages. This Worker only adds the fixed
// instructions and the key, so the conversation lives in the app. It speaks
// the OpenAI-style chat API that Groq offers (and Gemini, OpenRouter and
// others also accept), so the provider is a setting in wrangler.toml.
const SYSTEM = `Your name is Nyel AI. If asked who you are, say you are Nyel AI, the assistant inside MyManual. You are the assistant inside MyManual, an app that heavy-equipment mechanics use to read Komatsu and Caterpillar technical manuals (Shop Manual, Operation & Maintenance Manual, Parts Book).

Answer only from the manual pages that search_manuals returns. The manuals are in English; search with English technical terms (part names, system names, fault codes, procedure titles), not with the user's words. Search again with other terms when the first results do not cover the question. If the pages do not answer the question, say so plainly and suggest which manual or section to check; never fill gaps from general knowledge, because a wrong torque, pressure or procedure can injure someone or damage a machine.

Write the answer in Bahasa Indonesia and start straight with it (no remarks about what you looked at or will do), keeping technical terms, part names and values exactly as the manual writes them. Give values with their units and conditions. Keep it short and practical: steps as a numbered list when there is a procedure, safety warnings from the manual first when they apply. Use plain text: no Markdown headings or tables; "- " for bullet points is fine, and **double stars** may mark a key value or warning in bold.

Cite every fact with the source id of the page it comes from, in square brackets right after the sentence, like [S3]. Use only ids that appear in the search results.

The app can show a page itself as a picture under the answer. When seeing a page would help the mechanic (a component drawing or location, an exploded view or parts figure, a hydraulic or electrical diagram, a connector pin layout, an adjustment illustration), add [Gambar S3] on its own line at the end, using that page's source id. Show at most 3 pictures, only pages whose text shows they carry such a figure (figure numbers, callout numbers, "location", "diagram", parts lists), and none when text alone answers the question.`;

// Added when the app can show the AI manual pages as pictures.
const VIEW_INSTRUCTIONS = `You can also look at manual pages with view_page. Use it when the answer is in a drawing rather than in text: a wiring or electrical diagram, a hydraulic or pneumatic schematic, a component location, a connector pin layout, an exploded view. Manuals marked "pictures only" cannot be searched at all; look at their pages directly (a schematic usually has only 1 or 2 pages). In a schematic manual the first pages are usually a cover, a legend and component location tables; the drawing sheets come after them. Search first: the component tables give each component's sheet and grid location (like D-3), which tells you which page and which part of it to look at. After your first look at a manual, the reply also names its large drawing sheets (pages much bigger than the rest): that is where the drawing is, so go there next. Large sheets are hard to read whole: look at the full page first to find the area, then at the part (top-left, top-right, bottom-left, bottom-right) that holds it. You can look at up to 6 pictures per question, so don't spend them on cover or table pages that search already gave you.

When reading a drawing, report only what you can actually read on it: labels, component names, wire numbers and colours, connector and pin numbers, port names, pressures printed on it. Say plainly what you cannot read or follow; never guess where a line goes. Cite the picture with its source id like any other page, and add [Gambar S#] so the mechanic sees it too.`;

const SEARCH_TOOL = {
  type: "function",
  function: {
    name: "search_manuals",
    description:
      "Full-text search over all the manuals in the app (downloaded on the phone or not). Returns the best matching pages, each with a source id, the manual title, the unit model, the page number, the section and the page text.",
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

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";

const VIEW_TOOL = {
  type: "function",
  function: {
    name: "view_page",
    description:
      "Look at one manual page as a picture, or at a quarter of it to see small print. Returns the picture with a source id you can cite.",
    parameters: {
      type: "object",
      properties: {
        source: {
          type: "string",
          description: 'Source id of a page found by search_manuals, e.g. "S3". Leave empty to use manual and page.',
        },
        manual: { type: "string", description: 'Manual id from the manual list, e.g. "M4".' },
        page: { type: "integer", description: "Page number in that manual, from 1." },
        region: {
          type: "string",
          enum: ["full", "top-left", "top-right", "bottom-left", "bottom-right"],
          description: "Which part of the page; full by default.",
        },
      },
      required: ["source", "manual", "page", "region"],
    },
  },
};

// Page pictures make requests large.
const MAX_BODY_BYTES = 8_000_000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

type ChatMessage = {
  role: string;
  content?: unknown;
  tool_calls?: unknown;
  tool_call_id?: unknown;
  reasoning_content?: unknown;
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return json({ ok: true, model: env.MODEL });
    }
    if (request.method === "POST" && url.pathname === "/owner") {
      // The app asks once whether a code typed in its menu is the admin code.
      let code = "";
      try {
        code = String(((await request.json()) as { code?: unknown }).code ?? "");
      } catch {
        return json({ error: "bad_request" }, 400);
      }
      return json({ ok: !!env.OWNER_CODE && code.trim() === env.OWNER_CODE.trim() });
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

    let body: { messages?: unknown; manuals?: unknown; features?: unknown };
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
    // Older app versions can't show pages to the AI.
    const canView = Array.isArray(body.features) && body.features.includes("view_page");
    const hasPictures = messages.some(
      (m) => Array.isArray(m.content) && m.content.some((part) => part?.type === "image_url"),
    );
    const manuals = Array.isArray(body.manuals)
      ? body.manuals.filter((m): m is string => typeof m === "string").slice(0, 200)
      : [];
    const context = manuals.length
      ? `Manuals in the app (all can be searched; pass unit when the question is about one unit model, so only its manuals are searched):\n${manuals.join("\n")}`
      : "The app has no manual list yet (it has not reached the server), so search_manuals finds nothing. Tell the user to connect to the internet and open the Unit tab first.";

    // MODEL is a list tried in order: when one model is full, out of credit
    // or retired, the same request goes to the next one. "deepseek:<model>"
    // goes to DeepSeek; a bare name goes to API_URL (Groq). Entries whose key
    // is not set are skipped.
    // Only models that can see pictures get a conversation that has some.
    const models = (hasPictures ? env.VISION_MODEL : env.MODEL)
      .split(",")
      .map((m) => m.trim())
      .filter(Boolean);
    const system = canView ? `${SYSTEM}\n\n${VIEW_INSTRUCTIONS}` : SYSTEM;
    let lastStatus = 0;
    let rateLimited = false;
    let keyRejected = false;
    for (const entry of models) {
      const deepseek = entry.startsWith("deepseek:");
      const model = deepseek ? entry.slice("deepseek:".length) : entry;
      const key = deepseek ? env.DEEPSEEK_API_KEY : env.GROQ_API_KEY;
      if (!key) continue;
      const url = deepseek ? DEEPSEEK_URL : env.API_URL;
      // DeepSeek's thinking mode wants its reasoning sent back on every tool
      // round, which the app doesn't keep, so it's turned off; other
      // providers may reject the field.
      const turns = deepseek ? messages : messages.map(({ reasoning_content: _, ...m }) => m);
      let upstream: Response;
      try {
        upstream = await fetch(url, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
          body: JSON.stringify({
            model,
            messages: [{ role: "system", content: `${system}\n\n${context}` }, ...turns],
            tools: canView ? [SEARCH_TOOL, VIEW_TOOL] : [SEARCH_TOOL],
            tool_choice: "auto",
            temperature: 0.2,
            max_tokens: 2048,
            ...(deepseek ? { thinking: { type: "disabled" } } : {}),
            // Less hidden reasoning means fewer tokens against the limit.
            ...(model.startsWith("openai/gpt-oss") ? { reasoning_effort: "low" } : {}),
          }),
        });
      } catch (e) {
        console.log("model unreachable", entry, String(e));
        lastStatus = 502;
        continue;
      }
      const data = (await upstream.json().catch(() => null)) as {
        choices?: { message?: unknown; finish_reason?: string }[];
        error?: { message?: string; code?: string };
      } | null;
      const choice = data?.choices?.[0];
      if (upstream.ok && choice?.message) {
        return json({ message: choice.message, finish_reason: choice.finish_reason, model });
      }
      lastStatus = upstream.status;
      if (upstream.status === 429 || upstream.status === 413) rateLimited = true;
      if (upstream.status === 401 || upstream.status === 403) keyRejected = true;
      console.log("model failed", entry, upstream.status, data?.error?.code, data?.error?.message);
      // 429 and 413 are rate limits, 402 is no credit left, 401/403 a bad key
      // for that provider; 404 and 400 can mean a retired model.
      if (![400, 401, 402, 403, 404, 413, 422, 429, 498, 500, 502, 503].includes(upstream.status)) break;
    }
    if (keyRejected && !rateLimited) {
      return json({ error: "server_key", message: "Kunci API di server AI tidak valid. Hubungi admin." }, 502);
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
