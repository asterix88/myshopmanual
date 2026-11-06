// The Quiz's nightly job, run by Cloudflare at 21.00 UTC (04.00 WIB, when a
// new quiz day starts; [triggers] in wrangler.toml):
// - remembers every leaderboard's ranks, so the app can show who went up
//   or down since yesterday (this week's board starts empty each Monday by
//   itself: its period id changes, e.g. W2026-45 -> W2026-46)
// - sends questions that most mechanics get wrong back to the admins
// - removes answers older than 6 months, old boards and abandoned sets

import * as quiz from "./quiz-db.ts";
import { askWith, type AiEnv } from "./quiz-ai.ts";
import { runJobs } from "./quiz-jobs.ts";
import { quizDay } from "./quiz-rules.ts";

export async function runNightly(db: quiz.Db, now = Date.now()): Promise<void> {
  const day = quizDay(now, await quiz.siteTz(db, quiz.DEFAULT_SITE));
  await quiz.snapshotRanks(db, day);
  const flagged = await quiz.flagHardQuestions(db, now);
  const tidied = await quiz.tidy(db, now);
  console.log("quiz nightly", day, { flagged, ...tidied });
}

export async function scheduledQuiz(env: { QUIZ: D1Database }): Promise<void> {
  await runNightly(quiz.d1(env.QUIZ));
}

/// Every minute: works on "Buat draf kuis" jobs for up to 12 minutes (a
/// cron run may take 15), one job at a time.
export async function scheduledJobs(env: { QUIZ: D1Database } & AiEnv): Promise<void> {
  const worked = await runJobs(quiz.d1(env.QUIZ), askWith(env), Date.now() + 12 * 60_000);
  if (worked) console.log("quiz jobs", worked);
}
