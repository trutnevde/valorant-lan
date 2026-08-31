# CLAUDE.md — Godot-порт

Порт браузерного тактического шутера на Godot 4 + типизированный GDScript. Канон механик — ../DESIGN.md и ../AGENTS.md. Числа — из зафиксированного среза ../public/js/shared.js (хэш в VERSIONS.md). Веб-версия в корне репы неприкосновенна.

## Команды
- `godot --headless --import` — ОБЯЗАТЕЛЬНО после добавления/замены любых ассетов
- `godot --headless --script res://<файл>.gd --check-only` — синтакс-чек изменённых скриптов перед коммитом
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` — юнит-гейт
- `godot --headless -s res://tools/botmatch.gd -- --preset=medium --rounds=3` — ботматч с телеметрией (JSON в stdout)
- `godot --path . res://tools/agent_eyes.tscn -- --scene=<сцена> --frames=90 --out=<png>` — скриншот-глаза (мигнёт окно, PNG на диск)
- `godot --headless --export-release "Windows Desktop" build/game.exe` — сборка

## Гейт перед каждым коммитом (godot/gate.bat)
check-only изменённых скриптов → импорт-чек → GUT → ботматч (застреваний 0, сквозь-стен 0, точность в коридоре пресета) → hitreg-санити (фиксированный сид → фиксированное попадание) → `npm run gate` веб-версии из корня.

## Правила
1. Системы движка вместо самопала: NavigationServer, AnimationTree, AudioStreamPlayer3D, GPUParticles3D, CharacterBody3D.
2. Сцены (.tscn) правятся как текст; не редактировать сцену одновременно в редакторе и агентом.
3. Все игровые числа — только через res://src/core/balance.gd (портированный срез shared.js). Хардкод чисел в сценах/скриптах запрещён.
4. Каждая способность — отдельная сцена-компонент в scenes/agents/<агент>/, подключаемая к игроку; никаких switch-простыней на 10 агентов в одном файле.
5. Скриншот-пруфы в отчёте фазы: минимум 2 PNG через agent_eyes.
6. Перф-бюджет: 60 FPS на средней видеокарте; замер — 60-сек виндовый прогон с дампом Performance-мониторов в лог.
7. Звук — механика: шаги слышны (у ботов — событийная модель слуха), Shift/присед бесшумны, синтез запрещён.
8. Теги godot-v0.X.Y-имя, записи в ../VERSIONS.md с префиксом [GODOT].

## Локальный путь к Godot (эта машина)
`godot` в командах выше = `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe` (4.7.stable.official). Запуск из папки `godot/` с `--path .`.
