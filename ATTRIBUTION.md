# Атрибуция ассетов

Все внешние ассеты — **CC0 / public domain** (либо MIT для кода движка). Всё вендорено локально
в репозитории, игра работает офлайн, ничего не грузится в рантайме. Пересобрать набор:
`node tools/fetch-assets.mjs`.

> IP-гигиена (правило `CLAUDE.md`): чужой контент один-в-один не копируется, механики — «по мотивам»,
> названия/описания способностей — оригинальные. Ниже — только реально используемые внешние файлы.

---

## Текстуры — Poly Haven (CC0)

Источник: <https://polyhaven.com>. Лицензия: CC0. Разрешение 1k, формат JPG (diffuse + normal + ARM).

| В игре | Слаг Poly Haven | Файлы |
|--------|-----------------|-------|
| Пол игровой зоны | `concrete_floor_02` | `public/assets/textures/floor/{diffuse,normal,arm}.jpg` |
| Внешняя земля | `gravel_concrete_03` | `public/assets/textures/ground/…` |
| Стены и крупные боксы | `concrete_wall_008` | `public/assets/textures/wall/…` |
| Деревянные ящики | `wood_planks` | `public/assets/textures/wood/…` |

Godot-порт использует те же наборы, скопированные в `godot/assets/textures/<набор>/` (фаза G10):
стены и ступени, пол игровой зоны, деревянные ящики. Лицензия та же — CC0.

## 3D-модели Godot-порта (CC0), фаза G12 «Визуал»

Все паки — CC0, вендорены в `godot/assets/models/…`, рядом с каждым лежит `LICENSE.txt` из архива.

| В игре | Автор / пак | Источник | Файлы |
|--------|-------------|----------|-------|
| Бойцы (риг Mixamo, анимации Idle/Walk/Run/Jump/Death, 6 текстур одежды) | Quaternius — «Animated Human» | зеркало на OpenGameArt: <https://opengameart.org/content/animated-human-low-poly> | `characters/quaternius/human.fbx`, `Textures/*.png` |
| Автоматы и винтовки | Quaternius — «GunPack Vol.1» (AK-47, винтовка) | <https://opengameart.org/content/low-poly-guns> | `weapons/quaternius/*.obj`, `*.mtl`, `*Texture.png` |
| Пистолеты, ПП, дробовики | Kenney — «Blaster Kit» 2.1 | <https://kenney.nl/assets/blaster-kit> | `weapons/blaster/*.glb`, `Textures/colormap.png` |
| Ящики на картах | Kenney — «Prototype Kit» | <https://kenney.nl/assets/prototype-kit> | `props/prototype/*.glb`, `Textures/colormap.png` |

Стволы «по мотивам»: реальные названия оружия из веб-баланса сопоставлены низкополигональным
моделям без копирования чужих игровых ассетов (правило 6).

## Небо / освещение (IBL) — Poly Haven (CC0)

| В игре | Слаг | Файл |
|--------|------|------|
| Небо + свет | `kloppenheim_06_puresky` | `public/assets/hdri/sky.hdr` |

В Godot-порте тот же HDRI лежит в `godot/assets/hdri/sky.hdr` и работает как PanoramaSkyMaterial
(небо + небесное освещение и отражения), фаза G10.

---

## Звук (CC0)

Разложено в `public/assets/sfx/`. Три источника, все public domain:

**OpenGameArt.org (CC0).** Оружие, перезарядка, шаги, взрыв:
- Выстрелы: `22 Pistol` → `gun_pistol.wav`, `22 Magnum` → `gun_magnum.wav`,
  `Black Powder` → `gun_heavy.wav`, `Unkown` → `gun_rifle.wav`.
- Перезарядка: `clipload1/2` → `reload1/2.wav`.
- Шаги: `01–06 footstep` → `step1…6.ogg`.
- Взрыв: `explosion1` → `explosion.ogg`.

**rubberduck — паки «100 CC0 SFX» и «SFX 100 v2» (OpenGameArt, CC0).** Фидбек/скиллы/шип/UI:
- `hit`, `metal` (→ `ting`), `slam`, `plop` (→ `pop`), `bell` (→ `buff`/`confirm`), `gong` (→ `fail`),
  `weird` (→ `energy`/`zap`), `metal` (→ `clunk`), `air` (→ `whoosh`/`whoosh2`), `hit` (→ `hurt`),
  `thunder` (→ `boom`).

**Kenney — UI Audio (public domain / CC0).** <https://kenney.nl>:
- `click1/2` → `ui_click.wav`, `ui_confirm.wav`.

> Осцилляторный синтез в `public/js/audio.js` — НЕ основной звук, а фолбэк (если сэмпл не догрузился)
> и характерная озвучка без готового CC0-аналога (курица/кони/пожирание/огонь) + чистый синус-бип шипа.

---

## 3D-модели (CC0)

- `public/assets/models/characters/_demo.glb` — **RobotExpressive**, three.js examples
  (Tomás Laulhé / Quaternius), **CC0**. Подключается только при `window.USE_DEMO_MODELS = true`.
- **KayKit Character Pack: Adventurers** (Kay Lousberg, <https://kaylousberg.com>), **CC0** —
  инфраструктура drop-in присутствует, но по умолчанию **не активна** (`manifest.json → characterModels: {}`).
  По умолчанию агенты рисуются **процедурным человечком** (собственный код, внешних ассетов нет).

---

## Код движка

- **three.js** (r160) — лицензия **MIT**. Вендорено в `public/js/three*` и `public/js/three/`.
- **ws** (npm) — лицензия **MIT**. Серверный WebSocket.

---

*Если добавляешь ассет — впиши сюда источник и лицензию (только CC0/PD или совместимую). Правило `CLAUDE.md`.*
