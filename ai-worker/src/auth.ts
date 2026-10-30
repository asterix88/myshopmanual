// Employee login: NRP + 4-digit PIN. The employee list comes from Anas's
// karyawan.xlsx (tools/upload_karyawan.py posts it to /admin/import); each
// employee is one KV entry "emp:<NRP>" whose metadata is the row the admin
// screen lists, so listing needs no extra reads.
//
// A login gives the phone a signed session token. It is valid 30 days, which
// is how long the app works offline; the server only accepts tokens issued
// in the last day, so a phone that is online swaps its token every day
// (/auth/refresh), and that swap is where a deactivated NRP is turned away.

import { DEFAULT_SECTION, cleanSections, type Allowed } from "./sections";

export interface AuthEnv {
  AUTH: KVNamespace;
  // The admin code; also lets update.bat import the employee list.
  OWNER_CODE?: string;
}

/// How long a phone works without internet after its last token swap.
export const SESSION_DAYS = 30;
/// How old a token may be when it is sent to the server.
const FRESH_SECONDS = 24 * 3600;
/// The token for choosing a PIN after logging in with the starting PIN.
const SETUP_SECONDS = 15 * 60;
export const AI_DAILY_LIMIT = 10;

// s: the employee's sections (sections.ts); missing in tokens from before
// sections, which are TRACK.
export type Session = { n: string; nm: string; a: boolean; s?: string[]; iat: number; exp: number; t?: "setup" };

/// The sections whose manuals [s] may see; null = all (admins).
export function allowedOf(s: Session): Allowed {
  return s.a ? null : s.s?.length ? s.s : [DEFAULT_SECTION];
}

type Device = { model: string; seen: number };

type Employee = {
  nrp: string;
  name: string;
  admin: boolean;
  active: boolean;
  // From the Section and Departemen columns; missing for employees
  // imported before them (TRACK, no department).
  sections?: string[];
  department?: string;
  // Set by the import when the row is missing, or by an admin in the app;
  // a row deactivated by an admin stays so even if it is still in the file.
  off_by?: "import" | "admin";
  // Hash of the current PIN; must_change while it is a starting PIN.
  pin: string;
  salt: string;
  must_change: boolean;
  // Hash of the starting PIN last read from the file, so a changed one in
  // the file resets the PIN and an unchanged one does not.
  file_pin: string;
  // Left from when wrong PINs locked the NRP for a while; now always 0.
  fails: number;
  lock_until: number;
  last_seen: number;
  devices: Record<string, Device>;
  // When the employee asked for a PIN reset on the login screen ("Lupa
  // PIN"); cleared when an admin makes a temporary PIN or dismisses it.
  reset_at?: number;
};

/// What the admin screen lists, kept in the KV entry's metadata.
export type Row = {
  name: string;
  admin: boolean;
  active: boolean;
  sections: string[];
  dept?: string;
  status: "new" | "active";
  seen: number;
  devices: string[];
  reset?: number;
};

const now = () => Math.floor(Date.now() / 1000);
const enc = new TextEncoder();

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromB64url(s: string): Uint8Array {
  const b = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(b, (c) => c.charCodeAt(0));
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// The signing key is made once and kept in KV, so no secret has to be set up.
// It also peppers the PIN hashes, so it must never change.
let keyCache: CryptoKey | null = null;

async function signingKey(env: AuthEnv): Promise<CryptoKey> {
  if (keyCache) return keyCache;
  let raw = await env.AUTH.get("config:key");
  if (!raw) {
    raw = b64url(crypto.getRandomValues(new Uint8Array(32)));
    await env.AUTH.put("config:key", raw);
  }
  keyCache = await crypto.subtle.importKey("raw", fromB64url(raw), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
    "verify",
  ]);
  return keyCache;
}

async function sign(env: AuthEnv, payload: Session): Promise<string> {
  const body = b64url(enc.encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign("HMAC", await signingKey(env), enc.encode(body));
  return `${body}.${b64url(new Uint8Array(sig))}`;
}

/// The token's content if its signature is right and it has not run out.
export async function verify(env: AuthEnv, token: string | null): Promise<Session | null> {
  if (!token) return null;
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;
  try {
    const ok = await crypto.subtle.verify("HMAC", await signingKey(env), fromB64url(sig), enc.encode(body));
    if (!ok) return null;
    const s = JSON.parse(new TextDecoder().decode(fromB64url(body))) as Session;
    return s.exp > now() ? s : null;
  } catch {
    return null;
  }
}

export const SESSION_HEADER = "x-mymanual-session";

/// The caller's session for files, chat and admin calls: null with the
/// response to send when there is none or it needs swapping first.
export async function requireSession(
  env: AuthEnv,
  request: Request,
): Promise<{ session: Session; error?: undefined } | { session?: undefined; error: Response }> {
  const s = await verify(env, request.headers.get(SESSION_HEADER));
  if (!s || s.t === "setup") {
    return { error: json({ error: "login", message: "Silakan masuk lagi dengan NRP dan PIN." }, 401) };
  }
  if (s.iat < now() - FRESH_SECONDS) {
    return { error: json({ error: "refresh", message: "Sesi perlu diperbarui." }, 401) };
  }
  return { session: s };
}

async function pinHash(env: AuthEnv, salt: string, pin: string): Promise<string> {
  return hex(await crypto.subtle.sign("HMAC", await signingKey(env), enc.encode(`${salt}:${pin}`)));
}

// PINs have 4 digits; the app's PIN boxes take no more, so a 6-digit PIN
// set before 13 Oct 2026 needs a new one from an admin.
const PIN_LENGTH = 4;
const validPin = (pin: string) => new RegExp(`^\\d{${PIN_LENGTH}}$`).test(pin);
const cleanNrp = (nrp: unknown) => String(nrp ?? "").trim().toUpperCase();

function rowOf(e: Employee): Row {
  return {
    name: e.name,
    admin: e.admin,
    active: e.active,
    sections: sectionsOf(e),
    ...(e.department ? { dept: e.department } : {}),
    status: e.must_change && Object.keys(e.devices).length === 0 ? "new" : "active",
    seen: e.last_seen,
    devices: Object.values(e.devices).map((d) => d.model).slice(0, 8),
    ...(e.reset_at ? { reset: e.reset_at } : {}),
  };
}

const sectionsOf = (e: Employee) => (e.sections?.length ? e.sections : [DEFAULT_SECTION]);

async function load(env: AuthEnv, nrp: string): Promise<Employee | null> {
  return (await env.AUTH.get<Employee>(`emp:${nrp}`, "json")) ?? null;
}

async function save(env: AuthEnv, e: Employee): Promise<void> {
  await env.AUTH.put(`emp:${e.nrp}`, JSON.stringify(e), { metadata: rowOf(e) });
}

async function issue(env: AuthEnv, e: Employee): Promise<Response> {
  const iat = now();
  const sections = sectionsOf(e);
  const token = await sign(env, { n: e.nrp, nm: e.name, a: e.admin, s: sections, iat, exp: iat + SESSION_DAYS * 86400 });
  return json({
    status: "ok", token, nrp: e.nrp, name: e.name, admin: e.admin, sections,
    ...(e.department ? { department: e.department } : {}), iat, exp: iat + SESSION_DAYS * 86400,
  });
}

/// Remembers the phone and when it was last online; written at most once a
/// day per phone to stay inside KV's free write allowance.
function touch(e: Employee, device: unknown): boolean {
  const d = (device ?? {}) as { id?: unknown; model?: unknown };
  const id = String(d.id ?? "").slice(0, 64);
  const t = now();
  let changed = false;
  if (t - e.last_seen > 86400) {
    e.last_seen = t;
    changed = true;
  }
  if (id) {
    const old = e.devices[id];
    if (!old || t - old.seen > 86400) {
      e.devices[id] = { model: String(d.model ?? "").slice(0, 60) || "HP", seen: t };
      // Phones not seen for 60 days are forgotten.
      for (const [k, v] of Object.entries(e.devices)) if (t - v.seen > 60 * 86400) delete e.devices[k];
      changed = true;
    }
  }
  return changed;
}

const notFound = () => json({ error: "unknown", message: "NRP tidak terdaftar." }, 403);
const inactive = () => json({ error: "inactive", message: "NRP ini sudah tidak aktif, hubungi admin." }, 403);

async function body(request: Request): Promise<Record<string, unknown> | null> {
  try {
    return (await request.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/// Handles /auth/* and /admin/*; null for other paths.
export async function handleAuth(request: Request, env: AuthEnv, path: string): Promise<Response | null> {
  if (request.method !== "POST") return null;
  switch (path) {
    case "/auth/login":
      return login(request, env);
    case "/auth/pin":
      return setPin(request, env);
    case "/auth/forgot":
      return forgot(request, env);
    case "/auth/refresh":
      return refresh(request, env);
    case "/app/config":
      return appConfig(request, env);
    case "/admin/import":
      return importList(request, env);
    case "/admin/config":
      return setAppConfig(request, env);
    case "/admin/employees":
    case "/admin/pin":
    case "/admin/active":
    case "/admin/dismiss":
      return admin(request, env, path);
  }
  return null;
}

async function login(request: Request, env: AuthEnv): Promise<Response> {
  const b = await body(request);
  if (!b) return json({ error: "bad_request" }, 400);
  const nrp = cleanNrp(b.nrp);
  const pin = String(b.pin ?? "").trim();
  const e = nrp ? await load(env, nrp) : null;
  if (!e) return notFound();
  if (!e.active) return inactive();
  const t = now();
  // No lockout after wrong PINs (Anas's choice): the mechanic just tries
  // again, or asks an admin for a temporary PIN.
  if ((await pinHash(env, e.salt, pin)) !== e.pin) {
    return json({ error: "pin", message: "PIN salah." }, 403);
  }
  // Clears counters left by builds that still locked after wrong PINs, and
  // a reset request the employee no longer needs.
  const changed = e.fails > 0 || e.lock_until > 0 || e.reset_at !== undefined;
  e.fails = 0;
  e.lock_until = 0;
  delete e.reset_at;
  if (e.must_change) {
    if (changed) await save(env, e);
    const setup = await sign(env, { n: e.nrp, nm: e.name, a: e.admin, iat: t, exp: t + SETUP_SECONDS, t: "setup" });
    return json({ status: "set_pin", setup, name: e.name });
  }
  if (touch(e, b.device) || changed) await save(env, e);
  return issue(env, e);
}

/// "Lupa PIN": puts the NRP on the admins' list of reset requests. It
/// changes nothing else; an admin still has to make a temporary PIN.
async function forgot(request: Request, env: AuthEnv): Promise<Response> {
  const b = await body(request);
  if (!b) return json({ error: "bad_request" }, 400);
  const nrp = cleanNrp(b.nrp);
  const e = nrp ? await load(env, nrp) : null;
  if (!e) return notFound();
  if (!e.active) return inactive();
  if (!e.reset_at) {
    e.reset_at = now();
    await save(env, e);
  }
  return json({ ok: true });
}

async function setPin(request: Request, env: AuthEnv): Promise<Response> {
  const b = await body(request);
  if (!b) return json({ error: "bad_request" }, 400);
  const s = await verify(env, String(b.setup ?? ""));
  if (!s || s.t !== "setup") {
    return json({ error: "expired", message: "Waktu habis. Silakan masuk lagi dengan PIN awal." }, 401);
  }
  const pin = String(b.pin ?? "").trim();
  if (!validPin(pin)) return json({ error: "pin_format", message: `PIN harus ${PIN_LENGTH} angka.` }, 400);
  const e = await load(env, s.n);
  if (!e) return notFound();
  if (!e.active) return inactive();
  e.salt = b64url(crypto.getRandomValues(new Uint8Array(12)));
  e.pin = await pinHash(env, e.salt, pin);
  e.must_change = false;
  touch(e, b.device);
  await save(env, e);
  return issue(env, e);
}

async function refresh(request: Request, env: AuthEnv): Promise<Response> {
  const b = (await body(request)) ?? {};
  const s = await verify(env, request.headers.get(SESSION_HEADER));
  if (!s || s.t === "setup") return json({ error: "login", message: "Silakan masuk lagi dengan NRP dan PIN." }, 401);
  const e = await load(env, s.n);
  if (!e) return notFound();
  if (!e.active) return inactive();
  if (touch(e, b.device)) await save(env, e);
  return issue(env, e);
}

/// Settings an admin changes in the app that every phone follows without an
/// app update. cetok_all: Cetok Online shows every location (like
/// stock-spareparts.vercel.app) instead of hiding some (like cetok-online).
type AppConfig = { cetok_all: boolean };

async function readConfig(env: AuthEnv): Promise<AppConfig> {
  const saved = (await env.AUTH.get<Partial<AppConfig>>("config:app", "json")) ?? {};
  return { cetok_all: saved.cetok_all === true };
}

async function appConfig(request: Request, env: AuthEnv): Promise<Response> {
  const auth = await requireSession(env, request);
  if (auth.error) return auth.error;
  return json(await readConfig(env));
}

async function setAppConfig(request: Request, env: AuthEnv): Promise<Response> {
  const auth = await requireSession(env, request);
  if (auth.error) return auth.error;
  const me = await load(env, auth.session.n);
  if (!me || !me.active || !me.admin) return json({ error: "forbidden", message: "Khusus admin." }, 403);
  const b = (await body(request)) ?? {};
  const config = await readConfig(env);
  if (typeof b.cetok_all === "boolean") config.cetok_all = b.cetok_all;
  await env.AUTH.put("config:app", JSON.stringify(config));
  return json(config);
}

/// Replaces the employee list with the one in Anas's file.
async function importList(request: Request, env: AuthEnv): Promise<Response> {
  const code = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!env.OWNER_CODE || code !== env.OWNER_CODE.trim()) {
    return json({ error: "unauthorized", message: "Kode admin salah." }, 401);
  }
  const b = await body(request);
  const list = Array.isArray(b?.employees) ? (b!.employees as Record<string, unknown>[]) : null;
  if (!list) return json({ error: "bad_request" }, 400);
  type Imported = { name: string; pin: string; admin: boolean; sections: string[] | null; department: string | null };
  const rows = new Map<string, Imported>();
  const problems: string[] = [];
  for (const r of list) {
    const nrp = cleanNrp(r.nrp);
    const pin = String(r.pin ?? "").trim();
    if (!nrp) continue;
    if (!validPin(pin)) {
      problems.push(`${nrp}: PIN awal harus ${PIN_LENGTH} angka`);
      continue;
    }
    rows.set(nrp, {
      name: String(r.name ?? "").trim() || nrp, pin, admin: r.admin === true,
      // null: an upload_karyawan.py from before these columns; keep what is saved.
      sections: cleanSections(r.sections),
      department: typeof r.department === "string" ? r.department.trim().toUpperCase() : null,
    });
  }
  if (rows.size === 0) return json({ error: "empty", message: "Daftar karyawan kosong.", problems }, 400);
  if (![...rows.values()].some((r) => r.admin)) {
    // Without an admin nobody could manage the list from the app.
    return json({ error: "no_admin", message: "Tandai minimal satu karyawan sebagai admin.", problems }, 400);
  }

  const existing = new Set<string>();
  let cursor: string | undefined;
  do {
    const page: KVNamespaceListResult<unknown, string> = await env.AUTH.list({ prefix: "emp:", cursor });
    for (const k of page.keys) existing.add(k.name.slice(4));
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);

  const result = { added: 0, updated: 0, pin_reset: 0, deactivated: 0, reactivated: 0, unchanged: 0, problems };
  for (const [nrp, r] of rows) {
    const e = existing.has(nrp) ? await load(env, nrp) : null;
    if (!e) {
      const salt = b64url(crypto.getRandomValues(new Uint8Array(12)));
      const hash = await pinHash(env, salt, r.pin);
      await save(env, {
        nrp, name: r.name, admin: r.admin, active: true, pin: hash, salt, must_change: true,
        ...(r.sections ? { sections: r.sections } : {}),
        ...(r.department ? { department: r.department } : {}),
        file_pin: await pinHash(env, "file", r.pin), fails: 0, lock_until: 0, last_seen: 0, devices: {},
      });
      result.added++;
      continue;
    }
    let changed = false;
    const sections = r.sections ?? e.sections;
    const department = r.department === null ? e.department : r.department || undefined;
    if (
      e.name !== r.name || e.admin !== r.admin || department !== e.department ||
      (sections ?? []).join(",") !== (e.sections ?? []).join(",")
    ) {
      e.name = r.name;
      e.admin = r.admin;
      if (sections) e.sections = sections;
      if (department) e.department = department;
      else delete e.department;
      changed = true;
      result.updated++;
    }
    const filePin = await pinHash(env, "file", r.pin);
    if (filePin !== e.file_pin) {
      e.file_pin = filePin;
      e.salt = b64url(crypto.getRandomValues(new Uint8Array(12)));
      e.pin = await pinHash(env, e.salt, r.pin);
      e.must_change = true;
      changed = true;
      result.pin_reset++;
    }
    if (!e.active && e.off_by === "import") {
      e.active = true;
      delete e.off_by;
      changed = true;
      result.reactivated++;
    }
    if (changed) await save(env, e);
    else result.unchanged++;
  }
  for (const nrp of existing) {
    if (rows.has(nrp)) continue;
    const e = await load(env, nrp);
    if (e && e.active) {
      e.active = false;
      e.off_by = "import";
      await save(env, e);
      result.deactivated++;
    }
  }
  return json({ ok: true, ...result });
}

/// Jakarta's date, for the daily nyel AI allowance.
export function today(): string {
  return new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 10);
}

/// Counts a new question for [s]: a Response when today's allowance is used
/// up, otherwise a function that takes the question back (null for admins,
/// who have no limit).
export async function countQuestion(env: AuthEnv, s: Session): Promise<Response | (() => Promise<void>) | null> {
  if (s.a) return null;
  const key = `ai:${today()}:${s.n}`;
  const asked = Number((await env.AUTH.get(key)) ?? "0");
  if (asked >= AI_DAILY_LIMIT) {
    return json(
      { error: "quota", message: `Jatah ${AI_DAILY_LIMIT} pertanyaan hari ini sudah habis. Coba lagi besok.` },
      429,
    );
  }
  const put = (n: number) => env.AUTH.put(key, String(n), { expirationTtl: 3 * 86400, metadata: { n } });
  await put(asked + 1);
  return () => put(asked);
}

/// The caller's session when it belongs to an active admin; otherwise the
/// response to send.
export async function requireAdmin(
  env: AuthEnv,
  request: Request,
): Promise<{ session: Session; error?: undefined } | { session?: undefined; error: Response }> {
  const auth = await requireSession(env, request);
  if (auth.error) return auth;
  const me = await load(env, auth.session.n);
  if (!me || !me.active || !me.admin) return { error: json({ error: "forbidden", message: "Khusus admin." }, 403) };
  return auth;
}

/// Every employee as the admin screen lists them, by NRP.
export async function employeeRows(env: AuthEnv): Promise<Map<string, Row>> {
  const rows = new Map<string, Row>();
  let cursor: string | undefined;
  do {
    const page: KVNamespaceListResult<Row, string> = await env.AUTH.list<Row>({ prefix: "emp:", cursor });
    for (const k of page.keys) if (k.metadata) rows.set(k.name.slice(4), k.metadata);
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return rows;
}

async function admin(request: Request, env: AuthEnv, path: string): Promise<Response> {
  const auth = await requireAdmin(env, request);
  if (auth.error) return auth.error;

  if (path === "/admin/employees") {
    const asked = new Map<string, number>();
    const prefix = `ai:${today()}:`;
    let cursor: string | undefined;
    do {
      const page: KVNamespaceListResult<{ n: number }, string> = await env.AUTH.list<{ n: number }>({ prefix, cursor });
      for (const k of page.keys) asked.set(k.name.slice(prefix.length), k.metadata?.n ?? 0);
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    const employees = [...(await employeeRows(env))].map(([nrp, row]) => ({ nrp, ...row, ai_today: asked.get(nrp) ?? 0 }));
    return json({ employees, ai_limit: AI_DAILY_LIMIT });
  }

  const b = await body(request);
  const e = b ? await load(env, cleanNrp(b.nrp)) : null;
  if (!e) return notFound();

  if (path === "/admin/pin") {
    const pin = String(crypto.getRandomValues(new Uint32Array(1))[0] % 10 ** PIN_LENGTH).padStart(PIN_LENGTH, "0");
    e.salt = b64url(crypto.getRandomValues(new Uint8Array(12)));
    e.pin = await pinHash(env, e.salt, pin);
    e.must_change = true;
    e.fails = 0;
    e.lock_until = 0;
    delete e.reset_at;
    await save(env, e);
    return json({ ok: true, pin });
  }

  if (path === "/admin/dismiss") {
    if (e.reset_at) {
      delete e.reset_at;
      await save(env, e);
    }
    return json({ ok: true });
  }

  // /admin/active
  const active = b!.active === true;
  if (!active && e.nrp === auth.session.n) {
    return json({ error: "self", message: "Admin tidak bisa menonaktifkan NRP-nya sendiri." }, 400);
  }
  e.active = active;
  if (active) delete e.off_by;
  else e.off_by = "admin";
  await save(env, e);
  return json({ ok: true, active });
}
