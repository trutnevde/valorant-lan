@echo off
chcp 65001 >nul
title VALORANT LAN — сервер
cd /d "%~dp0"

if not exist node_modules (
  echo === Первый запуск: ставлю зависимости (npm install), подожди минутку ===
  call npm install
  echo.
)

echo ==========================================================
echo   Запускаю сервер VALORANT LAN.
echo   НЕ ЗАКРЫВАЙ это окно, пока играете.
echo   Ссылки для друзей появятся ниже.
echo   Остановить — Ctrl+C или просто закрой окно.
echo ==========================================================
echo.

call npm start

echo.
echo === Сервер остановлен. ===
pause
