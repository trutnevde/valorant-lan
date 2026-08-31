// Генерирует godot/src/core/balance.gd из среза ../public/js/shared.js.
// Паритет: числа НЕ трогать руками — только перегенерация этим скриптом (хэш среза в VERSIONS.md).
// Запуск из корня репы:  node godot/tools/port_balance.mjs
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';
import {
  RULES, WEAPONS, WEAPON_FEEL, ARMOR, CHARACTERS, ABILITY, MOVE,
  BOT_PRESETS, PASSIVES, SIGNATURES, MAPS,
} from '../../public/js/shared.js';

// слим-каталог карт (id → отображаемое имя/размер) — для лобби и валидации; геометрия карт
// живёт в .tscn (convert_maps.mjs), сюда числа баланса не входят.
const MAP_CATALOG = {};
for (const id of Object.keys(MAPS)) {
  MAP_CATALOG[id] = { name: MAPS[id].name || id, w: MAPS[id].SIZE.w, d: MAPS[id].SIZE.d };
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(__dirname, '..', 'src', 'core', 'balance.gd');

// JSON-литерал = валидный литерал словаря GDScript (ключи в кавычках, true/false/null совпадают)
const gd = (o) => JSON.stringify(o, null, '\t');

let hash = 'unknown';
try { hash = execSync('git rev-parse --short HEAD', { cwd: path.join(__dirname, '..', '..') }).toString().trim(); } catch {}

const body = `# balance.gd — АВТОГЕНЕРАЦИЯ из ../public/js/shared.js (срез: коммит ${hash}).
# НЕ ПРАВИТЬ РУКАМИ. Перегенерация: node godot/tools/port_balance.mjs (из корня репы).
# Паритет с веб-версией: все игровые числа берутся ТОЛЬКО отсюда (правило 3 godot/CLAUDE.md).
class_name Balance

const SNAPSHOT_HASH := "${hash}"

const RULES := ${gd(RULES)}

const WEAPONS := ${gd(WEAPONS)}

const WEAPON_FEEL := ${gd(WEAPON_FEEL)}

const ARMOR := ${gd(ARMOR)}

const CHARACTERS := ${gd(CHARACTERS)}

const ABILITY := ${gd(ABILITY)}

const MOVE := ${gd(MOVE)}

const BOT_PRESETS := ${gd(BOT_PRESETS)}

const PASSIVES := ${gd(PASSIVES)}

const SIGNATURES := ${gd(SIGNATURES)}

const MAPS := ${gd(MAP_CATALOG)}


static func weapon_feel(id: String) -> Dictionary:
	var w: Dictionary = WEAPONS.get(id, {})
	return WEAPON_FEEL.get(w.get("cat", "pistol"), WEAPON_FEEL["pistol"])
`;

writeFileSync(OUT, body.replace(/\r?\n/g, '\n'), 'utf8');
console.log('balance.gd записан (' + body.length + ' байт), срез=' + hash);
