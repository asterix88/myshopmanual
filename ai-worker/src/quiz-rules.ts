// Jadwal ulang spaced repetition (PRD Kuis, 3 Nov 2026).
// Indeks daftar = level. Level 0 = baru salah.
const JEDA_HARI = [7];   // isi 7 angka: jeda level 0 sampai 6

/// Berapa hari lagi soal dengan level ini diulang.
export function daysUntilNext(level: number): number {
  if (level < 0) return JEDA_HARI[0];
  if (level >= JEDA_HARI.length) return ___;   // level di atas 6: pakai jeda terakhir
  return ___;                                   // ambil angka ke-[level] dari daftar
}
