@echo off
rem Гейт Godot-порта: импорт -> GUT -> веб-гейт из корня. Запуск из папки godot/.
rem (ботматч и hitreg добавятся в G2 — см. CLAUDE.md)
setlocal
set GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe

echo === [1/3] import-check ===
"%GODOT%" --headless --path . --import || goto :fail

echo === [2/3] GUT ===
"%GODOT%" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit || goto :fail

echo === [3/3] web gate (invariant #1) ===
pushd ..
call npm run gate || (popd & goto :fail)
popd

echo.
echo ===== GODOT GATE: GREEN =====
exit /b 0

:fail
echo.
echo ===== GODOT GATE: RED =====
exit /b 1
