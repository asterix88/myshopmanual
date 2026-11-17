// Google Sheets for Daily Inspection (inspection.ts). Google wants an
// account for writing, even on a sheet anyone with the link may edit, so
// the Worker goes through one of two "robots":
// - appsScriptSheets: a Web App made from the sheet's own Apps Script
//   (tools/daily-inspection.gs), running as one Gmail account; the Worker
//   secrets SHEET_SCRIPT_URL and SHEET_SCRIPT_KEY. Needs no Google Cloud
//   project and no credit card. Used now.
// - googleSheets: a Google Cloud service account (secret
//   GOOGLE_SERVICE_ACCOUNT, its JSON key), when one is ever made.
// Either account should be an editor of the sheet, so it keeps working if
// the link sharing is turned off.

export type ServiceAccount = { client_email: string; private_key: string };

/// What inspection.ts needs from a spreadsheet; a fake in the tests.
export interface Sheets {
  /// The formatted values of each range (as the sheet shows them), one
  /// list of rows per range; missing trailing cells and rows are left out.
  read(ranges: string[]): Promise<string[][][]>;
  /// Writes each range as if typed into the sheet (formulas and dates are
  /// read the way the sheet reads typing). With [mustBeEmpty], nothing is
  /// written (SheetsError 409) when one of those ranges has a value.
  write(data: { range: string; values: string[][] }[], mustBeEmpty?: string[]): Promise<void>;
}

export class SheetsError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const SCOPE = "https://www.googleapis.com/auth/spreadsheets";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const API = "https://sheets.googleapis.com/v4/spreadsheets";

const enc = new TextEncoder();
const b64url = (bytes: Uint8Array | string) => {
  const b = typeof bytes === "string" ? enc.encode(bytes) : bytes;
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

export function parseServiceAccount(json: string | undefined): ServiceAccount | null {
  if (!json) return null;
  try {
    const a = JSON.parse(json) as Partial<ServiceAccount>;
    return a.client_email && a.private_key ? { client_email: a.client_email, private_key: a.private_key } : null;
  } catch {
    return null;
  }
}

async function signingKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

// One access token per Worker instance, swapped a few minutes before it
// runs out (Google gives an hour).
let cached: { email: string; token: string; until: number } | null = null;

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.email === account.client_email && cached.until > now) return cached.token;
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(
    JSON.stringify({ iss: account.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600 }),
  );
  const key = await signingKey(account.private_key);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(`${head}.${claims}`)));
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer")}&assertion=${head}.${claims}.${b64url(sig)}`,
    signal: AbortSignal.timeout(15_000),
  });
  const data = (await response.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error_description?: string };
  if (!response.ok || !data.access_token) {
    throw new SheetsError(502, `Login robot Google gagal: ${data.error_description ?? response.status}`);
  }
  cached = { email: account.client_email, token: data.access_token, until: now + (data.expires_in ?? 3600) - 300 };
  return data.access_token;
}

/// The real spreadsheet [id], through Google's Sheets API.
export function googleSheets(account: ServiceAccount, id: string): Sheets {
  async function call(path: string, init?: RequestInit): Promise<unknown> {
    const token = await accessToken(account);
    const response = await fetch(`${API}/${id}${path}`, {
      ...init,
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      signal: AbortSignal.timeout(20_000),
    });
    const data = (await response.json().catch(() => ({}))) as { error?: { message?: string } };
    if (!response.ok) {
      // 403/404: the robot may no longer open the sheet (sharing changed).
      throw new SheetsError(response.status, data.error?.message ?? `Google Sheets ${response.status}`);
    }
    return data;
  }
  return {
    async read(ranges) {
      const q = ranges.map((r) => `ranges=${encodeURIComponent(r)}`).join("&");
      const data = (await call(`/values:batchGet?${q}&valueRenderOption=FORMATTED_VALUE`)) as {
        valueRanges?: { values?: unknown[][] }[];
      };
      return (data.valueRanges ?? []).map((v) => (v.values ?? []).map((row) => row.map((c) => String(c ?? ""))));
    },
    async write(data, mustBeEmpty) {
      if (mustBeEmpty?.length) {
        const got = await this.read(mustBeEmpty);
        if (got.some((rows) => rows.some((r) => r.some((c) => c.trim() !== "")))) {
          throw new SheetsError(409, "Baris sudah terisi.");
        }
      }
      await call(`/values:batchUpdate`, {
        method: "POST",
        body: JSON.stringify({ valueInputOption: "USER_ENTERED", data }),
      });
    },
  };
}

/// The sheet through its Apps Script Web App (tools/daily-inspection.gs).
/// The script answers every call with HTTP 200 and {error} on failure.
export function appsScriptSheets(url: string, key: string): Sheets {
  async function call(body: Record<string, unknown>): Promise<Record<string, unknown>> {
    let response: Response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: { "content-type": "text/plain;charset=utf-8" },
        body: JSON.stringify({ ...body, key }),
        redirect: "follow",
        signal: AbortSignal.timeout(30_000),
      });
    } catch (e) {
      throw new SheetsError(502, `Apps Script tidak menjawab (${String(e)}).`);
    }
    const text = await response.text();
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      // An HTML page: the Web App is not deployed for "Anyone", or removed.
      throw new SheetsError(response.status === 404 ? 404 : 403, "Web App Apps Script tidak bisa dibuka (cek Deploy: akses Anyone).");
    }
    if (data.error) {
      const status = data.error === "forbidden" ? 403 : data.error === "taken" ? 409 : data.error === "range" ? 400 : 502;
      throw new SheetsError(status, String(data.message ?? data.error));
    }
    return data;
  }
  return {
    async read(ranges) {
      const data = await call({ op: "read", ranges });
      return ((data.values as unknown[][][] | undefined) ?? []).map((rows) =>
        rows.map((row) => row.map((c) => String(c ?? ""))),
      );
    },
    async write(data, mustBeEmpty) {
      await call({ op: "write", data, guard: mustBeEmpty ?? [] });
    },
  };
}
