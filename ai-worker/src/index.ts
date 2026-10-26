import { countQuestion, handleAuth, requireSession, SESSION_HEADER } from "./auth";
import { feedback } from "./feedback";
import { handleFiles, type FilesEnv } from "./files";

export interface Env extends FilesEnv {
  GROQ_API_KEY?: string;
  DEEPSEEK_API_KEY?: string;
  APP_TOKEN?: string;
  // "1" once every phone has the login version: /chat then refuses phones
  // without a session (see wrangler.toml).
  REQUIRE_LOGIN?: string;
  // Key from app.tavily.com for web_search; without it Wikipedia is used.
  TAVILY_API_KEY?: string;
  MODEL: string;
  VISION_MODEL: string;
  API_URL: string;
}

// The app runs the search itself, on the manuals' search indexes, and
// sends the results back as tool messages. This Worker only adds the fixed
// instructions and the key, so the conversation lives in the app. It speaks
// the OpenAI-style chat API that Groq offers (and Gemini, OpenRouter and
// others also accept), so the provider is a setting in wrangler.toml.
const SYSTEM = `Your name is nyel AI. If asked who you are, say you are nyel AI, the assistant inside MyManual. You are the assistant inside MyManual, an app that heavy-equipment mechanics use to read Komatsu and Caterpillar technical manuals (Shop Manual, Operation & Maintenance Manual, Parts Book).

You are also a master mechanic and instructor in heavy-equipment electrical systems, hydraulics and mechanical systems (engines, power trains, transmissions and clutches, brakes, steering, undercarriage), and a friendly discussion partner for technical problems. Use the manuals first: before answering any technical question, call search_manuals, even when you think you already know the answer and even when earlier answers in this chat said something else. Search with English technical terms (part names, system names, fault codes, procedure titles), not with the user's words, and search again with other terms when the first results do not cover the question. A code, part number or unfamiliar string of letters and digits (for example "DKULKB", "CA234", "E02", "07000-12115") is most likely a failure code or part number from the manuals: search for the code on its own as the query, without extra words like "error code", with the unit when the user named one (otherwise an empty unit), and answer from the page that has it.

You are not limited to the manuals. When they do not cover the question, or cover only part of it, after searching well (see the accuracy rules below), answer from your own expert knowledge, marked as general: what a term or component is, how a system works, the theory behind it (Ohm's law, hydraulic pressure and flow, load-sensing, valve, pump and clutch types), troubleshooting logic and likely causes, measuring methods, good workshop practice and safety. Never answer only that a term was not found in the manuals, and never report your search (no "Hasil pencarian", no lists of what you searched or of unrelated hits); the mechanic wants the explanation, not the search log. Earlier answers in this chat may have said a term was not found: do not repeat that, answer from your knowledge now. A bare term or code on its own ("SL1", "ECMV") means "what is this?": explain it, using the earlier questions in the chat as context. Mechanics use shorthand: read terms and abbreviations as a heavy-equipment mechanic would (for example "Spring Loaded I" / "SL1" / "SLI" in bulldozer steering and brake systems is the spring-loaded type: engaged (connected, braking) by spring force and disengaged (released) by oil pressure, so it stays engaged when the engine is off or pressure is lost, which is fail-safe; also "ECMV", "PPC", "LS", "CLSS", "SOL" and similar). When the user has already said what an abbreviation stands for, use that meaning.

Answer a "what is" question like an experienced instructor: the first sentence states the single most likely meaning plainly and with confidence, in the machine context where it is used (for example "Pada sistem kemudi dan pengereman bulldozer, Spring Loaded I (SL1) adalah ..."); then explain how it works in each state (normal or engine off, operated), why it is built that way, and what goes wrong in the field. Do not open with a list of possible meanings or with what it is "not"; mention another meaning only at the end, in one line, when there is real doubt. Ask a short question back only when the question cannot be understood at all, and even then explain what you can first.

Accuracy comes before everything else. Junior mechanics act on your answers, and a confident wrong answer can damage a machine or hurt someone:
- Never tell the mechanic that their question or premise is wrong, and never state that something does not exist, has no value, has no role or is not related ("tidak ada", "bukan", "tidak berpengaruh", "tidak berhubungan") unless a manual page you cite says so. When the manuals do not settle it, say what you know, mark it as general knowledge, and say what to check in the manual or the circuit diagram of that unit. Mechanics often know their machine's circuits well: when they describe how a circuit works, take it seriously and search for it.
- For an electrical question (starting, charging, a safety or neutral relay, a terminal voltage or signal, a sensor or switch value) and for any "does not start / does not work" question, search the Shop Manual's troubleshooting first. E-mode tables (for example "Engine does not start", "Engine does not stop", "Battery is not charged") list each cause with the terminals to measure ("Between <terminal> - chassis ground"), the switch position and the standard value. Search with the English symptom title and also with the terminal or signal name (for example "alternator terminal R generation signal starting motor"), with the unit.
- Before you answer, check your draft against the pages you found: every value, and every statement about how this machine's circuit or system works, must come from a page you cite. Anything else is general knowledge: mark it as such and word it as typical ("biasanya", "umumnya"), never as fact about this machine.
- When a manual page and your general knowledge disagree, the manual is right; follow it and do not argue against it.

Keep the two kinds of facts apart, so the mechanic knows what comes from the manual:
- Facts from manual pages get their source id. Explanations from your own knowledge get no source id; introduce them with "Secara umum," (or mark them "(pengetahuan umum)"). When the manuals do not cover the question, you may say so in one short line, then give the explanation.
- Values and steps for a specific machine (torques, pressures, clearances, capacities, settings, part numbers, fault-code meanings, the exact procedure for a model) are best taken from the manual. When the manual pages do not give them, you may give typical values or a general procedure from your knowledge, marked clearly as general (for example "nilai umum, cek manual unit sebelum dipakai"), never as that model's specification; never make up a part number or the meaning of a model-specific fault code.

Write the answer in Bahasa Indonesia and start straight with it (no remarks about what you looked at or will do), keeping technical terms, part names and values exactly as the manual writes them. Give values with their units and conditions. Talk like an experienced colleague in the workshop: concise, tidy, helpful and informative, with no filler. Fit the shape of the answer to the question instead of using one template. A quick question (a value, a yes or no, what a code means, a short follow-up) gets a short answer: one to three sentences, no titles, the key value in bold. A longer question gets a direct opening sentence, then only the parts it needs; when there are several parts, a short title line ending in a colon (for example "Penyebab umum:", "Langkah pemeriksaan:", "Nilai standar:") may start each, followed by "- " bullet points or a numbered list for steps, with a blank line between parts. Never add a section just to fill a pattern. Keep each point to one or two sentences and each paragraph to at most three. Safety warnings from the manual come first when they apply. Use plain text: no Markdown headings (#) or tables; **double stars** may mark a key value or warning in bold.

When the mechanic describes a problem or symptom (something slow, weak, noisy, hot, leaking, not working, a warning lamp or failure code), guide the troubleshooting the way a senior mechanic would on site:
- Search the manuals for the failure code or the symptom first; Komatsu Shop Manuals have troubleshooting sections by failure code and by symptom (E-mode electrical, H-mode hydraulic and mechanical, S-mode engine), each with causes, checks and standard values. Follow that manual procedure when it exists.
- Name the most likely causes first, ordered from likely and quick to check to rare and costly.
- Give the checks in order, starting with the simple ones (visual check, oil level, fuses and connectors, failure codes on the monitor) before measurements and disassembly. For each measurement say where to measure, the condition (engine speed, oil temperature, mode) and the standard value from the manual, and what the result means: if within standard go to the next check, if out of standard what that points to.
- Use what the mechanic already told you, and do not repeat checks they have already done. When a key fact is missing (unit and serial, failure code, when it happens, one side or both, hot or cold), still give the first checks, then ask at most two short questions at the end.
- Invite them to report the results so you can continue step by step together.
- Mention the safety step that matters for the job (lower the work equipment, release hydraulic pressure, lock the machine, battery off before electrical work).

Cite every fact taken from a manual page with the source id of that page, in square brackets right after the sentence, like [S3]. Use only ids that appear in the search results. The app removes these marks from the text and lists the pages under the answer, so do not write page numbers or "[1]"-style numbers yourself.

The app can show a page itself as a picture under the answer. When seeing a page would help the mechanic (a component drawing or location, an exploded view or parts figure, a hydraulic or electrical diagram, a connector pin layout, an adjustment illustration), add [Gambar S3] on its own line at the end, using that page's source id. Add a picture only when the answer depends on the drawing itself (where a part is, how it is connected or routed, how it fits together) and the page's text shows it carries such a figure (figure numbers, callout numbers, "location", "diagram", parts lists). When the text answers the question (a value, a failure code's meaning, a procedure, an explanation), add none. Show at most 2.`;

// Added when the app can show the AI manual pages as pictures.
const VIEW_INSTRUCTIONS = `You can also look at manual pages with view_page. Use it when the answer is in a drawing rather than in text: a wiring or electrical diagram, a hydraulic or pneumatic schematic, a component location, a connector pin layout, an exploded view. Manuals marked "pictures only" cannot be searched at all; look at their pages directly (a schematic usually has only 1 or 2 pages). In a schematic manual the first pages are usually a cover, a legend and component location tables; the drawing sheets come after them. Search first: the component tables give each component's sheet and grid location (like D-3), which tells you which page and which part of it to look at. After your first look at a manual, the reply also names its large drawing sheets (pages much bigger than the rest): that is where the drawing is, so go there next. Large sheets are hard to read whole: look at the full page first to find the area, then at the part (top-left, top-right, bottom-left, bottom-right) that holds it. You can look at up to 6 pictures per question, so don't spend them on cover or table pages that search already gave you.

When reading a drawing, report only what you can actually read on it: labels, component names, wire numbers and colours, connector and pin numbers, port names, pressures printed on it. Say plainly what you cannot read or follow; never guess where a line goes. Cite the picture with its source id like any other page, and add [Gambar S#] so the mechanic sees it too.`;

// Added to the instructions: the Worker runs web_search itself, so every
// app version gets it.
const WEB_INSTRUCTIONS = `You can also search the internet with web_search. When the manuals do not cover the question, search the web once before answering to check your explanation, especially for a term, abbreviation, product or brand name, or how a particular system works; then answer, correcting anything the results show you had wrong. Skip it when the manuals already answer the question, for basic theory (Ohm's law, how a gear pump works), and for follow-up questions the earlier results already cover. Never search the web for a machine's specification values. Call it on its own, not together with other tools, with a short English query. Facts from web results are not manual facts: give them without source ids and name the site in brackets after the sentence, like (sumber: wikipedia.org). Web results can be wrong; prefer the manuals and say so when they disagree.`;

const WEB_TOOL = {
  type: "function",
  function: {
    name: "web_search",
    description:
      "Search the internet. Returns a few results, each with a title, a site address and a short text. Use sparingly; see the instructions.",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: 'Short English keywords, e.g. "spring loaded brake bulldozer steering clutch".' },
      },
      required: ["query"],
    },
  },
};

// Web searches per question. Tavily's free plan gives 1,000 a month and
// simply stops (no bill) when they are used up; Wikipedia takes over then.
const MAX_WEB_SEARCHES = 2;

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

// Search results carry only the start of each page; tables (troubleshooting,
// failure codes, specifications) go on below it.
const READ_TOOL = {
  type: "function",
  function: {
    name: "read_page",
    description:
      "Read the whole text of a page found by search_manuals. Search results show only the start of each page (cut off with …); use this before taking a value from a table or a long page.",
    parameters: {
      type: "object",
      properties: {
        source: { type: "string", description: 'Source id of the page, e.g. "S3".' },
      },
      required: ["source"],
    },
  },
};

const READ_INSTRUCTIONS = `Search results show only the start of each page, cut off with "…". Troubleshooting tables (E-, H-, S-mode), failure-code pages and specification tables go on below that, and one table often has several rows with different values for different measuring points (for example one value at the alternator and another at a harness connector). Before you give a value or a check from such a page, call read_page with its source id and read the whole table; then give the value of the row that matches the mechanic's question, with its measuring point and switch position.`;

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
// Extra tries when DeepSeek says it is too busy, before the fallback models.
const DEEPSEEK_BUSY_RETRIES = 2;

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

const USER_AGENT = "MyManual-AI/1.0 (https://mymanual.my.id)";

type WebResult = { title: string; url: string; text: string };

async function tavilySearch(query: string, key: string): Promise<WebResult[]> {
  const response = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
    body: JSON.stringify({ query, search_depth: "basic", max_results: 5, include_answer: false }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`tavily ${response.status}`);
  const data = (await response.json()) as { results?: { title?: string; url?: string; content?: string }[] };
  return (data.results ?? []).map((r) => ({ title: r.title ?? "", url: r.url ?? "", text: r.content ?? "" }));
}

async function wikipediaSearch(query: string): Promise<WebResult[]> {
  const headers = { "user-agent": USER_AGENT };
  const found = await fetch(
    `https://en.wikipedia.org/w/rest.php/v1/search/page?q=${encodeURIComponent(query)}&limit=3`,
    { headers, signal: AbortSignal.timeout(10_000) },
  );
  if (!found.ok) throw new Error(`wikipedia ${found.status}`);
  const pages = ((await found.json()) as { pages?: { key?: string; title?: string }[] }).pages ?? [];
  const results = await Promise.all(
    pages.map(async (page): Promise<WebResult | null> => {
      if (!page.key) return null;
      const summary = await fetch(
        `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(page.key)}`,
        { headers, signal: AbortSignal.timeout(10_000) },
      ).catch(() => null);
      const data = summary?.ok ? ((await summary.json()) as { extract?: string }) : null;
      if (!data?.extract) return null;
      return { title: page.title ?? page.key, url: `https://en.wikipedia.org/wiki/${page.key}`, text: data.extract };
    }),
  );
  return results.filter((r): r is WebResult => r !== null);
}

// Tavily when it has a key and searches left, otherwise Wikipedia.
async function webSearch(query: string, env: Env): Promise<string> {
  let results: WebResult[] = [];
  if (env.TAVILY_API_KEY) {
    try {
      results = await tavilySearch(query, env.TAVILY_API_KEY);
      console.log("web search (tavily)", query, results.length);
    } catch (e) {
      console.log("tavily failed", String(e));
    }
  }
  if (results.length === 0) {
    try {
      results = await wikipediaSearch(query);
      console.log("web search (wikipedia)", query, results.length);
    } catch (e) {
      console.log("wikipedia failed", String(e));
    }
  }
  if (results.length === 0) return "Web search found nothing (or is not available now). Answer from your own knowledge.";
  return results
    .map((r) => `${r.title}\n${r.url}\n${r.text.replace(/\s+/g, " ").slice(0, 1200)}`)
    .join("\n\n");
}

type ToolCall = { id?: string; function?: { name?: string; arguments?: string } };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

// DeepSeek sometimes writes a tool call as its own markup in the answer
// text ("<｜DSML｜function_calls> ... </｜DSML｜function_calls>") instead of a
// real tool call, mostly when the request carries no tools. That text is
// cut out; if nothing else is left, the model is asked again.
const DSML_BLOCK = /<[｜|\s]*DSML[｜|\s]*(?:function_)?calls>[\s\S]*?(?:<\/[｜|\s]*DSML[｜|\s]*(?:function_)?calls>|$)/g;
const DSML_TAG = /<\/?[｜|\s]*DSML[｜|\s]*[^>]*>/g;

function hasDsml(text: unknown): boolean {
  return typeof text === "string" && /[｜|]\s*DSML\s*[｜|]/.test(text);
}

function stripDsml(text: string): string {
  return text.replace(DSML_BLOCK, "").replace(DSML_TAG, "").replace(/\n{3,}/g, "\n\n").trim();
}

// The last round of a question gets no tools. DeepSeek still writes calls
// (as DSML markup) when the conversation holds tool rounds, even with
// tool_choice "none", so that round sees them as plain text: each lookup
// and its result become a note from the app.
function flattenToolRounds(turns: ChatMessage[]): ChatMessage[] {
  const names = new Map<string, string>();
  const out: ChatMessage[] = [];
  for (const m of turns) {
    const { reasoning_content: _, tool_calls, tool_call_id, ...rest } = m;
    if (m.role === "assistant" && Array.isArray(tool_calls)) {
      for (const call of tool_calls as ToolCall[]) {
        if (call.id) names.set(call.id, `${call.function?.name ?? "tool"} ${call.function?.arguments ?? ""}`.trim());
      }
      if (typeof m.content === "string" && m.content.trim()) out.push({ role: "assistant", content: m.content });
    } else if (m.role === "tool") {
      const label = names.get(String(tool_call_id)) ?? "a lookup";
      out.push({ role: "user", content: `(From the app, result of ${label}:)\n${typeof m.content === "string" ? m.content : JSON.stringify(m.content)}` });
    } else {
      out.push(rest);
    }
  }
  return out;
}

type ChatMessage = {
  role: string;
  content?: unknown;
  tool_calls?: unknown;
  tool_call_id?: unknown;
  reasoning_content?: unknown;
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const counted: { undo?: () => Promise<void> } = {};
    const response = await handle(request, env, ctx, counted);
    // A question that got no answer does not use up the allowance.
    if (counted.undo && response.status !== 200) await counted.undo();
    return response;
  },
} satisfies ExportedHandler<Env>;

async function handle(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  counted: { undo?: () => Promise<void> },
): Promise<Response> {
  const url = new URL(request.url);
  if (url.hostname.startsWith("files.")) return handleFiles(request, env, ctx);
  const auth = await handleAuth(request, env, url.pathname);
  if (auth) return auth;
  if (request.method === "GET" && url.pathname === "/") {
    return json({ ok: true, model: env.MODEL });
  }
  if (request.method === "POST" && url.pathname === "/owner") {
    // Apps before the NRP login ask whether a code typed in their menu is
    // the admin code.
    let code = "";
    try {
      code = String(((await request.json()) as { code?: unknown }).code ?? "");
    } catch {
      return json({ error: "bad_request" }, 400);
    }
    return json({ ok: !!env.OWNER_CODE && code.trim() === env.OWNER_CODE.trim() });
  }
  if (url.pathname === "/feedback") return feedback(request, env);
  if (request.method !== "POST" || url.pathname !== "/chat") {
    return json({ error: "not_found" }, 404);
  }
  if (env.APP_TOKEN && request.headers.get("authorization") !== `Bearer ${env.APP_TOKEN}`) {
    return json({ error: "unauthorized" }, 401);
  }
  // Phones with the login version send their session; older ones work
  // without until REQUIRE_LOGIN is "1".
  let session = null;
  if (request.headers.get(SESSION_HEADER) || env.REQUIRE_LOGIN === "1") {
    const checked = await requireSession(env, request);
    if (checked.error) return checked.error;
    session = checked.session;
  }
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) {
    return json({ error: "too_large", message: "Percakapan terlalu panjang. Mulai percakapan baru." }, 413);
  }

  let body: { messages?: unknown; manuals?: unknown; features?: unknown; final?: unknown };
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return json({ error: "bad_request" }, 400);
  }
  // Only conversation turns from the app; the system prompt is ours.
  // Answers saved with tool-call markup in them would teach the model to
  // write it again.
  const messages = (body.messages as ChatMessage[])
    .filter((m) => m && (m.role === "user" || m.role === "assistant" || m.role === "tool"))
    .map((m) => (m.role === "assistant" && hasDsml(m.content) ? { ...m, content: stripDsml(m.content as string) } : m));
  // A request ending with the user's message starts a new question; the
  // rounds after it end with the app's tool results.
  if (session && messages[messages.length - 1]?.role === "user") {
    const count = await countQuestion(env, session);
    if (count instanceof Response) return count;
    counted.undo = count ?? undefined;
  }
  // Older app versions can't show pages to the AI.
  const canView = Array.isArray(body.features) && body.features.includes("view_page");
  // Apps that send back the model's reasoning within a question get the
  // model's thinking mode: slower, but it checks its answer much better.
  const canReason = Array.isArray(body.features) && body.features.includes("reasoning");
  const canRead = Array.isArray(body.features) && body.features.includes("read_page");
  const hasPictures = messages.some(
    (m) => Array.isArray(m.content) && m.content.some((part) => part?.type === "image_url"),
  );
  const manuals = Array.isArray(body.manuals)
    ? body.manuals.filter((m): m is string => typeof m === "string").slice(0, 200)
    : [];
  const context = manuals.length
    ? `Manuals in the app (all can be searched; pass unit when the question is about one unit model, so only its manuals are searched):\n${manuals.join("\n")}`
    : "The app has no manual list yet (it has not reached the server), so search_manuals finds nothing. Tell the user to connect to the internet and open the Home tab first.";

  // MODEL is a list tried in order: when one model is full, out of credit
  // or retired, the same request goes to the next one. "deepseek:<model>"
  // goes to DeepSeek; a bare name goes to API_URL (Groq). Entries whose key
  // is not set are skipped.
  // Only models that can see pictures get a conversation that has some.
  const models = (hasPictures ? env.VISION_MODEL : env.MODEL)
    .split(",")
    .map((m) => m.trim())
    .filter(Boolean);
  // The app's last round for a question: no more tools, answer now.
  const final = body.final === true;
  const system =
    `${canView ? `${SYSTEM}\n\n${VIEW_INSTRUCTIONS}` : SYSTEM}\n\n${canRead ? `${READ_INSTRUCTIONS}\n\n` : ""}${WEB_INSTRUCTIONS}` +
    (final
      ? "\n\nNo more searches are possible for this question. Answer now from the pages already found (cite them) and your knowledge, marked as general; say briefly what the mechanic should still check in the manual."
      : "");
  const appTools = [SEARCH_TOOL, ...(canRead ? [READ_TOOL] : []), ...(canView ? [VIEW_TOOL] : [])];
  const lastUser = messages.map((m) => m.role).lastIndexOf("user");
  const fallbackRoundInQuestion = messages
    .slice(lastUser + 1)
    .some((m) => m.role === "assistant" && !m.reasoning_content);
  let lastStatus = 0;
  let rateLimited = false;
  let keyRejected = false;
  // DeepSeek answering "too busy" (503) is a different story from Groq's
  // free tier being full, and the mechanic should hear which one it was.
  let deepseekBusy = false;
  models: for (const entry of models) {
    const deepseek = entry.startsWith("deepseek:");
    const model = deepseek ? entry.slice("deepseek:".length) : entry;
    const key = deepseek ? env.DEEPSEEK_API_KEY : env.GROQ_API_KEY;
    if (!key) continue;
    const url = deepseek ? DEEPSEEK_URL : env.API_URL;
    // DeepSeek's thinking mode wants its reasoning sent back on every tool
    // round of a question: apps that keep it say so with "reasoning", older
    // ones get it turned off. Other providers may reject the field.
    // A round of this question answered by a fallback model carries no
    // reasoning, and thinking mode rejects that (400), so such a question
    // goes on without thinking.
    const thinking = deepseek && canReason && !fallbackRoundInQuestion;
    let turns: unknown[] = final
      ? flattenToolRounds(messages)
      : deepseek
        ? messages
        : messages.map(({ reasoning_content: _, ...m }) => m);
    // web_search runs here, not in the app: its rounds are added to the
    // request and the model is asked again.
    let webSearches = 0;
    const webNotes: string[] = [];
    // DeepSeek's "too busy" usually clears within seconds, and its answers
    // are better than the free fallback's, so it gets asked again first.
    let busyRetries = 0;
    let dsmlRetried = false;
    for (let round = 0; ; round++) {
      let upstream: Response;
      try {
        upstream = await fetch(url, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
          body: JSON.stringify({
            model,
            messages: [{ role: "system", content: `${system}\n\n${context}` }, ...turns],
            ...(final
              ? {}
              : { tools: webSearches < MAX_WEB_SEARCHES ? [...appTools, WEB_TOOL] : appTools, tool_choice: "auto" }),
            // Thinking ignores temperature, and its reasoning counts
            // against max_tokens.
            ...(thinking ? { max_tokens: 8192 } : { temperature: 0.2, max_tokens: 2048 }),
            ...(deepseek ? { thinking: { type: thinking ? "enabled" : "disabled" } } : {}),
            // Less hidden reasoning means fewer tokens against the limit.
            ...(model.startsWith("openai/gpt-oss") ? { reasoning_effort: "low" } : {}),
          }),
        });
      } catch (e) {
        console.log("model unreachable", entry, String(e));
        lastStatus = 502;
        continue models;
      }
      const data = (await upstream.json().catch(() => null)) as {
        choices?: { message?: Record<string, unknown>; finish_reason?: string }[];
        error?: { message?: string; code?: string };
      } | null;
      const choice = data?.choices?.[0];
      if (upstream.ok && choice?.message) {
        const message = choice.message;
        if (hasDsml(message.content)) {
          const text = stripDsml(message.content as string);
          console.log("tool-call markup in answer", entry, final, text.length);
          if (!text && !dsmlRetried) {
            dsmlRetried = true;
            turns = [
              ...turns,
              {
                role: "user",
                content:
                  "Jawab sekarang dengan teks biasa dari halaman yang sudah ditemukan dan pengetahuanmu, tanpa memanggil alat. (Answer now in plain text, no tool calls.)",
              },
            ];
            round--;
            continue;
          }
          message.content =
            text ||
            "Maaf, jawabannya gagal disusun. Coba tanyakan lagi dengan kalimat yang sedikit berbeda.";
        }
        const calls = Array.isArray(message.tool_calls) ? (message.tool_calls as ToolCall[]) : [];
        const web = calls.filter((c) => c.function?.name === "web_search");
        const others = calls.filter((c) => c.function?.name !== "web_search");
        // A model that keeps asking for the web after its searches are
        // used up gets no more rounds.
        if (web.length === 0 || others.length > 0 || round > MAX_WEB_SEARCHES) {
          if (others.length === 0) {
            const { tool_calls: _, ...answer } = message;
            return json({ message: answer, finish_reason: choice.finish_reason, model, web: webSearches });
          }
          // The app runs the other tools but does not keep the web rounds,
          // so what the web said rides along as this message's text (the
          // app keeps it in the conversation but does not show it).
          const notes = webNotes.length
            ? `Notes from my web search for this question:\n${webNotes.join("\n\n")}`
            : "";
          const content = [typeof message.content === "string" ? message.content : "", notes]
            .filter(Boolean)
            .join("\n\n");
          return json({ message: { ...message, content, tool_calls: others }, finish_reason: choice.finish_reason, model, web: webSearches });
        }
        const results = await Promise.all(
          web.map((call) => {
            let query = "";
            try {
              query = String((JSON.parse(call.function?.arguments ?? "{}") as { query?: unknown }).query ?? "").trim();
            } catch {
              // An unreadable call gets an empty query.
            }
            if (!query) return Promise.resolve("Empty query.");
            if (webSearches++ >= MAX_WEB_SEARCHES) {
              return Promise.resolve("No more web searches for this question. Answer with what you have.");
            }
            return webSearch(query, env).then((text) => {
              webNotes.push(`Web search "${query}":\n${text}`);
              return text;
            });
          }),
        );
        turns = [
          ...turns,
          { ...message, content: message.content ?? "" },
          ...web.map((call, i) => ({ role: "tool", tool_call_id: call.id, content: results[i] })),
        ];
        continue;
      }
      lastStatus = upstream.status;
      if (deepseek && [429, 500, 502, 503].includes(upstream.status)) {
        deepseekBusy = true;
        if (busyRetries < DEEPSEEK_BUSY_RETRIES) {
          console.log("deepseek busy, retrying", upstream.status, data?.error?.message);
          await new Promise((resolve) => setTimeout(resolve, 1500 * ++busyRetries));
          round--;
          continue;
        }
      }
      if (upstream.status === 429 || upstream.status === 413) rateLimited = true;
      if (upstream.status === 401 || upstream.status === 403) keyRejected = true;
      console.log("model failed", entry, upstream.status, data?.error?.code, data?.error?.message);
      // 429 and 413 are rate limits, 402 is no credit left, 401/403 a bad key
      // for that provider; 404 and 400 can mean a retired model.
      if (![400, 401, 402, 403, 404, 413, 422, 429, 498, 500, 502, 503].includes(upstream.status)) break models;
      continue models;
    }
  }
  if (keyRejected && !rateLimited) {
    return json({ error: "server_key", message: "Kunci API di server AI tidak valid. Hubungi admin." }, 502);
  }
  if (deepseekBusy) {
    return json(
      { error: "busy", message: "Server DeepSeek sedang sibuk dan AI cadangan juga penuh. Coba lagi sebentar lagi." },
      503,
    );
  }
  if (rateLimited) {
    return json({ error: "busy", message: "Batas pemakaian AI gratis sedang penuh. Coba lagi dalam 1 menit." }, 429);
  }
  return json(
    { error: "upstream", message: `Layanan AI sedang bermasalah (${lastStatus}). Coba lagi nanti.` },
    502,
  );
}
