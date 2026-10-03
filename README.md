# MyShopManual

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

Isi `dist/` nantinya diunggah ke Cloudflare R2.

Catatan lisensi: PyMuPDF berlisensi AGPL. Ini aman untuk script internal di PC admin
karena script tidak ikut didistribusikan di dalam aplikasi.
