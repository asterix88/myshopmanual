/**
 * Daily Inspection Monitoring: the "robot" that lets the MyManual server
 * read and write this sheet. Paste this whole file into the sheet's
 * Extensions > Apps Script, put your own secret code in KEY (the same text
 * as the GitHub secret SHEET_SCRIPT_KEY), then Deploy > New deployment >
 * Web app, Execute as: Me, Who has access: Anyone. The Web app URL goes in
 * the GitHub secret SHEET_SCRIPT_URL.
 *
 * Every call needs KEY, so the URL alone gives nobody access. The server
 * (ai-worker/src/google.ts) sends:
 *   {key, op: "read",  ranges: ["'TAB'!B5:Q3000", ...]}
 *     -> {values: [rows of each range, as the sheet shows them]}
 *   {key, op: "write", data: [{range, values}], guard: [ranges]}
 *     -> {ok: true}; values are entered as if typed (formulas, dates);
 *        nothing is written ({error: "taken"}) when a guard range has a value.
 */
const KEY = 'GANTI_DENGAN_KODE_RAHASIA';

function doPost(e) {
  let req;
  try {
    req = JSON.parse(e.postData.contents);
  } catch (err) {
    return out_({ error: 'bad_request' });
  }
  if (!req || KEY === 'GANTI_DENGAN_KODE_RAHASIA' || req.key !== KEY) return out_({ error: 'forbidden', message: 'Kode rahasia salah.' });
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  try {
    if (req.op === 'read') {
      return out_({ values: (req.ranges || []).map(function (r) {
        const range = range_(ss, r, false);
        return range ? trim_(range.getDisplayValues()) : [];
      }) });
    }
    if (req.op === 'write') {
      const lock = LockService.getScriptLock();
      lock.waitLock(20000);
      try {
        const taken = (req.guard || []).some(function (r) {
          const range = range_(ss, r, false);
          return range && range.getDisplayValues().some(function (row) {
            return row.some(function (c) { return String(c).trim() !== ''; });
          });
        });
        if (taken) return out_({ error: 'taken', message: 'Baris sudah terisi.' });
        (req.data || []).forEach(function (d) { range_(ss, d.range, true).setValues(d.values); });
        SpreadsheetApp.flush();
      } finally {
        lock.releaseLock();
      }
      return out_({ ok: true });
    }
    return out_({ error: 'bad_request' });
  } catch (err) {
    const message = String(err && err.message || err);
    return out_({ error: err.name === 'RangeError' ? 'range' : 'sheet', message: message });
  }
}

/// A test from the browser: opening the Web app URL shows this.
function doGet() {
  return out_({ ok: true, sheet: SpreadsheetApp.getActiveSpreadsheet().getName() });
}

/// "'TAB'!B5:Q3000" in tab TAB. Rows past the end of the tab are left out
/// when reading (null when none is left) and added when [grow] (writing).
function range_(ss, a1, grow) {
  const m = /^(?:'((?:[^']|'')+)'|([^'!]+))!([A-Z]+)(\d+)(?::([A-Z]+)(\d+))?$/.exec(a1);
  if (!m) throw rangeError_('Range tidak dikenal: ' + a1);
  const name = m[1] !== undefined ? m[1].replace(/''/g, "'") : m[2];
  const sheet = ss.getSheetByName(name);
  if (!sheet) throw rangeError_('Tab tidak ditemukan: ' + name);
  const top = Number(m[4]);
  let bottom = m[6] ? Number(m[6]) : top;
  const max = sheet.getMaxRows();
  if (bottom > max) {
    if (grow) sheet.insertRowsAfter(max, bottom - max);
    else bottom = max;
  }
  if (top > bottom) return null;
  return sheet.getRange(m[3] + top + ':' + (m[5] || m[3]) + bottom);
}

function rangeError_(message) {
  const e = new Error(message);
  e.name = 'RangeError';
  return e;
}

/// Drops empty rows at the end (a range like B5:Q3000 is mostly empty).
function trim_(rows) {
  let n = rows.length;
  while (n > 0 && rows[n - 1].every(function (c) { return c === ''; })) n--;
  return rows.slice(0, n);
}

function out_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}
