// Google Sheets for Daily Inspection (inspection.ts), as the "robot": a
// Google Cloud service account whose JSON key is the Worker secret
// GOOGLE_SERVICE_ACCOUNT. The sheet is open to anyone with its link, but
// Google's API still needs an account to write; adding the robot's e-mail
// (client_email in the key) as an editor of the sheet keeps it working if
// the link sharing is ever turned off.

export type ServiceAccount = { client_email: string; private_key: string };

/// What inspection.ts needs from a spreadsheet; a fake in the tests.
export interface Sheets {
  /// The formatted values of each range (as the sheet shows them), one
  /// list of rows per range; missing trailing cells and rows are left out.
  read(ranges: string[]): Promise<string[][][]>;
  /// Writes each range as if typed into the sheet (formulas and dates are
  /// read the way the sheet reads typing).
  write(data: { range: string; values: string[][] }[]): Promise<void>;
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
    async write(data) {
      await call(`/values:batchUpdate`, {
        method: "POST",
        body: JSON.stringify({ valueInputOption: "USER_ENTERED", data }),
      });
    },
  };
}
