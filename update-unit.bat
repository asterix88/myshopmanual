@echo off
rem Update only some unit folders: lists the folders in source\, asks which
rem ones, then runs update.bat for those only. Other units stay as they are.
setlocal
cd /d "%~dp0"

echo Folder di source:
for /d %%D in (source\*) do echo   %%~nxD
echo.
set /p UNIT=Ketik nama folder yang mau di-update (lebih dari satu: pisahkan dengan spasi): 
if "%UNIT%"=="" exit /b 0
call update.bat --only %UNIT%
