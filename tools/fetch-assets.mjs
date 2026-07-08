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

// CC0-звуки (OpenGameArt, public domain): реальные выстрелы/перезарядка/шаги/взрыв → assets/sfx/
const OGA = 'https://opengameart.org/sites/default/files';
const SFX = [
  ['22%20Pistol.wav', 'gun_pistol.wav'], ['22%20Magnum.wav', 'gun_magnum.wav'],
  ['Black%20Powder.wav', 'gun_heavy.wav'], ['Unkown.wav', 'gun_rifle.wav'],
  ['clipload1.wav', 'reload1.wav'], ['clipload2.wav', 'reload2.wav'],
  ['01-footstep_0.ogg', 'step1.ogg'], ['02-footstep.ogg', 'step2.ogg'], ['03-footstep.ogg', 'step3.ogg'],
  ['04-footstep.ogg', 'step4.ogg'], ['05-footstep.ogg', 'step5.ogg'], ['06-footstep.ogg', 'step6.ogg'],
  ['explosion1_0.ogg', 'explosion.ogg'],
];
// звуки скиллов/шипа/фидбека из CC0-паков rubberduck «100 CC0 SFX» (zip). Нужен unzip в PATH.
const SFX_ZIPS = [
  { url: `${OGA}/100-CC0-SFX_0.zip`, pick: {
    'hit_01.ogg': 'hit.ogg', 'metal_02.ogg': 'ting.ogg', 'slam_02.ogg': 'slam.ogg', 'plop_01.ogg': 'pop.ogg',
    'bell_02.ogg': 'buff.ogg', 'bell_01.ogg': 'confirm.ogg', 'gong_01.ogg': 'fail.ogg',
    'weird_01.ogg': 'energy.ogg', 'weird_03.ogg': 'zap.ogg', 'metal_05.ogg': 'clunk.ogg' } },
  { url: `${OGA}/sfx_100_v2.zip`, pick: {
    'sfx100v2_air_01.ogg': 'whoosh.ogg', 'sfx100v2_air_02.ogg': 'whoosh2.ogg',
    'sfx100v2_hit_02.ogg': 'hurt.ogg', 'sfx100v2_thunder_01.ogg': 'boom.ogg' } },
];
// UI-клики Kenney (CC0)
const KENNEY_UI = 'https://raw.githubusercontent.com/Calinou/kenney-ui-audio/master/addons/kenney_ui_audio';

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

  // ── звуки (CC0, OpenGameArt) ──
  const sfxDir = path.join(ASSETS, 'sfx');
  for (const [src, dst] of SFX) {
    console.log('▶ звук', dst);
    await download(`${OGA}/${src}`, path.join(sfxDir, dst));
  }
  // доп. звуки скиллов/шипа/UI из zip-паков (best-effort, нужен unzip; файлы и так лежат в репо)
  for (const z of SFX_ZIPS) {
    try {
      const tmp = path.join(ASSETS, '_tmp_sfx');
      const zip = path.join(tmp, 'p.zip');
      await download(z.url, zip);
      execFileSync('unzip', ['-o', '-q', zip, '-d', tmp], { stdio: 'ignore' });
      const all = [];
      (function walk(d) { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); if (fs.statSync(p).isDirectory()) walk(p); else all.push(p); } })(tmp);
      for (const [src, dst] of Object.entries(z.pick)) {
        const hit = all.find(p => path.basename(p) === src);
        if (hit) fs.copyFileSync(hit, path.join(sfxDir, dst));
      }
      fs.rmSync(tmp, { recursive: true, force: true });
      console.log('▶ звуки из', path.basename(z.url), '✓');
    } catch (e) { console.log('  ⚠ пропущен', path.basename(z.url), '(нужен unzip):', e.message); }
  }
  try {
    await download(`${KENNEY_UI}/click1.wav`, path.join(sfxDir, 'ui_click.wav'));
    await download(`${KENNEY_UI}/click2.wav`, path.join(sfxDir, 'ui_confirm.wav'));
  } catch (e) { console.log('  ⚠ Kenney UI пропущен:', e.message); }
  manifest.sfxLicense = 'CC0 — OpenGameArt (rubberduck, Brian MacIntosh) + Kenney UI (public domain)';

  fs.writeFileSync(path.join(ASSETS, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log('\n✅ Ассеты скачаны. manifest.json записан. Всё CC0, лежит локально.');
}
main().catch(e => { console.error('✖', e.message); process.exit(1); });
