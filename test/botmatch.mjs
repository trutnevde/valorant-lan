// Headless бот-матч с телеметрией. Поднимает сервер, набивает команды ботами, стартует матч,
// наблюдает бродкасты состояний/выстрелов/урона и стдаут сервера (p95 тика). Проверяет пороги
// из test/gate.config.json: сквозь-стены = 0, застреваний = 0, точность ботов в коридоре, p95 тика.
import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import { readFileSync } from 'fs';
import WebSocket from 'ws';
import { MAPS, mapAabbs } from '../public/js/shared.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CFG = JSON.parse(readFileSync(path.join(__dirname, 'gate.config.json'), 'utf8')).botmatch;
const DIFF = process.env.BOT_DIFF || '';   // прогон метрик по пресету: easy|medium|hard (пусто = дефолт лобби)
const PORT = 27019;
const BOT_R = 0.34;

// барьеры карты = НАСТОЯЩИЕ стены (h>=2.9), как в коллизии ботов
const barriers = mapAabbs(MAPS[CFG.map])
  .filter(b => (b.maxY - b.minY) >= 2.9 && b.minY < 1.5)
  .map(b => ({ x0: b.minX, x1: b.maxX, z0: b.minZ, z1: b.maxZ }));
const insideWall = (x, z) => barriers.some(b => x > b.x0 + 0.1 && x < b.x1 - 0.1 && z > b.z0 + 0.1 && z < b.z1 - 0.1);
const distToWall = (x, z) => {
  let best = Infinity;
  for (const b of barriers) {
    const dx = Math.max(b.x0 - x, 0, x - b.x1), dz = Math.max(b.z0 - z, 0, z - b.z1);
    best = Math.min(best, Math.hypot(dx, dz));
  }
  return best;
};

const server = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
  env: { ...process.env, PORT: String(PORT), TICK_TELEMETRY: '1' }, stdio: ['ignore', 'pipe', 'pipe'],
});
const tickWins = [];   // p95 каждого окна тиков; берём МЕДИАНУ (устойчива к разовому GC-спайку)
let botHits = 0, botShots = 0;   // BOTACC = серверный счётчик ТОЛЬКО пуль ботов
server.stdout.on('data', (d) => {
  for (const line of d.toString().split('\n')) {
    const m = line.match(/TICKP95 ([\d.]+)/);
    if (m) tickWins.push(parseFloat(m[1]));
    const a = line.match(/BOTACC (\d+) (\d+)/);
    if (a) { botHits = parseInt(a[1], 10); botShots = parseInt(a[2], 10); }  // накопительно — берём последнее
  }
});
const median = (arr) => { if (!arr.length) return 0; const s = [...arr].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };
server.stderr.on('data', d => console.error('[server err]', d.toString().trim()));

const waitListen = new Promise((res) => {
  server.stdout.on('data', (d) => { if (d.toString().includes('запущен')) res(); });
});
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// телеметрия
const pos = new Map();       // id -> [{x,z,t}]
let rounds = 0;
let wallclip = 0, wallstuck = 0;
const clipSeen = new Set(), stuckSeen = new Set();

const t0 = () => Date.now() / 1000;

function onState(id, p) {
  const arr = pos.get(id) || []; pos.set(id, arr);
  arr.push({ x: p[0], z: p[2], t: t0() });
  if (arr.length > 400) arr.shift();
  if (insideWall(p[0], p[2]) && !clipSeen.has(id)) { clipSeen.add(id); wallclip++; }
  // застревание: не двигался stuckSeconds И прижат к стене
  const now = t0(); const win = arr.filter(s => now - s.t <= CFG.stuckSeconds);
  if (win.length >= 8 && (now - win[0].t) >= CFG.stuckSeconds - 0.3) {
    let moved = 0; for (let i = 1; i < win.length; i++) moved += Math.hypot(win[i].x - win[i - 1].x, win[i].z - win[i - 1].z);
    const jammed = distToWall(p[0], p[2]) < BOT_R + 0.2;
    if (moved < CFG.stuckMoveEps && jammed && !stuckSeen.has(id)) { stuckSeen.add(id); wallstuck++; }
    if (moved >= CFG.stuckMoveEps) stuckSeen.delete(id); // снова поехал — сбрасываем
  }
}

async function main() {
  await waitListen;
  const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
  let myId = 0, myTeam = 'A';
  await new Promise((res) => ws.on('open', res));
  ws.on('message', (raw) => {
    const m = JSON.parse(raw);
    if (m.t === 'welcome') myId = m.id;
    else if (m.t === 'lobby') { const me = (m.players || []).find(p => p.id === myId); if (me) myTeam = me.team; if (m.difficulty) globalThis.__diff = m.difficulty; }
    else if (m.t === 'state') onState(m.id, m.p);
    else if (m.t === 'roundStart') rounds++;
  });
  const send = (o) => ws.send(JSON.stringify(o));
  send({ t: 'join', name: 'Наблюдатель', char: 'artemiy' });
  await sleep(400);
  send({ t: 'setMap', map: CFG.map });
  if (DIFF) send({ t: 'setDifficulty', difficulty: DIFF });   // прогон метрик по пресету сложности
  await sleep(200);
  const other = myTeam === 'A' ? 'B' : 'A';
  for (let i = 0; i < CFG.botsPerTeam - 1; i++) send({ t: 'addBot', team: myTeam });
  for (let i = 0; i < CFG.botsPerTeam; i++) send({ t: 'addBot', team: other });
  await sleep(500);
  send({ t: 'startMatch' });

  const start = Date.now();
  while (rounds < CFG.rounds && Date.now() - start < CFG.maxDurationMs) await sleep(250);
  await sleep(500);
  try { ws.close(); } catch {}
  server.kill();

  const shots = botShots, acc = shots > 0 ? botHits / shots : 0;
  const tickMed = median(tickWins), tickMax = tickWins.length ? Math.max(...tickWins) : 0;
  console.log(`\n— БОТ-МАТЧ (${CFG.map}, сложность ${globalThis.__diff || '?'}, раундов ${rounds}) —`);
  console.log(`  сквозь стены: ${wallclip} (порог ${CFG.maxWallclip})`);
  console.log(`  застреваний у стен: ${wallstuck} (порог ${CFG.maxWallstuck})`);
  console.log(`  выстрелов ботов: ${shots}, попаданий: ${botHits}, точность: ${(acc * 100).toFixed(1)}% (коридор ${CFG.accuracyMin * 100}–${CFG.accuracyMax * 100}%)`);
  console.log(`  время тика: медиана p95 ${tickMed.toFixed(2)} мс (порог ${CFG.tickP95MaxMs}), макс окна ${tickMax.toFixed(2)} мс, окон ${tickWins.length}`);

  const fails = [];
  if (wallclip > CFG.maxWallclip) fails.push('боты проходят сквозь стены');
  if (wallstuck > CFG.maxWallstuck) fails.push('боты застревают у стен');
  if (rounds < 1) fails.push('матч не пошёл (0 раундов)');
  if (shots < 20) fails.push('боты почти не стреляли (мало данных)');
  else if (!DIFF && (acc < CFG.accuracyMin || acc > CFG.accuracyMax)) fails.push(`точность вне коридора: ${(acc * 100).toFixed(1)}%`); // коридор — только для дефолтной (medium) сложности
  if (tickMed > CFG.tickP95MaxMs) fails.push(`медиана p95 тика ${tickMed.toFixed(2)} > ${CFG.tickP95MaxMs} мс`);

  if (fails.length) { console.log('\n✖ БОТ-МАТЧ: ' + fails.join('; ')); process.exit(1); }
  console.log('\n✅ БОТ-МАТЧ: телеметрия в норме');
  process.exit(0);
}
main().catch(e => { console.error('botmatch error:', e); try { server.kill(); } catch {} process.exit(1); });
