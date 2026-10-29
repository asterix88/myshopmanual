// node --experimental-strip-types --test test/  (no Cloudflare needed)
import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanSections, filterCatalog, sectionMap, sees, unitOfKey } from "../src/sections.ts";

const catalog = {
  schema: 1,
  units: [
    { id: "PC210" }, // built before sections: TRACK
    { id: "D85", section: "TRACK" },
    { id: "HD785-7", section: "WHEEL" },
    { id: "PANDUAN MLU", section: "SEMUA" },
  ],
};
const ids = (c) => c.units.map((u) => u.id);

test("a Track NRP sees Track and SEMUA", () => {
  assert.deepEqual(ids(filterCatalog(catalog, ["TRACK"])), ["PC210", "D85", "PANDUAN MLU"]);
});

test("a Wheel NRP sees Wheel and SEMUA only", () => {
  const wheel = filterCatalog(catalog, ["WHEEL"]);
  assert.deepEqual(ids(wheel), ["HD785-7", "PANDUAN MLU"]);
  assert.deepEqual(wheel.hidden_units, ["PC210", "D85"]);
});

test("an NRP with two sections sees both", () => {
  assert.deepEqual(ids(filterCatalog(catalog, ["TRACK", "WHEEL"])), ids(catalog));
});

test("admins see everything", () => {
  assert.equal(filterCatalog(catalog, null), catalog);
});

test("files are checked by their unit", () => {
  const map = sectionMap(catalog);
  assert.equal(unitOfKey("units/HD785-7/sm.pdf"), "HD785-7");
  assert.equal(unitOfKey("catalog.json"), null);
  assert.equal(sees(["TRACK"], map.get("HD785-7")), false);
  assert.equal(sees(["TRACK"], map.get("PC210")), true);
  assert.equal(sees(["WHEEL"], map.get("PANDUAN MLU")), true);
});

test("import rows", () => {
  assert.deepEqual(cleanSections([" track", "WHEEL", "Track"]), ["TRACK", "WHEEL"]);
  assert.equal(cleanSections(undefined), null);
  assert.equal(cleanSections([]), null);
});
