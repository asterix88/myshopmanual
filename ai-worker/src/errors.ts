import { requireSession, type AuthEnv } from "./auth";
import { cleanItems, groupReports, text, type ErrorReport } from "./error-groups";

// Automatic error reports. When something goes wrong on a phone (an error
// the app did not handle, or Android closing it: crash, native crash, not
// responding), the app keeps it in a small list and sends it here the next
// time it is online. Admins see them grouped in the app (menu ⋮ > Laporan
// error), so Anas learns about a crash without waiting for a mechanic to
// send "Laporan masalah". Kept in the AUTH KV as "err:<time>:<nrp>", for
// 90 days.

const KEEP_SECONDS = 90 * 24 * 3600;
const LIST_LIMIT = 300;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function errors(request: Request, env: AuthEnv): Promise<Response> {
  const auth = await requireSession(env, request);
  if (auth.error) return auth.error;
  const s = auth.session;

  if (request.method === "GET") {
    if (!s.a) return json({ error: "forbidden", message: "Hanya admin." }, 403);
    const keys: string[] = [];
    let cursor: string | undefined;
    do {
      const page = await env.AUTH.list({ prefix: "err:", cursor });
      keys.push(...page.keys.map((k) => k.name));
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    const newest = keys.sort().reverse().slice(0, LIST_LIMIT);
    const reports = (await Promise.all(newest.map((k) => env.AUTH.get<ErrorReport>(k, "json")))).filter(
      (r): r is ErrorReport => !!r,
    );
    return json({ groups: groupReports(reports), reports: reports.length });
  }

  if (request.method !== "POST") return json({ error: "not_found" }, 404);
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const report: ErrorReport = {
    at: Date.now(),
    nrp: s.n,
    name: s.nm,
    app: text(body.app, 40),
    model: text(body.model, 60),
    items: cleanItems(body.items),
  };
  if (report.items.length === 0) return json({ error: "bad_request" }, 400);
  const key = `err:${new Date(report.at).toISOString()}:${s.n}`;
  await env.AUTH.put(key, JSON.stringify(report), { expirationTtl: KEEP_SECONDS });
  return json({ ok: true });
}
