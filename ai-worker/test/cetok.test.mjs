// node --experimental-strip-types --test test/  (no Cloudflare needed)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { cetokSitesFor } from "../src/cetok.ts";

const sites = {
  TRACK: { url: "https://track.supabase.co/", key: "k1", unit: ["pc210-10mo"] },
  wheel: { url: "https://wheel.supabase.co", key: "k2", semua_lokasi: true },
  SUPPORT: { url: "", key: "" }, // not filled in yet
};

test("an NRP gets only the Cetok of its sections", () => {
  assert.deepEqual(Object.keys(cetokSitesFor(sites, ["TRACK"], false)), ["TRACK"]);
  assert.deepEqual(Object.keys(cetokSitesFor(sites, ["WHEEL"], false)), ["WHEEL"]);
  assert.deepEqual(Object.keys(cetokSitesFor(sites, ["SUPPORT"], false)), []);
});

test("admins get every filled-in section", () => {
  assert.deepEqual(Object.keys(cetokSitesFor(sites, null, false)).sort(), ["TRACK", "WHEEL"]);
});

test("entries are tidied and the location choice settled", () => {
  const out = cetokSitesFor(sites, null, false);
  assert.equal(out.TRACK.url, "https://track.supabase.co");
  assert.deepEqual(out.TRACK.unit, ["PC210-10MO"]);
  assert.equal(out.TRACK.show_all, false); // the admin's choice
  assert.equal(cetokSitesFor(sites, null, true).TRACK.show_all, true);
  assert.equal(out.WHEEL.show_all, true); // semua_lokasi wins
});

test("the repo's cetok.json is valid and has Track", () => {
  const file = JSON.parse(readFileSync(new URL("../cetok.json", import.meta.url), "utf8"));
  const out = cetokSitesFor(file, null, false);
  assert.ok(out.TRACK, "TRACK entry");
  assert.ok(out.TRACK.unit.length > 0);
});
