// Serves the R2 bucket (catalog, manuals, search indexes) on
// files.mymanual.my.id to logged-in phones only, so the bucket itself can be
// closed to the public.
//
// Manuals are read in small pieces (HTTP Range). The first request for a
// manual copies the whole file into Cloudflare's cache near the reader, the
// way the public bucket address did, so later pieces come from there.

import { allowedOf, requireSession, type AuthEnv } from "./auth";
import { filterCatalog, sectionMap, sees, unitOfKey, type Allowed, type Catalog } from "./sections";

export interface FilesEnv extends AuthEnv {
  BUCKET: R2Bucket;
}

type Range = { offset: number; length: number };

/// The one byte range asked for, null for the whole file, "bad" when it
/// cannot be served.
function parseRange(header: string | null, size: number): Range | null | "bad" {
  if (!header) return null;
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m || (m[1] === "" && m[2] === "")) return "bad";
  if (m[1] === "") {
    const n = Math.min(Number(m[2]), size);
    return n > 0 ? { offset: size - n, length: n } : "bad";
  }
  const start = Number(m[1]);
  const end = m[2] === "" ? size - 1 : Math.min(Number(m[2]), size - 1);
  if (start >= size || end < start) return "bad";
  return { offset: start, length: end - start + 1 };
}

const filling = new Set<string>();

// Section of every unit, read from catalog.json and kept for a minute per
// Worker instance, so a file request does not read the catalog each time.
let sections: { at: number; map: Map<string, string> } | null = null;

async function readCatalog(env: FilesEnv): Promise<Catalog | null> {
  const object = await env.BUCKET.get("catalog.json");
  if (!object) return null;
  const catalog = (await object.json()) as Catalog;
  sections = { at: Date.now(), map: sectionMap(catalog) };
  return catalog;
}

async function unitAllowed(env: FilesEnv, unit: string, allowed: string[]): Promise<boolean> {
  if (!sections || Date.now() - sections.at > 60_000) await readCatalog(env);
  let section = sections?.map.get(unit);
  // A unit added in the last minute: read the catalog again, at most every 5 s.
  if (section === undefined && sections && Date.now() - sections.at > 5_000) {
    await readCatalog(env);
    section = sections?.map.get(unit);
  }
  return section !== undefined && sees(allowed, section);
}

async function catalogFor(env: FilesEnv, request: Request, allowed: Allowed): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
  const catalog = await readCatalog(env);
  if (!catalog) return new Response("Not found", { status: 404 });
  const text = JSON.stringify(filterCatalog(catalog, allowed));
  const headers = new Headers({
    "content-type": "application/json",
    "cache-control": "private, no-store",
    "content-length": String(new TextEncoder().encode(text).length),
  });
  return new Response(request.method === "HEAD" ? null : text, { headers });
}

const versionKey = (version: string, key: string) =>
  `https://files.mymanual.my.id/__cache/v/${version}/${encodeURIComponent(key)}`;

export async function handleFiles(request: Request, env: FilesEnv, ctx: ExecutionContext): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405 });
  }
  // update.bat warms new manuals with the admin code; phones use their session.
  const code = request.headers.get("x-admin-code");
  let allowed: Allowed = null;
  if (!(env.OWNER_CODE && code && code.trim() === env.OWNER_CODE.trim())) {
    const auth = await requireSession(env, request);
    if (auth.error) return auth.error;
    allowed = allowedOf(auth.session);
  }

  const url = new URL(request.url);
  const key = decodeURIComponent(url.pathname.slice(1));
  if (!key || key.includes("..")) return new Response("Not found", { status: 404 });
  const started = Date.now();

  // Each phone gets only its sections' units (sections.ts).
  if (key === "catalog.json") return catalogFor(env, request, allowed);
  const unit = unitOfKey(key);
  if (unit !== null && allowed !== null && !(await unitAllowed(env, unit, allowed))) {
    return new Response("Bukan section Anda", { status: 403 });
  }

  // The app names the file's version (the start of its sha256 from the
  // catalog), so a piece already in the cache is served without asking the
  // bucket first: that question alone took ~250 ms per piece, and opening
  // a page reads several pieces one after another.
  const version = url.searchParams.get("v");
  const rangeHeader = request.headers.get("range");
  if (version && /^[0-9a-f]{8,64}$/.test(version) && key !== "catalog.json" && request.method === "GET") {
    const cached = await caches.default.match(
      new Request(versionKey(version, key), { headers: rangeHeader ? { range: rangeHeader } : {} }),
    );
    if (cached && (cached.status === 206 || (cached.status === 200 && !rangeHeader))) {
      const headers = new Headers({
        "content-type": cached.headers.get("content-type") ?? "application/octet-stream",
        "accept-ranges": "bytes",
        "cache-control": "private, no-store",
        "server-timing": `cache;dur=${Date.now() - started}`,
      });
      for (const h of ["content-range", "content-length"]) {
        const v = cached.headers.get(h);
        if (v) headers.set(h, v);
      }
      return new Response(cached.body, { status: cached.status, headers });
    }
  }

  const head = await env.BUCKET.head(key);
  if (!head) return new Response("Not found", { status: 404 });

  const range = parseRange(request.headers.get("range"), head.size);
  if (range === "bad") {
    return new Response("Range not satisfiable", { status: 416, headers: { "content-range": `bytes */${head.size}` } });
  }
  const headers = new Headers({
    "content-type": head.httpMetadata?.contentType ?? "application/octet-stream",
    "accept-ranges": "bytes",
    etag: head.httpEtag,
    // Phones must not keep a copy where another login could read it.
    "cache-control": "private, no-store",
  });
  if (range) {
    headers.set("content-range", `bytes ${range.offset}-${range.offset + range.length - 1}/${head.size}`);
  }
  headers.set("content-length", String(range ? range.length : head.size));
  const status = range ? 206 : 200;
  if (request.method === "HEAD") return new Response(null, { status, headers });

  // Manuals and indexes never change under the same etag; the catalog does
  // and is always read from the bucket.
  const cacheable = key !== "catalog.json";
  const cacheKey = new Request(
    version && /^[0-9a-f]{8,64}$/.test(version)
      ? versionKey(version, key)
      : `https://files.mymanual.my.id/__cache/${encodeURIComponent(head.etag)}/${encodeURIComponent(key)}`,
  );
  if (cacheable) {
    const cached = await caches.default.match(
      new Request(cacheKey.url, { headers: range ? { range: `bytes=${range.offset}-${range.offset + range.length - 1}` } : {} }),
    );
    if (cached && cached.status === status) {
      headers.set("server-timing", `head+cache;dur=${Date.now() - started}`);
      return new Response(cached.body, { status, headers });
    }
    if (!filling.has(cacheKey.url)) {
      filling.add(cacheKey.url);
      ctx.waitUntil(
        (async () => {
          try {
            const whole = await env.BUCKET.get(key);
            if (!whole) return;
            await caches.default.put(
              cacheKey,
              new Response(whole.body, {
                headers: {
                  "content-type": headers.get("content-type")!,
                  "content-length": String(whole.size),
                  "cache-control": "public, max-age=2592000",
                },
              }),
            );
          } catch (e) {
            console.log("cache fill failed", key, String(e));
          } finally {
            filling.delete(cacheKey.url);
          }
        })(),
      );
    }
  }

  const object = await env.BUCKET.get(key, range ? { range } : {});
  if (!object) return new Response("Not found", { status: 404 });
  headers.set("server-timing", `bucket;dur=${Date.now() - started}`);
  return new Response(object.body, { status, headers });
}
