# MyManual

Aplikasi Android untuk membuka Shop Manual, OMM, dan Partsbook per unit model secara offline.
Aplikasinya kecil; PDF diunduh per unit sesuai kebutuhan, lalu bisa dibuka dan dicari tanpa sinyal.

## Tahap 1: pipeline paket per unit

`tools/build_packages.py` dijalankan di PC admin. Script ini membaca satu folder per unit,
melewati PDF hasil scan (tidak ada teks), membuat indeks pencarian SQLite FTS5 per unit,
dan menulis `catalog.json` yang dibaca aplikasi untuk tahu file apa saja yang tersedia dan berubah.

```
source/PC210/*.pdf   ->   dist/catalog.json
source/D85/*.pdf          dist/units/PC210/*.pdf
                          dist/units/PC210/index.sqlite
```

```bash
pip install -r tools/requirements.txt
python tools/build_packages.py source dist            # semua unit
python tools/build_packages.py source dist --only PC210
python tools/search.py dist/units/PC210/index.sqlite "track tension"
```

Folder unit boleh berisi `unit.json`, misalnya `{"name": "PC210-10M0", "kind": "Excavator"}`.
`kind` menentukan folder di beranda (Excavator atau Bulldozer). Kalau kosong, aplikasi menebak dari
kode model: PC, CAT, ZX, EX masuk EXCAVATOR; D85, D155, D375 masuk BULLDOZER; selain itu LAINNYA.
Menjalankan ulang script mempertahankan `catalog.json` lama: tanggal `updated_at` tiap file
hanya berubah kalau PDF-nya berubah, dan dari situ aplikasi tahu ada manual baru atau versi baru.

## Unggah ke Cloudflare R2

```bash
pip install boto3
export R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_BUCKET=mymanual
python tools/upload_r2.py dist --dry-run   # lihat dulu apa yang berubah
python tools/upload_r2.py dist             # unggah file yang berubah, catalog.json terakhir
```

### Sekali klik di Windows: `update.bat`

1. Salin `r2-keys.example.bat` menjadi `r2-keys.bat`, lalu isi kunci R2 Anda. File ini tidak ikut
   ke GitHub (ada di `.gitignore`), jadi kunci tetap di PC.
2. Taruh PDF di `source\<UNIT>\`, lalu klik dua kali `update.bat`. Script membuat paket lalu
   mengunggah yang berubah saja.
3. Untuk meng-update folder tertentu saja, klik dua kali `update-unit.bat`: daftar folder di `source\`
   ditampilkan, ketik nama foldernya (lebih dari satu dipisah spasi, huruf besar/kecil sama saja). Unit
   lain tetap ada di aplikasi seperti sebelumnya. Lewat Command Prompt bisa juga `update.bat --only PC210`.
   PDF boleh juga ditaruh di subfolder unit, misalnya `source\CAT395\System Diagram\`: file itu tetap
   masuk unit CAT395 dan tampil di bawah judul "System Diagram" di halaman unit.

## Server AI (`ai-worker/`)

Tab **Tanya AI** memakai AI Groq (tier gratis) lewat Cloudflare Worker kecil di `ai.mymanual.my.id`,
supaya kunci API tidak ikut di dalam APK. Pencarian halaman tetap berjalan di HP, pada manual yang sudah
diunduh; Worker hanya meneruskan percakapan ke AI dan mengembalikan jawabannya, lengkap dengan nomor
halaman sumber. Tier gratis punya batas permintaan per menit dan per hari; kalau penuh, aplikasi
menampilkan pesan untuk mencoba lagi nanti.

AI juga bisa melihat halaman manual sebagai gambar (wiring/hydraulic diagram, lokasi komponen). HP
menggambar halaman itu (atau seperempatnya untuk memperbesar) lalu mengirimnya ke AI. Hanya model di
`VISION_MODEL` yang dipakai untuk percakapan yang berisi gambar.

Server ini di-deploy otomatis oleh GitHub Actions (`.github/workflows/ai-worker.yml`) setiap folder
`ai-worker/` berubah di `main`; tidak ada yang perlu dipasang di PC. Siapkan sekali di GitHub, menu
Settings > Secrets and variables > Actions > New repository secret:

- `GROQ_API_KEY`: dari console.groq.com > API Keys (gratis, cukup login).
- `DEEPSEEK_API_KEY` (opsional): dari platform.deepseek.com > API Keys (berbayar, isi saldo). Kalau
  diisi, AI menjawab pakai DeepSeek dulu; kalau saldo habis atau DeepSeek bermasalah, otomatis
  pindah ke Groq gratis. Setelah menambah atau mengganti secret ini, jalankan ulang workflow
  "Deploy AI server" (tab Actions > Deploy AI server > Run workflow).
- `OWNER_CODE` (opsional): kode admin bebas (misalnya 8 huruf/angka acak). Setiap HP dibatasi 10 pertanyaan
  Tanya AI per hari; di HP yang memasukkan kode ini lewat menu ⋮ > Kode admin, batasnya hilang. Setelah
  menambah atau mengganti secret ini, jalankan ulang workflow "Deploy AI server".
- `CLOUDFLARE_API_TOKEN`: dari Cloudflare, My Profile > API Tokens > Create Token > template
  "Edit Cloudflare Workers", tambahkan izin Zone > DNS > Edit untuk zona `mymanual.my.id`.
- `CLOUDFLARE_ACCOUNT_ID`: ID akun di halaman Workers & Pages Cloudflare (kolom kanan).

Lalu di tab Actions jalankan "Deploy AI server" (Run workflow). Setelah selesai,
https://ai.mymanual.my.id harus menampilkan `{"ok":true,...}`. Model dan alamat API diatur di
`ai-worker/wrangler.toml` (`MODEL`, `API_URL`); API lain yang kompatibel dengan format OpenAI (misalnya
Gemini atau OpenRouter) juga bisa dipakai dengan mengganti keduanya dan kuncinya.

## Aplikasi Android (`app/`)

Flutter, dengan penampil PDF PDFium (`pdfrx`) dan indeks pencarian SQLite FTS5 (`sqlite3`).

- Tab **Unit**: daftar unit, lanjutkan membaca, folder unit dengan unduh/hapus per file.
- Penampil: cari kata di file, penanda bawaan PDF, tanda halaman sendiri, lompat halaman.
- Tab **Cari**: cari di semua manual yang sudah diunduh, langsung ke halamannya.
- Lonceng: update file manual di server (manual baru, versi baru, ditarik).
- Tab **Tanya AI**: belum aktif (tahap berikutnya, butuh internet).

APK dibuat otomatis oleh GitHub Actions (`.github/workflows/android.yml`) di setiap push dan PR;
unduh dari halaman run, bagian *Artifacts*. Alamat server bawaan adalah domain bucket R2
`https://mymanual.my.id` (alamat r2.dev tidak dipakai karena diblokir sebagian operator seluler); variabel repo `CATALOG_URL` bisa menggantinya
saat build, dan pengguna bisa menggantinya di aplikasi lewat menu ⋮ > Alamat server.

```bash
cd app
flutter test                                        # tes unit
flutter test tool/screenshot_test.dart --update-goldens   # render screenshot ke tool/screenshots/
```

Catatan lisensi: PyMuPDF berlisensi AGPL. Ini aman untuk script internal di PC admin
karena script tidak ikut didistribusikan di dalam aplikasi.

## Kunci tanda tangan APK

Android hanya mau memasang update di atas aplikasi lama kalau keduanya ditandatangani dengan kunci yang
sama. Tanpa kunci tetap, setiap build GitHub memakai kunci acak, jadi update gagal terpasang.

1. Di tab Actions jalankan "Create APK signing key" (Run workflow), lalu unduh artifact `signing-key`.
2. Buka `isi-secret.txt` di dalamnya dan buat tiga repository secret dengan nama dan isi persis seperti
   di file itu: `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEYSTORE_BASE64`.
3. Simpan salinan file itu di tempat aman (kalau hilang, semua HP harus uninstall lalu install ulang),
   lalu hapus artifact-nya di GitHub.

Setelah itu semua build memakai kunci ini. Aplikasi yang terpasang dengan kunci lama perlu di-uninstall
sekali, setelahnya update bisa langsung dipasang di atasnya.
