# Backup data karyawan dan quiz

Panduan ini bisa dipakai tanpa bantuan siapa pun. Semua langkahnya dilakukan di GitHub web, dan bisa juga dari HP.

## Apa yang di-backup

| Data | Tempat aslinya | Isi backup |
|---|---|---|
| **Karyawan** | Cloudflare KV `mymanual-auth`, data `emp:*` | NRP, nama, section, departemen, aktif/tidak, admin, PIN (dalam bentuk acak/hash), HP yang dipakai |
| **Quiz** | Cloudflare D1 `mymanual-quiz` | Semua tabel quiz: soal, progres belajar tiap mekanik, XP/leaderboard, laporan soal salah, pekerjaan pembuatan soal |

Yang **tidak** di-backup di sini:
- **Stok Cetok Online (Supabase)**: sudah punya backup sendiri lewat bot Telegram.
- **PDF manual**: aslinya ada di PC (`source\`).
- **Statistik pemakaian** dan **penilaian nyel AI**: kalau hilang, kerja mekanik tidak terganggu.

## Kapan backup dibuat

- **Otomatis setiap Minggu jam 22.00 WIB**, oleh workflow **Backup mingguan** (`.github/workflows/backup.yml`).
- **Manual kapan saja**, misalnya sebelum impor Excel karyawan yang besar: tab **Actions** > **Backup mingguan** > tombol **Run workflow** > **Run workflow**. Sekitar 2 menit kemudian hasilnya sudah ada.
- **Otomatis sebelum setiap pemulihan** (namanya `sebelum-pulih-…`), sebagai pengaman.

Setiap backup disimpan **90 hari**. Setelah itu GitHub menghapusnya sendiri, jadi selalu tersedia sekitar 12 backup mingguan terakhir.

Kalau backup gagal (misalnya token Cloudflare kedaluwarsa), run-nya berwarna merah di tab Actions dan GitHub mengirim email pemberitahuan.

## Melihat isi backup

1. Buka repo di GitHub, lalu tab **Actions**.
2. Di kolom kiri, klik **Backup mingguan**.
3. Klik run dengan tanggal yang diinginkan. Di bagian atas ada ringkasan, misalnya "Karyawan: 187, Quiz: question 412, …".
4. Gulir ke bawah ke bagian **Artifacts**, lalu klik **backup-2026-11-23** (contoh). Isinya terunduh sebagai ZIP.

Isi ZIP:

| File | Untuk apa |
|---|---|
| `karyawan.xlsx` | Daftar karyawan yang mudah dibaca. **Tanpa PIN.** |
| `quiz.xlsx` | Satu sheet per tabel quiz (soal di sheet `question`, XP di `xp_board`, dan seterusnya). |
| `BACA-SAYA.md` | Salinan panduan ini. |
| `pulihkan/karyawan.json` | Data karyawan lengkap untuk pemulihan. Jangan diubah. |
| `pulihkan/quiz.sql` | Database quiz lengkap untuk pemulihan. Jangan diubah. |

> File `pulihkan/` berisi data pribadi karyawan. Jangan dibagikan ke grup atau orang lain.

## Memulihkan data

Pakai ini kalau data rusak atau hilang, misalnya setelah salah impor Excel karyawan atau soal quiz terhapus.

### Langkah 1: pilih backup yang benar

Buka `karyawan.xlsx` atau `quiz.xlsx` dari beberapa backup terakhir (lihat bagian sebelumnya). Pilih **backup terakhir yang datanya masih benar**, lalu catat tanggalnya, misalnya `2026-11-23`.

### Langkah 2: jalankan pemulihan

1. Tab **Actions** > di kolom kiri klik **Pulihkan backup** > tombol **Run workflow**.
2. Isi tiga kolom:
   - **Tanggal backup**: misalnya `2026-11-23`. Kalau ada lebih dari satu backup di tanggal itu, yang dipakai adalah yang paling akhir. Bisa juga diisi nama lengkap, misalnya `sebelum-pulih-2026-11-26-1405`.
   - **Yang dipulihkan**: `karyawan`, `quiz`, atau `keduanya`.
   - **Ketik PULIHKAN**: harus persis `PULIHKAN` dengan huruf besar. Kalau isinya lain, workflow berhenti tanpa mengubah apa pun.
3. Tekan **Run workflow** yang hijau.

Workflow lalu menjalankan tiga tahap:
1. **check**: memeriksa kata konfirmasi dan mencari backup tersebut. Kalau tidak ketemu, berhenti di sini tanpa mengubah data.
2. **safety**: mem-backup data yang ada **sekarang** dengan nama `sebelum-pulih-<tanggal-jam>`.
3. **restore**: memulihkan data dari backup yang dipilih.

### Langkah 3: cek hasilnya

- Di halaman run, ringkasan di bagian atas menulis jumlah yang dipulihkan, misalnya "Karyawan dipulihkan: 187".
- Buka aplikasi: **Kelola karyawan**, atau **Quiz** untuk soal dan leaderboard.

### Kalau ternyata salah pilih

Jalankan **Pulihkan backup** sekali lagi. Isi kolom tanggal dengan nama `sebelum-pulih-…` yang tertulis di ringkasan run sebelumnya. Data akan kembali ke kondisi sebelum pemulihan tadi.

## Apa yang terjadi saat pemulihan

### Karyawan

Pemulihan hanya **mengembalikan dan menimpa** karyawan yang ada di backup. Contohnya kalau backup dibuat Minggu dan pemulihan dijalankan Rabu:

| Yang terjadi antara Minggu dan Rabu | Setelah dipulihkan |
|---|---|
| Budi terhapus karena salah impor | Budi **kembali** |
| Nama atau status Ali diubah | **Kembali seperti hari Minggu** |
| Citra mengganti PIN hari Senin | **PIN Citra kembali ke PIN hari Minggu**. Beri tahu Citra, atau buatkan PIN sementara lewat Kelola karyawan |
| Dedi karyawan baru, ditambahkan hari Selasa | Dedi **tetap ada** (tidak dihapus) |

Kalau ada karyawan yang memang harus dihapus, lakukan sendiri lewat **Kelola karyawan** di aplikasi.

### Quiz

Seluruh isi quiz dikembalikan **persis seperti saat backup**: soal, progres belajar, XP, dan leaderboard. Semua yang terjadi setelah tanggal backup akan hilang, misalnya XP yang didapat mekanik hari Senin–Rabu. Karena itu, pilih backup yang paling baru yang datanya masih benar.

## Hal teknis (untuk programmer)

- Script: `tools/backup_tool.py`, dengan tes di `tools/test_backup_tool.py` (dijalankan oleh workflow **Server and tools checks**).
- Karyawan diambil lewat Cloudflare API (KV list + bulk get), dan dipulihkan dengan KV bulk write.
- Quiz diambil dengan `wrangler d1 export mymanual-quiz --remote`. Untuk pemulihan, `restore-quiz-sql` membuat SQL yang mengosongkan tiap tabel lalu mengisinya kembali dengan nama kolom yang jelas, lalu SQL itu dijalankan dengan `wrangler d1 execute --remote --file`. Tabel `d1_migrations` tidak disentuh.
- Secret yang dipakai sama dengan deploy server AI: `CLOUDFLARE_API_TOKEN` (perlu izin Workers KV Storage Edit dan D1 Edit) dan `CLOUDFLARE_ACCOUNT_ID`.
- Mengubah jadwal: baris `cron: '0 15 * * 0'` di `backup.yml` (waktu dalam UTC; 15.00 UTC = 22.00 WIB, `0` = Minggu).
