"""Checks the Daily Inspection secrets against the Apps Script Web App
without printing the secret code: only its shape and the robot's answer."""
import json, os, urllib.request

url = os.environ.get("URL", "")
key = os.environ.get("KEY", "")

def describe(name, v):
    t = v.strip()
    print(f"{name}: length {len(v)}, after trim {len(t)}")
    q = ("'", '"')
    print("  starts/ends with quote:", t[:1] in q, t[-1:] in q)
    print("  has space inside:", " " in t, " has quote inside:", any(c in t for c in q))
    print("  non-ASCII chars:", sum(1 for c in t if ord(c) > 126), " newline:", "\n" in v)

describe("SHEET_SCRIPT_KEY", key)
u = url.strip()
print(f"SHEET_SCRIPT_URL: length {len(url)}, ends with /exec: {u.endswith('/exec')}, "
      f"has spaces: {u != url}, deployment id: {u.split('/s/')[-1].split('/')[0][:8]}...{u.split('/s/')[-1].split('/')[0][-6:]}")

def post(k):
    body = json.dumps({"key": k, "op": "read", "ranges": ["'INSPECTION TRACK OPEN 2026'!T3"]}).encode()
    req = urllib.request.Request(u, data=body, headers={"content-type": "text/plain;charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, r.read().decode()[:300]
    except Exception as e:
        return "ERR", str(e)[:300]

try:
    with urllib.request.urlopen(u, timeout=40) as r:
        print("GET:", r.status, r.read().decode()[:200])
except Exception as e:
    print("GET failed:", e)

print("POST with the secret as is (trimmed):", post(key.strip()))
stripped = key.strip().strip("'\"").strip()
if stripped != key.strip():
    print("POST without the quotes around it:", post(stripped))
print("POST with a wrong code (should be 'Kode rahasia salah'):", post("salah-sengaja"))
