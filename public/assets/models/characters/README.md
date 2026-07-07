# Модели персонажей (GLTF)

Здесь лежат **скелетно-анимированные** модели агентов (`.glb`).
Сейчас по умолчанию подключён CC0-пак **KayKit Character Pack: Adventurers** (Kay Lousberg):
стилизованные риггнутые персонажи с оружием и анимациями (idle/walk/run/death).

Маппинг «агент → модель» задан в `../../manifest.json` → `characterModels`.
8 агентов делят 5 моделей, каждый тонируется в свой цвет для идентичности:

| Агент | Модель |
|-------|--------|
| artemiy, koniliy | Knight.glb |
| max | Rogue.glb |
| sanek, fafik | Rogue_Hooded.glb |
| vova, ira | Mage.glb |
| denis | Barbarian.glb |

Нет модели / пустой `characterModels` → рисуется процедурный человечек (как раньше). Никакой регрессии.

## Заменить на свои модели (например, реалистичные солдаты из Mixamo)

KayKit — стилизованные фэнтези-воины (это то, что есть в CC0 бесплатно). Хочешь реалистичных
солдат — сделай своих:

1. Возьми риггнутого персонажа на [mixamo.com](https://www.mixamo.com) (бесплатно, вход Adobe),
   накинь анимации, где в именах есть `idle`/`walk`/`run`/`death`, и скачай **.glb** (glTF Binary).
2. Положи файл сюда и пропиши в `../../manifest.json`:
   ```json
   "characterModels": { "artemiy": "MySoldier.glb", ... }
   ```
   (можно указать один файл для всех агентов или свой на каждого).
3. Готово — агент рисуется твоей моделью, хитбоксы (голова/тело/ноги, хедшоты) навешиваются сами.

## Технические заметки
- Модель авто-масштабируется к росту ~1.8 юнита, ступни ставятся на землю, лицо — по −Z.
  Смотрит не туда → поправь `model.rotation.y` в `../../../js/loaders.js` (`makeGltfCharacter`).
- Клипы выбираются по именам (точное совпадение → подстрока): idle/walk/run/death. Разные паки/Mixamo ок.
- Демо-режим `window.USE_DEMO_MODELS = true` подставит `_demo.glb` (RobotExpressive, CC0) всем.
- Всё офлайн: `GLTFLoader`/`SkeletonUtils` вендорены в `../../../js/three/`, модели — локальные файлы.
- Пересоздать всё: `node tools/fetch-assets.mjs` (качает текстуры/HDRI/модели заново).

## Лицензии
- Персонажи: **CC0** — KayKit Character Pack: Adventurers, Kay Lousberg (kaylousberg.com).
- `_demo.glb`: **CC0** — RobotExpressive (three.js examples, Tomás Laulhé / Quaternius).
