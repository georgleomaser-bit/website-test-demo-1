@echo off
chcp 65001 >nul
title AKYTEX - Server
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo  Node.js fehlt noch. Bitte die LTS-Version von https://nodejs.org installieren
  echo  und danach diese Datei erneut doppelklicken.
  start https://nodejs.org
  pause
  exit /b
)
node server\start-public.mjs
pause
