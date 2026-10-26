@echo off
rem Save Caterpillar SIS 2.0 documents as PDFs with text, into source\<folder>.
rem Opens Chrome (or Edge); log in to SIS there, search and filter, then
rem follow the steps shown in this window.
setlocal
cd /d "%~dp0"

echo === Memeriksa paket Python ===
python -m pip install --disable-pip-version-check -q playwright
if errorlevel 1 goto failed

echo.
echo Contoh nama folder: CAT395\Disassembly and Assembly
set /p "FOLDER=Simpan ke folder source\ apa? "
if "%FOLDER%"=="" exit /b 0

python tools\sis_download.py "source\%FOLDER%"
if errorlevel 1 goto failed
pause
exit /b 0

:failed
echo.
echo Ada yang gagal. Lihat pesan di atas.
pause
exit /b 1
