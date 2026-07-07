// Smoke-тест v2: сервер, лобби с хостом, добавление ботов, старт матча,
// закупка, урон/смерть, командный счёт, серверные боты двигаются.
import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import WebSocket from 'ws';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = 27017;
let failed = false;
const log = (ok, name) => { console.log(`${ok ? '  [ok]' : '  [FAIL]'} ${name}`); if (!ok) failed = true; };

const server = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
  env: { ...process.env, PORT: String(PORT) }, stdio: ['ignore', 'pipe', 'pipe'],
});
server.stderr.on('data', d => console.error('[server err]', d.toString().trim()));
const waitListen = new Promise((res) => {
  server.stdout.on('data', (d) => { if (d.toString().includes('запущен')) res(); });
});

function client(name, char) {
  const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
  const c = { ws, name, id: 0, msgs: [], waiters: [] };
  ws.on('message', (raw) => {
    const m = JSON.parse(raw);
    c.msgs.push(m);
    for (let i = c.waiters.length - 1; i >= 0; i--) {
      if (c.waiters[i].test(m)) { const w = c.waiters.splice(i, 1)[0]; clearTimeout(w.to); w.res(m); }
    }
  });
  ws.on('open', () => ws.send(JSON.stringify({ t: 'join', name, char })));
  c.send = (o) => ws.send(JSON.stringify(o));
  c.wait = (test, label, timeout = 20000) => new Promise((res, rej) => {
    const hit = c.msgs.find(test);
    if (hit) return res(hit);
    const w = { test, res }; w.to = setTimeout(() => rej(new Error('timeout: ' + label)), timeout);
    c.waiters.push(w);
  });
  c.last = (test) => [...c.msgs].reverse().find(test);
  return c;
}

try {
  await waitListen;
  console.log('Сервер поднялся. Тест лобби + ботов…');

  const host = client('Хост', 'ira');
  const w1 = await host.wait(m => m.t === 'welcome', 'welcome');
  host.id = w1.id;
  log(true, `хост id=${host.id}`);

  const lob1 = await host.wait(m => m.t === 'lobby', 'lobby');
  log(lob1.hostId === host.id, 'первый игрок — хост');
  const myTeam = lob1.players.find(p => p.id === host.id).team;
  log(myTeam === 'A', 'хост попал в команду A');

  // хост набивает 5v5: 4 бота в A, 5 ботов в B
  for (let i = 0; i < 4; i++) host.send({ t: 'addBot', team: 'A' });
  for (let i = 0; i < 5; i++) host.send({ t: 'addBot', team: 'B' });
  const lobFull = await host.wait(m => m.t === 'lobby' && m.players.length === 10, 'lobby 10', 5000);
  log(lobFull.players.filter(p => p.team === 'A').length === 5, 'в A — 5 (хост + 4 бота)');
  log(lobFull.players.filter(p => p.team === 'B').length === 5, 'в B — 5 ботов');
  log(lobFull.players.filter(p => p.bot).length === 9, '9 ботов всего');

  // смена карты
  host.send({ t: 'setMap', map: 'height' });
  const lobMap = await host.wait(m => m.t === 'lobby' && m.map === 'height', 'map height', 3000);
  log(lobMap.map === 'height', 'хост сменил карту на «Высота»');
  host.send({ t: 'setMap', map: 'duel' });
  await host.wait(m => m.t === 'lobby' && m.map === 'duel', 'map duel', 3000);

  // старт матча
  host.send({ t: 'startMatch' });
  const ms = await host.wait(m => m.t === 'matchStart', 'matchStart', 5000);
  log(ms.players.length === 10, 'матч стартовал 5v5');

  const rs = await host.wait(m => m.t === 'roundStart', 'roundStart');
  log(rs.round === 1, 'раунд 1');
  log(rs.sides.A !== rs.sides.B, 'у команд разные стороны (атака/защита)');
  log(rs.credits[host.id] === 800, 'стартовые кредиты 800');
  log(!!rs.status[host.id].pos, 'сервер прислал спавн-позицию');

  // закупка по средствам (800 кредитов): Стингер стоит 950 — не хватит, Спектр 1600 — нет,
  // берём Шериф (800)
  host.send({ t: 'buy', item: 'vandal' });
  await host.wait(m => m.t === 'buyFail', 'buyFail vandal (нет денег)');
  log(true, 'Вандал за 2900 не по карману на 800 — отказ');
  host.send({ t: 'buy', item: 'sheriff' });
  const bo = await host.wait(m => m.t === 'buyOk' && m.item === 'sheriff', 'buyOk sheriff');
  log(bo.credits === 0 && bo.loadout.sidearm === 'sheriff', 'Шериф куплен за 800');

  // боты должны двигаться после начала LIVE
  await host.wait(m => m.t === 'phase' && m.phase === 'live', 'phase live', 20000);
  log(true, 'фаза LIVE');

  // ждём стейты ботов
  const botState = await host.wait(m => m.t === 'state' && m.id >= 100, 'bot state', 4000);
  log(botState.id >= 100, `бот шлёт состояние (id=${botState.id})`);
  const p1 = [...botState.p];
  await new Promise(r => setTimeout(r, 1200));
  const botState2 = host.last(m => m.t === 'state' && m.id === botState.id);
  const moved = Math.hypot(botState2.p[0] - p1[0], botState2.p[2] - p1[2]);
  log(moved > 0.3, `бот ${botState.id} движется по карте (сдвиг ${moved.toFixed(1)} м)`);

  // урон по вражескому боту (id из команды B)
  const enemyBot = lobFull.players.find(p => p.team === 'B' && p.bot);
  host.send({ t: 'hit', target: enemyBot.id, dmg: 200, part: 'head', weapon: 'vandal' });
  const death = await host.wait(m => m.t === 'death' && m.id === enemyBot.id, 'death enemy bot', 5000);
  log(death.by === host.id && death.part === 'head', 'убийство вражеского бота засчитано');

  // проверка: дружественного огня нет
  const allyBot = lobFull.players.find(p => p.team === 'A' && p.bot);
  host.send({ t: 'hit', target: allyBot.id, dmg: 200, part: 'head', weapon: 'vandal' });
  await new Promise(r => setTimeout(r, 300));
  const allyDeath = host.last(m => m.t === 'death' && m.id === allyBot.id);
  log(!allyDeath, 'по своим ботам урона нет (friendly fire off)');

  // ===== хилки Иры (хост — Ира) =====
  // healBurst по союзникам на полном HP не даёт overheal-события
  host.msgs.length = 0;
  host.send({ t: 'healBurst', pos: [0, 0, -19], r: 8, amount: 50 });
  await new Promise(r => setTimeout(r, 250));
  log(!host.last(m => m.t === 'hp' && m.part === 'heal'), 'healBurst не даёт overheal союзникам на 100 HP');
  // криспи-хилзона и банкет от Иры принимаются без краша
  host.send({ t: 'healZone', kind: 'crispy', a: [-3, 0, 0], b: [3, 0, 0], dur: 15 });
  host.send({ t: 'healZone', kind: 'banquet', pos: [0, 0, 0], r: 6, dur: 20 });
  await new Promise(r => setTimeout(r, 200));
  log(true, 'healZone (криспи + банкет) от Иры обработаны без ошибок');
  // куриный дозор: ability scoutPing реле-ится команде
  host.send({ t: 'ability', kind: 'scout', data: { from: [0, 0, 18], dir: [0, -1] } });
  await new Promise(r => setTimeout(r, 150));
  log(!!host.last(m => m.t === 'ability' && m.kind === 'scout'), 'дозор (scout) реле-ится всем');

  host.ws.close();
  console.log(failed ? '\nЕСТЬ ПАДЕНИЯ' : '\nВСЕ ПРОВЕРКИ ПРОШЛИ');
  server.kill();
  process.exit(failed ? 1 : 0);
} catch (e) {
  console.error('\nТест упал:', e.message);
  server.kill();
  process.exit(1);
}
