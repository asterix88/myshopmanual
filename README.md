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
Menjalankan ulang script mempertahankan `catalog.json` lama: tanggal `updated_at` tiap file
hanya berubah kalau PDF-nya berubah, dan dari situ aplikasi tahu ada manual baru atau versi baru.

## Unggah ke Cloudflare R2

```bash
pip install boto3
export R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_BUCKET=mymanual
python tools/upload_r2.py dist --dry-run   # lihat dulu apa yang berubah
python tools/upload_r2.py dist             # unggah file yang berubah, catalog.json terakhir
```

## Aplikasi Android (`app/`)

Flutter, dengan penampil PDF PDFium (`pdfrx`) dan indeks pencarian SQLite FTS5 (`sqlite3`).

- Tab **Unit**: daftar unit, lanjutkan membaca, folder unit dengan unduh/hapus per file.
- Penampil: cari kata di file, penanda bawaan PDF, tanda halaman sendiri, lompat halaman.
- Tab **Cari**: cari di semua manual yang sudah diunduh, langsung ke halamannya.
- Lonceng: update file manual di server (manual baru, versi baru, ditarik).
- Tab **Tanya AI**: belum aktif (tahap berikutnya, butuh internet).

APK dibuat otomatis oleh GitHub Actions (`.github/workflows/android.yml`) di setiap push dan PR;
unduh dari halaman run, bagian *Artifacts*. Alamat server diambil dari variabel repo `CATALOG_URL`
dan bisa diganti di aplikasi lewat menu ⋮ > Alamat server.

```bash
cd app
flutter test                                        # tes unit
flutter test tool/screenshot_test.dart --update-goldens   # render screenshot ke tool/screenshots/
```

Catatan lisensi: PyMuPDF berlisensi AGPL. Ini aman untuk script internal di PC admin
karena script tidak ikut didistribusikan di dalam aplikasi.
