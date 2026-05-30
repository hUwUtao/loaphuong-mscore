@echo off
setlocal enabledelayedexpansion

echo === loaphuong Windows Deploy ===
echo.

REM --- VST3 ---
set VST3_DST=%USERPROFILE%\Documents\VST3\loaphuong.vst3
if not exist "%USERPROFILE%\Documents\VST3" mkdir "%USERPROFILE%\Documents\VST3"
if exist "%VST3_DST%" rmdir /s /q "%VST3_DST%"
xcopy /s /e /i "%~dp0loaphuong.vst3" "%VST3_DST%"
echo [OK] VST3 installed to %VST3_DST%

REM --- MuseScore QML Plugin ---
set QML_DST=%USERPROFILE%\Documents\MuseScore4\Plugins\loaphuong\
if not exist "%QML_DST%" mkdir "%QML_DST%"
copy /y "%~dp0loaphuong.qml" "%QML_DST%loaphuong.qml" >nul
echo [OK] QML plugin installed to %QML_DST%

REM --- Backend (copy alongside) ---
echo [OK] Backend loaphuong.exe is here: %~dp0loaphuong.exe
echo.

echo === Done! ===
echo.
echo Next steps:
echo   1. Enable plugin in MuseScore: Plugins -^> Manage Plugins -^> loaphuong
echo   2. Set NEUTRINO_ROOT env var or place NEUTRINO/ next to loaphuong.exe
echo   3. Run: loaphuong.exe
echo   4. In MuseScore, run Plugins -^> loaphuong
echo.
pause
