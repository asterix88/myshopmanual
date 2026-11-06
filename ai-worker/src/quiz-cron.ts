// The Quiz's nightly job, run by Cloudflare at 21.00 UTC (04.00 WIB, when a
// new quiz day starts; [triggers] in wrangler.toml):
// - remembers every leaderboard's ranks, so the app can show who went up
//   or down since yesterday (this week's board starts empty each Monday by
//   itself: its period id changes, e.g. W2026-45 -> W2026-46)
// - sends questions that most mechanics get wrong back to the admins
// - removes answers older than 6 months, old boards and abandoned sets

import * as quiz from "./quiz-db.ts";
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
