// Jadwal ulang spaced repetition (PRD Kuis, 3 Nov 2026).
// Indeks daftar = level. Level 0 = baru salah.
const JEDA_HARI = [1, 3, 7, 14, 30, 60, 90];   // isi 7 angka: jeda level 0 sampai 6

/// Berapa hari lagi soal dengan level ini diulang.
export function daysUntilNext(level: number): number {
  if (level < 0) return JEDA_HARI[0];
  if (level >= JEDA_HARI.length) return JEDA_HARI[JEDA_HARI.length-1];   // level di atas 6: pakai jeda terakhir
  return JEDA_HARI[level];                                   // ambil angka ke-[level] dari daftar
}

// ---------------------------------------------------------------------------
// Aturan Quiz lainnya (PRD Kuis bagian "Aturan"), semuanya fungsi murni:
// tanpa database dan tanpa jam, supaya bisa dites seperti daysUntilNext.

/// Level tertinggi; soal level 4 ke atas = "dikuasai".
export const MAX_LEVEL = JEDA_HARI.length - 1;
export const MASTERED_LEVEL = 4;
export const isMastered = (level: number) => level >= MASTERED_LEVEL;

// ---- Hari quiz ----

/// Hari quiz dimulai jam 04.00 waktu site: jam 01.00 masih hari kemarin
/// (mekanik shift malam).
export const DAY_START_HOUR = 4;

/// Tanggal hari quiz ("2026-11-06") untuk waktu [ms] di zona waktu [tz].
export function quizDay(ms: number, tz: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" })
    .format(new Date(ms - DAY_START_HOUR * 3600_000));
}

/// [day] ditambah [n] hari ("2026-11-06" + 3 = "2026-11-09").
export function addDays(day: string, n: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/// Selisih hari dari [a] ke [b] (b - a).
export function daysBetween(a: string, b: string): number {
  return Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400_000);
}

/// Periode papan minggu ini: minggu ISO (Senin sampai Minggu), "W2026-45".
export function weekId(day: string): string {
  const d = new Date(`${day}T00:00:00Z`);
  const weekday = (d.getUTCDay() + 6) % 7; // Senin = 0
  d.setUTCDate(d.getUTCDate() - weekday + 3); // Kamis minggu itu menentukan tahunnya
  const year = d.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(year, 0, 4));
  firstThursday.setUTCDate(firstThursday.getUTCDate() - ((firstThursday.getUTCDay() + 6) % 7) + 3);
  const week = 1 + Math.round((d.getTime() - firstThursday.getTime()) / (7 * 86400_000));
  return `W${year}-${String(week).padStart(2, "0")}`;
}

/// Periode papan bulan ini, "M2026-11".
export const monthId = (day: string) => `M${day.slice(0, 7)}`;

// ---- Level dan jadwal ulang ----

export type Card = { level: number; next_date: string; last_correct_day?: string | null };

/// Keadaan kartu setelah satu jawaban pada hari [day]. [card] null = soal
/// baru. Benar tepat waktu (atau soal baru) naik satu level; benar sebelum
/// jadwal tidak naik; salah kapan pun kembali ke level 0 dan diulang besok.
export function nextCard(card: Card | null, correct: boolean, day: string): { level: number; next_date: string; due: boolean } {
  const due = !card || card.next_date <= day;
  if (!correct) return { level: 0, next_date: addDays(day, daysUntilNext(0)), due };
  if (!card) return { level: 1, next_date: addDays(day, daysUntilNext(1)), due };
  if (!due) return { level: card.level, next_date: card.next_date, due };
  const level = Math.min(card.level + 1, MAX_LEVEL);
  return { level, next_date: addDays(day, daysUntilNext(level)), due };
}

// ---- XP ----

export const XP = {
  correct: 10,
  correctMastered: 5,
  wrong: 2,
  finish: 10,
  perfect: 20,
  streakPerDay: 5,
  streakMax: 35,
  dailyCap: 400,
  minMs: 2000,
};

/// XP satu jawaban, sebelum batas harian.
/// - di bawah 2 detik: 0 (menebak cepat)
/// - benar: 10, atau 5 kalau soal sudah dikuasai sebelum dijawab;
///   0 kalau soal ini sudah dijawab benar hari ini, atau dijawab sebelum
///   jadwal ceknya
/// - salah: 2 (tetap dihargai karena mencoba)
export function answerXp(a: { correct: boolean; ms: number; levelBefore: number | null; due: boolean; correctToday: boolean }): number {
  if (a.ms < XP.minMs) return 0;
  if (!a.correct) return XP.wrong;
  if (a.correctToday || !a.due) return 0;
  return a.levelBefore !== null && isMastered(a.levelBefore) ? XP.correctMastered : XP.correct;
}

/// [xp] dipotong supaya total hari ini tidak lewat 400.
export function capDaily(earnedToday: number, xp: number): number {
  return Math.max(0, Math.min(xp, XP.dailyCap - earnedToday));
}

/// Bonus selesai sesi: +10, dan +20 lagi kalau semua benar.
export function sessionBonus(score: number, total: number): number {
  if (total <= 0) return 0;
  return XP.finish + (score === total ? XP.perfect : 0);
}

/// Bonus streak Quiz harian: +5 per hari streak, maksimal +35.
export const streakBonus = (streak: number) => Math.min(streak * XP.streakPerDay, XP.streakMax);

// ---- Streak ----

export type StreakState = { streak: number; best_streak: number; last_daily: string | null; freeze_week: string | null };

/// Streak setelah Quiz harian selesai pada hari [day].
/// - sudah selesai hari ini: tidak berubah
/// - terakhir kemarin: +1
/// - terlewat tepat satu hari dan libur streak minggu itu belum dipakai:
///   libur dipakai otomatis, streak tetap jalan (+1 untuk hari ini)
/// - selain itu: mulai lagi dari 1
export function nextStreak(s: StreakState, day: string): StreakState & { freezeUsed: boolean } {
  if (s.last_daily === day) return { ...s, freezeUsed: false };
  const gap = s.last_daily ? daysBetween(s.last_daily, day) : Infinity;
  let streak = 1;
  let freeze_week = s.freeze_week;
  let freezeUsed = false;
  if (gap === 1) {
    streak = s.streak + 1;
  } else if (gap === 2 && s.freeze_week !== weekId(addDays(day, -1))) {
    streak = s.streak + 1;
    freeze_week = weekId(addDays(day, -1));
    freezeUsed = true;
  }
  return { streak, best_streak: Math.max(s.best_streak, streak), last_daily: day, freeze_week, freezeUsed };
}

/// Streak yang tampil di Home pada hari [day]: 0 kalau sudah putus
/// (terlewat lebih dari satu hari, atau satu hari tanpa libur tersisa).
export function streakNow(s: StreakState, day: string): number {
  if (!s.last_daily) return 0;
  const gap = daysBetween(s.last_daily, day);
  if (gap <= 1) return s.streak;
  if (gap === 2 && s.freeze_week !== weekId(addDays(day, -1))) return s.streak;
  return 0;
}

// ---- Menyusun 10 soal ----

export const SESSION_SIZE = 10;
export const MAX_REVIEWS = 3;

/// Memilih soal sesi dari tiga daftar yang sudah diurutkan server:
/// [due] ulangan (paling lama terlambat dulu), [fresh] soal yang belum pernah
/// dijawab, [fallback] soal level terendah yang belum waktunya. Maksimal 3
/// ulangan, sisanya soal baru, kekurangan diisi fallback; lalu diacak.
/// [random] diganti di tes supaya hasilnya tetap.
export function pickSession<T extends { id: string }>(
  due: T[],
  fresh: T[],
  fallback: T[],
  random: () => number = Math.random,
): { question: T; review: boolean }[] {
  const picked: { question: T; review: boolean }[] = [];
  const seen = new Set<string>();
  const take = (list: T[], max: number, review: boolean) => {
    for (const q of list) {
      if (picked.length >= SESSION_SIZE || max <= 0) return;
      if (seen.has(q.id)) continue;
      seen.add(q.id);
      picked.push({ question: q, review });
      max--;
    }
  };
  take(due, MAX_REVIEWS, true);
  take(fresh, SESSION_SIZE, false);
  take(fallback, SESSION_SIZE, true);
  for (let i = picked.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [picked[i], picked[j]] = [picked[j], picked[i]];
  }
  return picked;
}

// ---- Bentuk soal ----

export const TOPICS = ["struktur", "torsi", "kapasitas", "standar", "fault", "servis", "sistem"];
export const TYPES = ["pg", "bs", "gambar"];
export const STATUSES = ["draf", "terbit", "ditolak", "ditarik", "perlu_cek"];

export type QuestionInput = {
  section: string;
  unit: string | null;
  topic: string;
  type: string;
  prompt: string;
  choices: string[];
  answer: number;
  explain: string;
  manual_id: string;
  page: number;
};

/// Kesalahan pertama pada soal, atau null kalau soal boleh disimpan.
/// pg dan gambar: 2 sampai 4 pilihan; bs: tepat "Benar" dan "Salah".
export function questionProblem(q: QuestionInput): string | null {
  if (!q.section) return "Section kosong.";
  if (!TOPICS.includes(q.topic)) return `Topik harus salah satu dari: ${TOPICS.join(", ")}.`;
  if (!TYPES.includes(q.type)) return "Jenis soal harus pg, bs atau gambar.";
  if (!q.prompt.trim()) return "Pertanyaan kosong.";
  if (!q.explain.trim()) return "Penjelasan kosong.";
  if (!q.manual_id.trim() || !(q.page >= 1)) return "Manual dan halaman sumber wajib diisi.";
  if (q.type === "bs") {
    if (q.choices.length !== 2) return "Soal benar/salah harus punya 2 pilihan.";
  } else if (q.choices.length < 2 || q.choices.length > 4) {
    return "Soal pilihan ganda harus punya 2 sampai 4 pilihan.";
  }
  if (q.choices.some((c) => !c.trim())) return "Ada pilihan yang kosong.";
  if (new Set(q.choices.map((c) => c.trim().toLowerCase())).size !== q.choices.length) return "Ada pilihan yang sama.";
  if (!Number.isInteger(q.answer) || q.answer < 0 || q.answer >= q.choices.length) return "Kunci jawaban tidak ada di pilihan.";
  return null;
}

/// Angka di jawaban benar yang tidak ada di teks halaman sumber, untuk
/// catatan cek admin ("AI salah angka" di PRD). "1,5" dan "1.5" dianggap
/// sama; angka 1 digit diabaikan (nomor langkah, "2 baut").
export function numbersMissing(answerText: string, pageText: string): string[] {
  const norm = (s: string) => s.replace(/(\d)[.,](\d)/g, "$1.$2");
  const page = new Set(norm(pageText).match(/\d+(?:\.\d+)?/g) ?? []);
  const nums = norm(answerText).match(/\d+(?:\.\d+)?/g) ?? [];
  return [...new Set(nums.filter((n) => n.replace(".", "").length >= 2 && !page.has(n)))];
}
