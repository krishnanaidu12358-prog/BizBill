@echo off
rem BizBill - compile check for the API and the Flutter app.
rem Writes everything to build-check.log next to this file.
set LOG=%~dp0build-check.log
echo BizBill build check %date% %time% > "%LOG%"

echo. >> "%LOG%"
echo ===== API: dotnet build ===== >> "%LOG%"
cd /d "%~dp0API\BizFlow.Api"
dotnet build -nologo -v q -o "%TEMP%\bizbill-check" >> "%LOG%" 2>&1
echo API EXIT %ERRORLEVEL% >> "%LOG%"

echo. >> "%LOG%"
echo ===== App: flutter analyze ===== >> "%LOG%"
cd /d "%~dp0Frontend"
call flutter pub get >> "%LOG%" 2>&1
call flutter analyze --no-fatal-infos --no-fatal-warnings >> "%LOG%" 2>&1
echo APP EXIT %ERRORLEVEL% >> "%LOG%"

echo ===== DONE ===== >> "%LOG%"
