@echo off
rem Upload only the employee list (karyawan.xlsx next to this file), e.g.
rem after adding a mechanic or changing a starting PIN. No manuals are built.
setlocal
cd /d "%~dp0"

if not exist r2-keys.bat (
  echo File r2-keys.bat belum ada.
  pause
  exit /b 1
)
call r2-keys.bat
if not exist karyawan.xlsx (
  echo File karyawan.xlsx belum ada. Salin karyawan-contoh.xlsx menjadi karyawan.xlsx lalu isi.
  pause
  exit /b 1
)
python -m pip install --disable-pip-version-check -q -r tools\requirements.txt
python tools\upload_karyawan.py karyawan.xlsx
if errorlevel 1 (
  echo.
  echo Gagal. Baca pesan di atas.
  pause
  exit /b 1
)
echo.
echo Selesai.
pause
