@echo off
rem Update only some unit folders: lists the unit folders in source\ (per
rem section), asks which ones, then runs update.bat for those only. Other
rem units stay as they are.
setlocal
cd /d "%~dp0"

echo Folder unit di source:
python tools\build_packages.py source --list
echo.
set /p UNIT=Ketik nama folder yang mau di-update (lebih dari satu: pisahkan dengan spasi): 
if "%UNIT%"=="" exit /b 0
call update.bat --only %UNIT%
