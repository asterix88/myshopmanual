@echo off
rem Deploys the AI server (ai-worker\) to Cloudflare as ai.mymanual.my.id.
rem Needs Node.js (nodejs.org). The first time, run:  deploy-ai.bat kunci
rem to also store the Anthropic API key on Cloudflare (it is never saved here).
setlocal
cd /d "%~dp0ai-worker"

echo === 1/2 Menyiapkan ===
call npm install --no-audit --no-fund
if errorlevel 1 goto failed

echo === 2/2 Deploy ke Cloudflare (login di browser kalau diminta) ===
call npx wrangler deploy
if errorlevel 1 goto failed

if /i "%~1"=="kunci" (
  echo.
  echo Tempel kunci API Anthropic, lalu tekan Enter:
  call npx wrangler secret put ANTHROPIC_API_KEY
  if errorlevel 1 goto failed
)

echo.
echo Selesai. Cek https://ai.mymanual.my.id harus menampilkan {"ok":true}
pause
exit /b 0

:failed
echo.
echo Gagal. Baca pesan di atas.
pause
exit /b 1
