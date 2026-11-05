// Jadwal ulang spaced repetition (PRD Kuis, 3 Nov 2026).
// Indeks daftar = level. Level 0 = baru salah.
const JEDA_HARI = [1, 3, 7, 14, 30, 60, 90];   // isi 7 angka: jeda level 0 sampai 6

/// Berapa hari lagi soal dengan level ini diulang.
export function daysUntilNext(level: number): number {
  if (level < 0) return JEDA_HARI[0];
  if (level >= JEDA_HARI.length) return JEDA_HARI[6];   // level di atas 6: pakai jeda terakhir
  return JEDA_HARI[level];                                   // ambil angka ke-[level] dari daftar
}
