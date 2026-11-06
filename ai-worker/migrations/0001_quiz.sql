-- Quiz tables in the D1 database "mymanual-quiz" (binding QUIZ), from the
-- Quiz PRD (Claude Doc "Kuis MyManual v2: PRD & Schema"). The deploy
-- workflow runs "wrangler d1 migrations apply" before each deploy; D1
-- remembers which files already ran, so each file runs once.
--
-- Every statement uses IF NOT EXISTS: the table "question" was made by hand
-- by Anas in the D1 console on 5 Nov 2026 with this same definition, and it
-- stays as it is.
--
-- site: the job site. Everyone is at SBS for now; every row already carries
-- it, so other sites can join later without rewriting old data (like the
-- usage statistics, src/stats-db.ts).

-- Sites using MyManual. tz decides when a quiz day (04.00) and a week start.
CREATE TABLE IF NOT EXISTS site (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  tz           TEXT NOT NULL
);
INSERT OR IGNORE INTO site (id, name, tz) VALUES ('SBS', 'SBS', 'Asia/Jakarta');

-- One row per mechanic, made on their first quiz call from the login.
CREATE TABLE IF NOT EXISTS quiz_user (
  nrp          TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  site         TEXT NOT NULL DEFAULT 'SBS',
  departemen   TEXT NOT NULL DEFAULT '',
  section      TEXT NOT NULL DEFAULT '',     -- "TRACK" or "TRACK,WHEEL"
  reminder     TEXT DEFAULT '07:00',
  streak       INTEGER NOT NULL DEFAULT 0,
  best_streak  INTEGER NOT NULL DEFAULT 0,
  last_daily   TEXT,                          -- quiz day of the last Quiz harian done
  freeze_week  TEXT,                          -- week whose streak freeze is used ('W2026-45')
  xp_total     INTEGER NOT NULL DEFAULT 0,
  avatar       INTEGER NOT NULL DEFAULT 0,    -- 0..9, random at first login
  hidden       INTEGER NOT NULL DEFAULT 0     -- 1 = left off the leaderboard (test accounts)
);

-- Question bank, shared by every site.
CREATE TABLE IF NOT EXISTS question (
  id           TEXT PRIMARY KEY,
  section      TEXT NOT NULL,
  unit         TEXT,
  topic        TEXT NOT NULL,
  type         TEXT NOT NULL,
  prompt       TEXT NOT NULL,
  choices      TEXT NOT NULL,
  answer       INTEGER NOT NULL,
  explain      TEXT NOT NULL,
  manual_id    TEXT NOT NULL,
  page         INTEGER NOT NULL,
  image        TEXT,
  status       TEXT NOT NULL,
  source       TEXT NOT NULL,
  check_note   TEXT,
  created_by   TEXT NOT NULL,
  reviewed_by  TEXT,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS question_pick ON question (status, section, unit);
-- The practice rows from the D1 console lesson.
DELETE FROM question WHERE manual_id = 'CONTOH';

-- Spaced repetition: one row per mechanic per question answered.
CREATE TABLE IF NOT EXISTS card_state (
  nrp          TEXT NOT NULL,
  question_id  TEXT NOT NULL,
  site         TEXT NOT NULL DEFAULT 'SBS',
  unit         TEXT,
  level        INTEGER NOT NULL,              -- 0..6 (0 = just wrong; 4+ = dikuasai)
  next_date    TEXT NOT NULL,                 -- quiz day it is due again
  last_correct_day TEXT,                      -- no XP twice for the same question in a day
  correct      INTEGER NOT NULL DEFAULT 0,
  wrong        INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (nrp, question_id)
);
CREATE INDEX IF NOT EXISTS card_due ON card_state (nrp, next_date);
CREATE INDEX IF NOT EXISTS card_due_unit ON card_state (nrp, unit, next_date);

-- A set of 10 questions.
CREATE TABLE IF NOT EXISTS session (
  id           TEXT PRIMARY KEY,
  nrp          TEXT NOT NULL,
  site         TEXT NOT NULL DEFAULT 'SBS',
  mode         TEXT NOT NULL,                 -- harian | unit
  unit         TEXT,
  day          TEXT NOT NULL,                 -- quiz day it was made
  questions    TEXT NOT NULL,                 -- JSON array of question ids
  created_at   INTEGER NOT NULL,
  done_at      INTEGER,
  score        INTEGER,
  xp           INTEGER                        -- whole session incl. bonuses
);
CREATE INDEX IF NOT EXISTS session_nrp ON session (nrp, created_at);

-- Every answer. Rows older than 6 months are removed by the nightly job;
-- daily_stats keeps the totals.
CREATE TABLE IF NOT EXISTS review_log (
  id           TEXT PRIMARY KEY,              -- made on the phone, so a resend is not counted twice
  session_id   TEXT NOT NULL,
  nrp          TEXT NOT NULL,
  site         TEXT NOT NULL DEFAULT 'SBS',
  question_id  TEXT NOT NULL,
  chosen       INTEGER NOT NULL,
  correct      INTEGER NOT NULL,
  level_after  INTEGER NOT NULL,
  xp           INTEGER NOT NULL,
  ms           INTEGER NOT NULL,
  answered_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS review_q ON review_log (question_id);
CREATE INDEX IF NOT EXISTS review_time ON review_log (answered_at);
CREATE INDEX IF NOT EXISTS review_session ON review_log (session_id);

-- Per mechanic per quiz day: the 400 XP limit and the statistics.
CREATE TABLE IF NOT EXISTS daily_stats (
  day          TEXT NOT NULL,
  nrp          TEXT NOT NULL,
  site         TEXT NOT NULL DEFAULT 'SBS',
  answered     INTEGER NOT NULL DEFAULT 0,
  correct      INTEGER NOT NULL DEFAULT 0,
  xp           INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, nrp)
);

-- Leaderboard: one row per mechanic per period ('W2026-45' or 'M2026-11').
-- rank_prev is the rank at the last nightly run, for the up/down label.
CREATE TABLE IF NOT EXISTS xp_board (
  period       TEXT NOT NULL,
  site         TEXT NOT NULL DEFAULT 'SBS',
  departemen   TEXT NOT NULL DEFAULT '',
  nrp          TEXT NOT NULL,
  section      TEXT NOT NULL DEFAULT '',
  xp           INTEGER NOT NULL,
  reached_at   INTEGER NOT NULL,              -- equal XP: who got there first ranks higher
  rank_prev    INTEGER,
  PRIMARY KEY (period, site, departemen, nrp)
);
CREATE INDEX IF NOT EXISTS board_rank ON xp_board (period, site, departemen, xp DESC, reached_at);

-- "Soal salah" reports from mechanics.
CREATE TABLE IF NOT EXISTS report (
  id           TEXT PRIMARY KEY,
  question_id  TEXT NOT NULL,
  nrp          TEXT NOT NULL,
  site         TEXT NOT NULL DEFAULT 'SBS',
  note         TEXT,
  created_at   INTEGER NOT NULL,
  handled_by   TEXT,
  UNIQUE (question_id, nrp)
);
