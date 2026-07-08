// Скачивает CC0-ассеты с Poly Haven и вендорит их локально в public/assets/.
// После запуска игра остаётся полностью офлайн — файлы лежат в репозитории.
// Запуск:  node tools/fetch-assets.mjs
// Лицензия всех ассетов: CC0 (public domain). Источник: https://polyhaven.com
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ASSETS = path.join(ROOT, 'public', 'assets');
const RES = '1k';        // разрешение: 1k достаточно и легковесно
const FMT = 'jpg';       // формат текстур

// какие текстурные наборы тянем и куда они идут в игре
const TEXTURES = [
  { slug: 'concrete_floor_02', name: 'floor' },   // пол играбельной зоны
  { slug: 'gravel_concrete_03', name: 'ground' }, // внешняя земля
  { slug: 'concrete_wall_008', name: 'wall' },    // стены/крупные боксы
  { slug: 'wood_planks', name: 'wood' },          // деревянные ящики
];
const HDRIS = [
  { slug: 'kloppenheim_06_puresky', name: 'sky' }, // небо + свет (IBL)
];
// из набора берём: albedo(Diffuse), normal(nor_gl), arm(AO+Rough+Metal упаковка)
const MAPS = { diffuse: 'Diffuse', normal: 'nor_gl', arm: 'arm' };

// Персонажи по умолчанию — процедурные (см. buildHumanoid в remote.js), characterModels пуст.
// Демо-модель только для window.USE_DEMO_MODELS (three.js examples, CC0).
const DEMO_URL = 'https://raw.githubusercontent.com/mrdoob/three.js/r160/examples/models/gltf/RobotExpressive/RobotExpressive.glb';

function mkdir(p) { fs.mkdirSync(p, { recursive: true }); }

async function getJSON(url) {
  for (let i = 0; i < 3; i++) {
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(30000) });
      if (r.ok) return await r.json();
    } catch (e) { /* retry */ }
    await new Promise(r => setTimeout(r, 800));
  }
  throw new Error('JSON fail: ' + url);
}

async function download(url, dest) {
  if (fs.existsSync(dest) && fs.statSync(dest).size > 1024) {
    console.log('  ✓ уже есть', path.basename(dest));
    return;
  }
  mkdir(path.dirname(dest));
  // curl надёжнее node-fetch для CDN Poly Haven (следует редиректам, не рвёт поток)
  execFileSync('curl', ['-sL', '--fail', '--retry', '4', '--retry-delay', '2',
    '--max-time', '180', '-o', dest, url], { stdio: 'ignore' });
  const sz = fs.statSync(dest).size;
  if (sz < 1024) throw new Error('слишком мал: ' + dest);
  console.log('  ⬇', path.basename(dest), (sz / 1e6).toFixed(2) + ' МБ');
}

function pickUrl(node) {
  // node = files[MapKey]; идём files[key][RES][FMT].url
  const res = node?.[RES] || node?.['2k'] || node?.['4k'];
  const f = res?.[FMT] || res?.png || res?.jpg;
  return f?.url;
}

async function main() {
  mkdir(ASSETS);
  const manifest = { license: 'CC0 — polyhaven.com', textures: {}, hdri: {} };

  for (const { slug, name } of TEXTURES) {
    console.log('▶ текстура', name, '(' + slug + ')');
    const files = await getJSON('https://api.polyhaven.com/files/' + slug);
    const dir = path.join(ASSETS, 'textures', name);
    const set = {};
    for (const [local, key] of Object.entries(MAPS)) {
      const url = pickUrl(files[key]);
      if (!url) { console.log('  ⚠ нет карты', key); continue; }
      const dest = path.join(dir, local + '.' + FMT);
      await download(url, dest);
      set[local] = 'assets/textures/' + name + '/' + local + '.' + FMT;
    }
    manifest.textures[name] = { slug, ...set };
  }

  for (const { slug, name } of HDRIS) {
    console.log('▶ hdri', name, '(' + slug + ')');
    const files = await getJSON('https://api.polyhaven.com/files/' + slug);
    const url = files?.hdri?.[RES]?.hdr?.url || files?.hdri?.['2k']?.hdr?.url;
    if (!url) { console.log('  ⚠ нет hdr'); continue; }
    const dest = path.join(ASSETS, 'hdri', name + '.hdr');
    await download(url, dest);
    manifest.hdri[name] = 'assets/hdri/' + name + '.hdr';
  }

  // ── демо-модель (window.USE_DEMO_MODELS). Персонажи по умолчанию — процедурные (characterModels пуст) ──
  const charDir = path.join(ASSETS, 'models', 'characters');
  try { console.log('▶ демо-модель RobotExpressive'); await download(DEMO_URL, path.join(charDir, '_demo.glb')); }
  catch (e) { console.log('  ⚠ демо не скачалась:', e.message); }
  manifest.characterModels = {};

  fs.writeFileSync(path.join(ASSETS, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log('\n✅ Ассеты скачаны. manifest.json записан. Всё CC0, лежит локально.');
}
main().catch(e => { console.error('✖', e.message); process.exit(1); });
