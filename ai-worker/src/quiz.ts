// The Quiz's endpoints for the app (/quiz/*); the admin ones are in
// quiz-admin.ts and the nightly job in quiz-cron.ts. Every call needs the
// NRP login session; what is done with the database is in quiz-db.ts, the
// rules (levels, XP, streak) in quiz-rules.ts.
//
//   GET  /quiz/home         Quiz harian done or not, streak, XP this week, rank
//   GET  /quiz/units        units with questions, and how many are mastered
//   POST /quiz/session      {mode: "harian" | "unit", unit?} -> 10 questions
//   POST /quiz/answer       {id, session_id, question_id, chosen, ms, at?}
//   POST /quiz/finish       {session_id} -> bonus, streak, rank
//   GET  /quiz/leaderboard  ?period=week|month -> top 20 + own row
//   POST /quiz/avatar       {avatar: 0..9}
//   POST /quiz/settings     {reminder: "07:00"}
//   POST /quiz/report       {question_id, note}

import { allowedOf, employeeInfo, requireSession, type AuthEnv, type Session } from "./auth";
import * as quiz from "./quiz-db.ts";
import { handleQuizAdmin, type AiEnv } from "./quiz-admin.ts";

export interface QuizEnv extends AuthEnv, AiEnv {
  QUIZ: D1Database;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  if (request.method === "GET") return Object.fromEntries(new URL(request.url).searchParams);
  try {
    const b = await request.json();
    return b && typeof b === "object" ? (b as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/// The mechanic as the Quiz sees them: sections from the login, department
/// from the employee list. Everyone is at site SBS for now.
async function whoOf(env: QuizEnv, s: Session): Promise<quiz.Who | Response> {
  const info = await employeeInfo(env, s.n);
  if (!info || !info.active) return json({ error: "inactive", message: "NRP ini sudah tidak aktif, hubungi admin." }, 403);
  return { nrp: s.n, name: s.nm, sections: allowedOf(s), departemen: info.department, site: quiz.DEFAULT_SITE };
}

const MESSAGES: Record<string, [number, string]> = {
  done: [409, "Quiz harian hari ini sudah selesai. Coba Quiz per unit, atau kembali besok."],
  empty: [404, "Soal baru sedang disiapkan."],
  session: [404, "Sesi quiz tidak ditemukan. Mulai quiz lagi."],
  question: [400, "Soal ini bukan bagian dari sesi."],
  late: [410, "Jawaban ini lebih dari 3 hari tersimpan di HP, jadi tidak dihitung lagi."],
};

function failed(error: string): Response {
  const [status, message] = MESSAGES[error] ?? [400, "Permintaan tidak valid."];
  return json({ error, message }, status);
}

/// Handles /quiz/* and /admin/quiz/*; null for other paths.
export async function handleQuiz(request: Request, env: QuizEnv, path: string): Promise<Response | null> {
  if (path.startsWith("/admin/quiz/")) return handleQuizAdmin(request, env, path);
  if (!path.startsWith("/quiz/")) return null;
  if (request.method !== "GET" && request.method !== "POST") return json({ error: "method" }, 405);
  const auth = await requireSession(env, request);
  if (auth.error) return auth.error;
  const who = await whoOf(env, auth.session);
  if (who instanceof Response) return who;
  const db = quiz.d1(env.QUIZ);
  await quiz.ensureUser(db, who);
  const b = await readBody(request);
  if (!b) return json({ error: "bad_request" }, 400);

  switch (path) {
    case "/quiz/home":
      return json(await quiz.home(db, who));
    case "/quiz/units":
      return json({ units: await quiz.units(db, who) });
    case "/quiz/session": {
      const mode = b.mode === "unit" ? "unit" : "harian";
      const unit = mode === "unit" ? String(b.unit ?? "").trim() || null : null;
      const out = await quiz.startSession(db, who, mode, unit);
      return "error" in out ? failed(out.error) : json(out);
    }
    case "/quiz/answer": {
      const a = {
        id: String(b.id ?? ""),
        session_id: String(b.session_id ?? ""),
        question_id: String(b.question_id ?? ""),
        chosen: Number(b.chosen),
        ms: Number(b.ms),
        at: b.at === undefined ? undefined : Number(b.at),
      };
      if (!a.id || !a.session_id || !a.question_id || !Number.isInteger(a.chosen) || !Number.isFinite(a.ms)) {
        return json({ error: "bad_request" }, 400);
      }
      const out = await quiz.answer(db, who, a);
      return "error" in out ? failed(out.error) : json(out);
    }
    case "/quiz/finish": {
      const out = await quiz.finish(db, who, String(b.session_id ?? ""));
      return "error" in out ? failed(out.error) : json(out);
    }
    case "/quiz/leaderboard":
      return json(await quiz.leaderboard(db, who, b.period === "month" ? "month" : "week"));
    case "/quiz/avatar":
      return (await quiz.setAvatar(db, who, Number(b.avatar)))
        ? json({ ok: true })
        : json({ error: "bad_request", message: "Avatar harus 0 sampai 9." }, 400);
    case "/quiz/settings":
      return (await quiz.setReminder(db, who, String(b.reminder ?? "")))
        ? json({ ok: true })
        : json({ error: "bad_request", message: "Jam pengingat harus seperti 07:00." }, 400);
    case "/quiz/report": {
      const out = await quiz.report(db, who, String(b.question_id ?? ""), String(b.note ?? ""));
      return "error" in out ? failed(out.error) : json({ ok: true, ...out });
    }
  }
  return json({ error: "not_found" }, 404);
}
