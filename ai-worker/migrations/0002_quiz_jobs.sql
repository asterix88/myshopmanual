-- "Buat draf kuis" (Anas, 6 Nov 2026): nyel AI writes questions from a whole
-- manual in the background, a second AI call checks them (the curator), and
-- the admin approves. Runs once (D1 remembers applied migrations).

-- What the curator said about a draft, and which job made it.
ALTER TABLE question ADD COLUMN job_id TEXT;
ALTER TABLE question ADD COLUMN curator_score INTEGER;     -- 1..10, null = not checked
ALTER TABLE question ADD COLUMN curator_note TEXT;
ALTER TABLE question ADD COLUMN passed INTEGER NOT NULL DEFAULT 0;  -- 1 = curator 7+ and numbers found
CREATE INDEX IF NOT EXISTS question_job ON question (job_id);

-- One "Buat draf kuis" run.
CREATE TABLE IF NOT EXISTS quiz_job (
  id           TEXT PRIMARY KEY,
  site         TEXT NOT NULL DEFAULT 'SBS',
  section      TEXT NOT NULL,
  unit         TEXT,
  manual_id    TEXT NOT NULL,
  title        TEXT NOT NULL,                 -- "Shop Manual", for the progress card
  topic        TEXT NOT NULL,                 -- 'semua' or one of the topics
  count        INTEGER NOT NULL,              -- questions wanted
  mix          TEXT NOT NULL,                 -- JSON {"pg":60,"bs":20,"gambar":20} in percent
  status       TEXT NOT NULL,                 -- antri | jalan | selesai | gagal
  written      INTEGER NOT NULL DEFAULT 0,    -- questions the AI wrote
  passed       INTEGER NOT NULL DEFAULT 0,    -- kept and passed the curator
  flagged      INTEGER NOT NULL DEFAULT 0,    -- kept, but the admin must look
  dropped      INTEGER NOT NULL DEFAULT 0,    -- thrown away by the curator or the checks
  error        TEXT,
  lease_until  INTEGER NOT NULL DEFAULT 0,    -- a run holds the job until then
  created_by   TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS quiz_job_status ON quiz_job (status, created_at);

-- The pages nyel AI chose, with their text from the admin's phone.
CREATE TABLE IF NOT EXISTS quiz_job_page (
  job_id       TEXT NOT NULL,
  page         INTEGER NOT NULL,
  kind         TEXT NOT NULL,                 -- teks | gambar
  topic        TEXT NOT NULL,
  text         TEXT NOT NULL,
  done         INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (job_id, page)
);
