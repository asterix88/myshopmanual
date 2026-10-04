@echo off
rem Build packages from source\ and upload the changes to Cloudflare R2.
rem Keys are read from r2-keys.bat next to this file (not committed to git).
rem Extra arguments go to build_packages.py, e.g.  update.bat --only PC210
setlocal
cd /d "%~dp0"

if not exist r2-keys.bat (
  echo File r2-keys.bat belum ada.
  echo Salin r2-keys.example.bat menjadi r2-keys.bat, lalu isi kunci R2 Anda.
  pause
  exit /b 1
)
call r2-keys.bat

echo === 1/2 Membuat paket dari folder source ===
python tools\build_packages.py source dist %*
if errorlevel 1 goto failed

echo === 2/2 Mengunggah ke R2 ===
python tools\upload_r2.py dist
if errorlevel 1 goto failed

echo.
echo Selesai. Tarik layar di aplikasi untuk melihat manual terbaru.
pause
exit /b 0

:failed
echo.
echo Gagal. Baca pesan di atas.
pause
exit /b 1
