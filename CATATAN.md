# CATATAN SERAH TERIMA PROYEK MYMANUAL

Diperbarui: 17 November 2026. Pemilik: Anas (GitHub `ajisukuma89-spec`).

## Cara memakai catatan ini di chat baru

1. Buka chat baru di claude.ai (atau Project, kalau paketmu menyediakan Project Knowledge).
2. Upload file ini (`CATATAN.md`), lalu tulis: **"Baca dulu CATATAN.md ini sampai habis. Ini memori proyek MyManual. Setelah itu kita lanjutkan."**
3. Sebutkan apa yang mau dikerjakan, misalnya "lanjut fitur layar penuh di viewer".
4. Kalau Claude butuh kode, upload file yang dimaksud dari GitHub (buka file > tombol unduh / "Download raw file"), atau tempel isinya. Chat biasa **tidak bisa** membuka repo, membuat PR, atau menjalankan tes sendiri.
5. Setiap ada keputusan baru, minta Claude memperbarui bagian yang relevan di catatan ini, lalu ganti `CATATAN.md` di GitHub lewat editor web (buka file > ikon pensil > Commit changes).

Salinan yang sama ada di repo `asterix88/myshopmanual` sebagai `CATATAN.md`.

---

## 1. Ringkasan proyek

- **MyManual**: aplikasi Android (Flutter) untuk mekanik membuka dan mencari dokumen teknis (Shop Manual, OMM, Partsbook, dll.) per unit, bisa offline. Dipakai internal di site **SBS**, Plant Dept, Section **TRACK** (Excavator, Bulldozer), sedang disiapkan untuk WHEEL dan SUPPORT. Sekitar 188 karyawan terdaftar.
- Unit: PC210, PC500, PC1250, PC2000, CAT395, D85, D155, D375 (semua sudah punya gambar unit).
- Tab bawah: **Home, Cari, Nyel AI** (tombol oranye bulat di tengah), **Standar, Servis**. Bisa digeser kiri-kanan.
- **Nyel AI** (huruf n kecil): asisten tanya jawab yang membaca semua manual di server, mengutip halaman, bisa melihat gambar halaman, mencari di web kalau manual tidak memuat jawabannya.
- Fitur lain di Home ("Fitur lainnya"): **Cetok Online** (stok part), **Konversi Satuan**, **Daily Inspection Monitoring**, **Kuis Harian**.
- Versi app sekarang: 1.1.x (angka belakang = nomor build GitHub Actions).

## 2. Cara kerja dengan Anas (aturan wajib)

- Pakai **Bahasa Indonesia** santai. Panggil **"Anas"** saja (bukan "Mas", "Pak").
- Anas **baru belajar pemrograman**. Jelaskan dengan dua lapis: bahasa sederhana (analogi bengkel) lalu sisi teknis. Setiap PR diakhiri bagian **"Pelajaran dari PR ini"** (Apa yang berubah / File yang disentuh / Satu konsep baru / Coba lihat sendiri).
- **Mockup dulu, konfirmasi dulu, baru PR.** Untuk perubahan tampilan: buat mockup, tunggu OK Anas, baru ubah kode.
- **Setiap mockup = link/file baru** (jangan timpa versi lama), supaya histori bisa dibandingkan.
- Sebelum menggambar ulang layar yang sudah ada, cek desain final yang sudah disetujui (`mymanual/DESAIN-FINAL.md` di folder proyek), mulai dari tampilan aplikasi yang asli, jangan dari ingatan. (Anas pernah kesal karena mockup leaderboard memakai versi lama yang ada mahkotanya.)
- **Hindari tampilan "AI slop"**: teks pendek, tanpa kalimat sambutan panjang, tanpa emoji, tanpa ikon stok campur aduk, tanpa gradasi ungu, tanpa ilustrasi generik.
- Anas lebih suka semua lewat GitHub (web). **PC Anas tidak punya git clone**: folder `mymanual` di PC adalah salinan biasa. Mengganti file tool di PC = unduh file dari GitHub lalu timpa. (Dia berencana memasang GitHub Desktop.)
- Anas yang merge PR. Merge ke `main` otomatis membuat APK dan (kalau `ai-worker/` berubah) men-deploy server.

### Panduan desain (disetujui 28 Okt 2026)

1. Warna: navy `#1E3A64` utama; oranye `#F08A1C` hanya aksen kecil (sekitar satu titik per layar); abu netral latar `#F1F2F4`, teks `#1F2328` / `#6B7178`. Hijau `#1E7A46`, merah, kuning **hanya untuk status**.
2. Warna hidup datang dari foto unit (kuning Komatsu/CAT); UI tetap tenang.
3. Bentuk: radius kartu 16, ikon 12, satu bayangan tipis `0 1px 4px rgba(16,24,40,.08)`, jarak kelipatan 4/8.
4. Teks minimal, label pendek.
5. Ikon buatan sendiri satu gaya: garis navy 1.8, grid 24, satu aksen oranye.
6. Konten nyata (foto unit, nomor halaman, nilai torsi) di atas dekorasi.
7. Font **Poppins** saja. Ukuran: 22 judul besar, 17 app bar/sheet, 15 judul kartu/tombol, 13 isi, 12 meta, 11 LABEL CAPS; 30 untuk angka besar. Tebal: Regular isi, SemiBold judul/tombol, Bold hanya angka penting + label caps.

Logo: panah torsi oranye mengelilingi mur hex navy berlubang di kotak putih. Logo Nyel AI: balon chat + mur hex.

## 3. Arsitektur dan cara kerja teknis

```
PC Anas (Windows)                         Cloudflare                         HP mekanik (Android)
source\SECTION TRACK\EXCAVATOR\PC210\*.pdf
   │ update.bat / update-unit.bat
   ▼ tools/build_packages.py  ──upload──▶ R2 bucket "mymanual"  ◀──────────  app Flutter
     (indeks FTS5, catalog.json,          (PDF, indeks, catalog,     files.mymanual.my.id (hanya sesi login)
      spek.pdf, ukuran halaman)            spek.pdf)
                                          Worker "mymanual-ai"   ◀──────────  login NRP+PIN, Nyel AI,
                                          ai.mymanual.my.id                  stats, quiz, error, inspeksi
                                          KV AUTH, D1 mymanual-quiz,
                                          Durable Object STATS
Supabase (proyek Cetok Online) ◀──────────────────────────────────────────── tab Cetok (RPC)
Google Sheet Daily Inspection ◀── Apps Script "robot" ◀── Worker ◀────────── layar Daily Inspection
```

### Repo `asterix88/myshopmanual` (privat; Anas kolaborator)

- `app/`: aplikasi Flutter. Penting: `lib/src/store.dart` + `lib/src/store/` (data, unduhan, update, indeks AI, paket spek), `lib/src/screens/` (satu folder per layar besar: `viewer/`, `chat/`, `login/`, `cetok/`, `stats/`, `quiz/`, `quiz_hub/`, `quiz_admin/`), `lib/src/specs.dart` (Standar/Servis/Torsi), `lib/src/cetok.dart`, `lib/src/inspection.dart`, `lib/src/quiz*.dart`, `lib/src/error_reports.dart`, `lib/src/widgets/`. Native Android: `KeepAliveService.kt` (unduhan tetap jalan), `PublicDownloads.kt` (Simpan ke Download). Tes: `app/test/`, `app/integration_test/` (emulator).
- `ai-worker/`: server Cloudflare Worker (TypeScript). `src/index.ts` (Nyel AI), `auth.ts` (login NRP+PIN 4 digit, Lupa PIN, tanpa lockout), `files.ts` (sajikan R2 ke HP yang login), `sections.ts` (filter katalog per section), `stats*.ts`, `quiz*.ts` (D1, cron), `inspection*.ts` + `google.ts`, `errors.ts`, `feedback.ts`. `migrations/` = tabel D1. `wrangler.toml` = konfigurasi (`REQUIRE_LOGIN = "1"`, model AI, ID sheet inspeksi).
- `tools/` (dipakai di PC): `build_packages.py` (paket per unit + indeks + spek + ukuran halaman), `upload_r2.py`, `upload_karyawan.py`, `sections.py`, `sis_download.py` + `susunan.py` (dokumen CAT SIS), `daily-inspection.gs` (Apps Script robot), `torsi-pilihan.json`, `backup_tool.py`, `diag/` (skrip uji).
- Root: `update.bat` (bangun + upload semua), `update-unit.bat` (pilih unit), `update-karyawan.bat` (upload karyawan.xlsx), `sis-download.bat`, `r2-keys.example.bat` (kunci asli di `r2-keys.bat`, tidak di-commit), `BACKUP.md`, `README.md`.
- Workflow GitHub Actions (`.github/workflows/`):
  - `android.yml`: build APK tiap push ke main (+ GitHub Release `v<versi>`), bisa dijalankan manual untuk APK uji dari branch lain. Pakai `app-arm64-v8a-release.apk`.
  - `ai-worker.yml`: deploy server tiap perubahan `ai-worker/` di main (juga menerapkan migrasi D1 dan mengunggah secret).
  - `checks.yml` (tes), `emulator.yml` (tes UI di emulator Android 13 tiap PR, sekitar 6 menit), `ai-eval.yml` (uji jawaban Nyel AI pada PR AI, soal di `app/tool/ai_eval.json`).
  - `backup.yml` (Minggu 22.00 WIB + manual) dan `restore.yml` (pulihkan; ketik PULIHKAN). Lihat `BACKUP.md`.
  - `inspection-check.yml` (cek secret inspeksi tanpa menampilkan isinya), `signing-key.yml`.

**Nama secret / variabel di GitHub (isinya tidak pernah ditulis di sini):** `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `DEEPSEEK_API_KEY`, `GROQ_API_KEY`, `TAVILY_API_KEY`, `AI_TOKEN`, `OWNER_CODE`, `SHEET_SCRIPT_URL`, `SHEET_SCRIPT_KEY`, `GOOGLE_SERVICE_ACCOUNT` (cadangan, tidak dipakai), `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`; variabel `CATALOG_URL`. Juga ada `ELEVENLABS_API_KEY` (untuk suara video). Di PC: `r2-keys.bat` berisi kunci R2 dan ADMIN_CODE.

### Layanan

- **Domain** `mymanual.my.id` (Cloudflare). `ai.mymanual.my.id` = Worker; `files.mymanual.my.id` = file untuk HP yang login. URL lama `pub-…r2.dev` diblokir operator seluler Anas dan **harus dimatikan**.
- **AI**: DeepSeek V4 Flash (utama, perkiraan sekitar US$8/bulan untuk 50 user), Groq sebagai cadangan. Pencarian web: Tavily (gratis 1.000/bulan), cadangan Wikipedia. Kuota 10 pertanyaan/hari per HP (dihitung di HP, reset tengah malam), maksimal 4 putaran per pertanyaan.
- **Cara Nyel AI bekerja**: HP mengunduh indeks pencarian (SQLite FTS5) semua manual di latar belakang; AI memanggil alat `search_manuals`, `read_page`, `view_page`; jawaban mengutip halaman yang bisa diketuk. Aturan: selalu cari di manual dulu; kalau tidak ada, jawab dari pengetahuan umum dengan tanda "Secara umum"; tidak boleh mengarang part number atau arti kode error. Pelajaran: jangan kirim ke DeepSeek percakapan berisi putaran alat tanpa daftar alat (keluar teks DSML mentah).
- **Login**: NRP + PIN 4 digit, tanpa lockout (lockout 5x pernah dibuang karena mekanik terkunci). Admin = NRP dengan kolom Admin "ya" di `karyawan.xlsx`. Karyawan diunggah lewat `update-karyawan.bat`.
- **Cetok Online**: repo `asterix88/cetok-online` (publik; web statis `index.html`, `script.js`, `style.css`; backend Supabase). Tabel `stok`, `riwayat`; semua tulis lewat RPC `ambil_barang`, `input_barang`, `transfer_stok`; baca `get_all_data(p_riwayat_limit, p_show_hidden)`. Aplikasi memakai kunci publik Supabase (diterima untuk internal). Website menampilkan lokasi LOGISTIK/FABRIKASI/LAYDOWN/TRACKINDO. Supabase sudah dibackup sendiri oleh bot Telegram Anas. Ada juga bot WhatsApp (n8n + Baileys), host belum diketahui.
- **Daily Inspection**: Google Sheet "MASTER DATA MONITORING DAILY INSPECTION", tab `INSPECTION TRACK/WHEEL/SUPPORT OPEN 2026`. Ditulis lewat Apps Script di akun Gmail "robot" (Anas tidak punya kartu kredit untuk Google Cloud). Akses per section dari login NRP.
- **Kuis Harian**: spaced repetition level 0-6 (jeda 1/3/7/14/30/60/90 hari), soal Pilihan Ganda / Benar-Salah / Gambar, draf dibuat AI per halaman atau per file lalu dikurasi AI kedua, admin menyetujui. Data di D1 `mymanual-quiz`.

### Penyimpanan di HP

Manual yang diunduh ada di penyimpanan privat aplikasi (`files/manuals/<UNIT>/`), tidak terlihat di File Manager kecuali disimpan ke `Download/MyManual/` lewat tombol simpan. File state: `state.json` (tema, notifikasi, pencarian terakhir), `chat.json`, `cetok.json`, `quiz_pending.json`, `errors-pending.json`, `diagnostics.log`.

### Alur upload manual (di PC Anas)

1. Taruh PDF di `source\SECTION TRACK\<KELOMPOK>\<UNIT>\` (kelompok = EXCAVATOR / BULLDOZER; WHEEL: COMPACTOR, DT, GRADER, HD). Subfolder di dalam unit jadi folder di halaman unit. PDF yang lepas di `source\` dilewati.
2. Klik dua kali `update.bat` (semua) atau `update-unit.bat` (pilih unit). Jangan upload ke R2 manual.
3. Opsional: `source\<UNIT>\spek-hapus.txt` untuk menyembunyikan entri Standar/Servis yang salah (judul persis; `*` di akhir = awalan). `tools/torsi-pilihan.json` memilih komponen Torsi.
4. Setiap kali `build_packages.py` atau `upload_r2.py` berubah di GitHub, **file itu harus disalin ulang ke PC** sebelum menjalankan update.

## 4. SUDAH (fitur yang sudah jadi, dengan nomor PR)

**Dasar dan viewer**
- #1 MVP Flutter + pdfrx; #4 domain sendiri; signing key permanen; #9 Tanya AI; #14 HP unduh indeks semua manual; #20 PDF scan tetap diunggah (tidak bisa dicari); #25/#31 gambar semua unit; #26 Laporan masalah (diagnostik crash); #27 kartu lanjut baca; #28 riwayat chat + kuota; #29 `update-unit.bat`; #30 subfolder unit.
- #31/#33 perbaikan crash dan PDF abu-abu (pdfrx cache dan worker PDFium; pelajaran: jangan blok worker pdfrx dengan baca jaringan).
- #32 notifikasi update manual di latar belakang (tiap 3 jam).
- #53 pencarian di viewer pakai indeks (online pun seluruh manual), bookmark online dari indeks; #62 file online lebih cepat.
- #99 halaman landscape bertumpuk seperti Xodo.
- #51 Simpan ke Download; #65 ikon simpan di kartu; #76 kartu dokumen (ketuk = buka, tombol unduh bulat, cincin progres), tab bisa digeser.
- #34 mode gelap (default terang sejak #51).
- #50 layanan tetap hidup saat unduh + 5x coba ulang.

**Standar / Servis / Torsi**
- #35-#37 tab Spek lalu Standar (Torsi baut, Kapasitas oli & cairan, Nilai standar) dari paket `spek.pdf` per unit; tab Servis (jadwal perawatan per HM).
- #39 `spek-hapus.txt`; #47-#50 Torsi per komponen (grup dari bookmark Shop Manual, buka di bagian Installation, angka torsi ditandai kuning, chip "N angka torsi ditandai · berikutnya"); #49 Standard tightening torque, animasi loading excavator.
- #77/#79 dokumen CAT395 dari SIS (susunan OMM/SO/Troubleshooting, Servis CAT395).

**Nyel AI**
- #37 nama "Nyel AI", lalu #47 "Nyel AI". #38/#40/#41 boleh pakai pengetahuan umum yang diberi label. #42 cari web (Tavily). #43 salin pesan + cari riwayat chat. #64 tombol Nyel AI di viewer (Terjemahkan/Jelaskan/Ringkas halaman). #65/#66 mode berpikir DeepSeek, `read_page`, jempol 👍/👎 + admin Penilaian Nyel AI, maks 4 putaran. #70 perbaikan teks DSML mentah.

**Akun, admin, data**
- #60/#61/#67 login NRP + PIN 4 digit, Lupa PIN; #80 multi-section (TRACK/WHEEL/SUPPORT, katalog difilter per section, `REQUIRE_LOGIN=1`); #82 ganti section dengan ketuk logo.
- #74 logo baru, splash, login, intro 4 slide.
- #81 Statistik pemakaian admin + Kelola karyawan (setiap event punya kolom `site`, default SBS); #97 perbaikan statistik 0.
- #44/#73/#76 Cetok Online di app (Stok/Ambil/Input/Transfer, filter lokasi, Cari di Partsbook), ikon C di app bar lalu pindah ke "Fitur lainnya".
- #72 Konversi Satuan. #73 Home baru (judul MyManual dua warna, sapaan, "Dokumen teknis", "Fitur lainnya").
- #78 perbaikan keyboard, riwayat lonceng, Title Case.
- #85-#98 Kuis Harian (backend D1, UI, pengingat, draf otomatis, soal gambar, editor gambar, statistik kuis, anti-duplikat).
- #100/#110/#111/#112 Daily Inspection Monitoring (daftar per model > kartu per unit, umur temuan abu-abu, merah + titik kalau lebih dari 30 hari, label CLOSED, tambah temuan, offline tersimpan dulu).
- #101/#102/#105/#107/#108/#109 kode dirapikan (file besar dipecah, lint lebih ketat). Tidak ada file app lebih dari 1.000 baris kecuali `inspection_screen.dart`.
- #103 nomor versi otomatis + GitHub Releases; #104 laporan error otomatis (admin: ⋮ > Laporan error); #106 backup mingguan + pulihkan.
- #52 tes UI otomatis di emulator.

**Dokumen dan media** (di folder proyek Claude, `mymanual/`): Dokumentasi Lengkap (PDF), Skema Teknis, Penilaian Engineer, PRD, video intro (versi terakhir `MyManual-intro-motion(-musik).mp4`), video edukasi cara kerja, panduan Robot Sheet Daily Inspection (PDF). **Unduh semua file penting dari folder proyek sebelum langganan habis.**

## 5. BELUM (yang masih terbuka per 17 Nov 2026)

### PR terbuka
- **#113** Viewer: halaman landscape tidak loncat/berkedip saat file dibuka (ukuran halaman disimpan di indeks `meta.page_sizes`; HP mengingat ukuran yang sudah diukur di `page-sizes/`). Tunggu CI hijau lalu merge. **Setelah merge:** salin `tools/build_packages.py` ke PC lalu jalankan `update.bat`.
- **#68** Cari: tampilkan "Baru X dari Y manual bisa dicari" (dari Oktober, belum di-merge; cek apakah masih relevan atau tutup).
- (#111 unit dalam satu bingkai dan #112 umur temuan/CLOSED **sudah di-merge**.)

### Langkah di tangan Anas
1. Jalankan sekali **Actions > Backup mingguan > Run workflow** (uji pertama ke Cloudflare), cek hijau dan isi ZIP.
2. Checklist keamanan: matikan URL publik `r2.dev` di R2 Settings; aktifkan 2FA di GitHub, Cloudflare, Supabase, DeepSeek; pasang saldo DeepSeek kecil tanpa isi ulang otomatis.
3. Setelah #113: salin `tools/build_packages.py` ke PC dan jalankan `update.bat`.
4. Multi-section: masukkan manual WHEEL ke `source\SECTION WHEEL\<KELOMPOK>\<UNIT>\`; pastikan unit TRACK ada di bawah folder kelompok EXCAVATOR/BULLDOZER; tentukan isi SUPPORT; kirim data Supabase/website Cetok untuk WHEEL kalau Cetok per section mau dibuat.
5. Isi kolom Departemen di `karyawan.xlsx` (masih kosong).

### Belum dikerjakan (sudah diusulkan, menunggu keputusan)
- **Keamanan (tahap A dari penilaian engineer):** batas salah PIN yang lunak (10 salah = jeda 5 menit per NRP, plus batas per IP), batas pertanyaan Nyel AI per menit di server, tulis Cetok lewat Worker (bukan kunci publik Supabase), lalu cabut izin tulis anonim.
- Lint tambahan `avoid_catches_without_on_clauses` (39 tempat).
- Versi iPhone (perlu Apple Developer US$99/tahun, TestFlight, build Mac di cloud; fitur Android-only harus ditulis ulang).

## 6. AKAN (rencana berikutnya)

1. **Viewer layar penuh dengan ketuk (sedang dirancang):** saat PDF terbuka, ketuk layar sekali = layar penuh (app bar, bar bawah, tombol lain hilang), **hanya menyisakan balon Nyel AI**; ketuk lagi = kembali normal. Contoh: perilaku Xodo dari video Anas. Langkah: mockup dulu > OK Anas > PR. Setelah itu Anas mau fitur viewer lain.
2. **Multi-site (hanya rencana, belum dibangun):** sekitar 16 site (SBS, MIFA, BA, DMP, MIP, BIB, ADW, MAC, LAC, SKS, IPT, MHU, VIB, MLP, PIK, BGE). Hierarki Site > Departemen (Plant) > Section > NRP. NRP unik di semua site. Aturan fitur baru: data membawa `site`, jangan hardcode hal khusus SBS di app, NRP sebagai kunci, manual dipakai bersama. **Jangan** bangun migrasi D1 karyawan, peran Admin site, atau pilihan site sampai Anas meminta.
3. **Ide yang ditunda (ingatkan Anas):** Nyel AI dengan foto kamera (foto komponen/monitor unit > cari halaman manual yang cocok). Kamus istilah Indonesia untuk Cari dan pencarian makna (embedding): ditunda, buka lagi hanya kalau ada pertanyaan yang sering meleset. Animasi login seperti referensi Instagram (logo digambar garis lalu terisi).
4. **Ditolak untuk sekarang:** catatan halaman bersama, riwayat/favorit, tab Stok terpisah, peran admin section.

## 7. Pelajaran teknis penting

- pdfrx: satu file cache per URL; viewer dan gambar AI tidak boleh membuka manual online yang sama lewat cache yang sama. Jangan blok worker PDFium dengan baca jaringan.
- Manual online besar: pakai `loadPagesProgressively(startPageNumber: …)` agar halaman tujuan termuat tanpa scroll.
- Bookmark online diambil dari indeks (`toc`), bukan `loadOutline()` (bisa 30 detik).
- Tes widget: jangan `tester.pump` saat lifecycle paused (macet).
- Kode Dart di repo **tidak** diformat `dart format`; jangan format ulang seluruh file.
- Push paksa ditolak; kalau branch tertinggal, merge `main` ke branch.
- Setelah publish ulang halaman video, cek sumber video di halaman masih menunjuk file yang ada.

## 8. Link penting (halaman Claude; mungkin hanya bisa dibuka saat login)

- Dokumentasi Lengkap: https://claude.ai/artifact/9tnH3mS9ra54dt1XZSwkpy
- Skema Teknis: https://claude.ai/artifact/8kBfVo89V5avrxfr2ij9gh
- Penilaian engineer: https://claude.ai/artifact/FCyi889qhFpnJVbCoqByQw
- Rancangan multi-section: https://claude.ai/artifact/GkRXcu7h5gtGjsMWCXSpXa
- Rencana multi-site: https://claude.ai/artifact/BGZUtJGfHZGAv3ojS78atc
- PRD Cetok Online: https://claude.ai/artifact/58Znn5bJXrFewpNPLTjQeK
- Peta kode untuk belajar: https://claude.ai/artifact/WuyfnEoZdv9q3kcTNqmpWf
- Leaderboard kuis final: "Simulasi Quiz MyManual" (`mymanual/quiz/quiz-simulasi.html`)
- Video intro: https://claude.ai/artifact/ATfY4QEMfqMXhNZtWRNS7R
