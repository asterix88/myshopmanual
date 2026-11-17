// Cleaning and grouping automatic error reports (see errors.ts). No
// imports, so the tests can run it directly.

const MAX_ITEMS = 20;
const MAX_MESSAGE = 500;
const MAX_STACK = 4000;

/// One kind of problem on one phone: how often it happened and when.
export type ErrorItem = {
  kind: string; // "error" (in the app) or Android's reason: CRASH, CRASH_NATIVE, ANR, ...
  message: string;
  stack: string;
  count: number;
  first: number;
  last: number;
};

export type ErrorReport = {
  at: number;
  nrp: string;
  name: string;
  app: string;
  model: string;
  items: ErrorItem[];
};

/// The same problem from many phones and versions, for the admin list.
export type ErrorGroup = {
  kind: string;
  message: string;
  stack: string;
  count: number;
  phones: number;
  people: string[];
  apps: string[];
  first: number;
  last: number;
};

export const text = (value: unknown, max: number) => (typeof value === "string" ? value.slice(0, max) : "");
const time = (value: unknown, fallback: number) =>
  typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.min(value, fallback) : fallback;

/// Keeps what makes sense from a phone's list; at most MAX_ITEMS.
export function cleanItems(raw: unknown, now = Date.now()): ErrorItem[] {
  if (!Array.isArray(raw)) return [];
  const items: ErrorItem[] = [];
  for (const r of raw.slice(0, MAX_ITEMS)) {
    if (!r || typeof r !== "object") continue;
    const o = r as Record<string, unknown>;
    const message = text(o.message, MAX_MESSAGE).trim();
    if (!message) continue;
    const kind = text(o.kind, 40).trim() || "error";
    const last = time(o.last, now);
    items.push({
      kind,
      message,
      stack: text(o.stack, MAX_STACK),
      count: Math.max(1, Math.min(10000, Math.floor(Number(o.count) || 1))),
      first: Math.min(time(o.first, last), last),
      last,
    });
  }
  return items;
}

/// What makes two messages the same problem: the kind and the message with
/// numbers left out (page 12 and page 13 are one problem).
export function signature(kind: string, message: string): string {
  return `${kind}|${message.replace(/\d+/g, "#").replace(/\s+/g, " ").trim().slice(0, 200)}`;
}

/// Groups reports by problem, the most recent problem first.
export function groupReports(reports: ErrorReport[]): ErrorGroup[] {
  const groups = new Map<string, ErrorGroup & { _phones: Set<string> }>();
  for (const r of reports) {
    for (const item of r.items) {
      const key = signature(item.kind, item.message);
      let g = groups.get(key);
      if (!g) {
        g = { ...item, phones: 0, people: [], apps: [], _phones: new Set() };
        groups.set(key, g);
      } else {
        g.count += item.count;
        g.first = Math.min(g.first, item.first);
        if (item.last > g.last) {
          g.last = item.last;
          g.message = item.message;
          g.stack = item.stack;
        }
      }
      g._phones.add(`${r.nrp}|${r.model}`);
      const who = r.name ? `${r.name} (${r.nrp})` : r.nrp;
      if (who && !g.people.includes(who)) g.people.push(who);
      if (r.app && !g.apps.includes(r.app)) g.apps.push(r.app);
    }
  }
  return [...groups.values()]
    .map(({ _phones, ...g }) => ({ ...g, phones: _phones.size }))
    .sort((a, b) => b.last - a.last);
}

