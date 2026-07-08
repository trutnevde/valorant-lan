// Сервер «Valorant LAN» v2 — команды до 5x5, лобби с хостом, боты, две карты.
// Сервер авторитарен для: HP, урона, экономики, раундов, шипа, ультов, кокона Дениса.
// Движение и попадания людей считает клиент; ботов целиком ведёт сервер.

import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { WebSocketServer } from 'ws';
import {
  PORT, PHASES, RULES, WEAPONS, ARMOR, CHARACTERS, ABILITY,
  MAPS, DEFAULT_MAP, mapAabbs, segmentHitsAabb, segmentHitsSphere,
} from './public/js/shared.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUB = path.join(__dirname, 'public');
const port = Number(process.env.PORT) || PORT;
const now = () => Date.now() / 1000;

// ===== Статика =====
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.ico': 'image/x-icon',
};
const httpServer = http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';
  const file = path.normalize(path.join(PUB, urlPath));
  if (!file.startsWith(PUB)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('404'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
});

// ===== Состояние =====
const players = new Map(); // id -> P (люди id 1..99, боты id 100+)
let nextHumanId = 1;
let nextBotId = 100;
const BOT_NAMES = ['Коня', 'Никита Грицина', 'Игорь Емцов', 'Вафлист', 'Стульчак', 'Ростислав Зиныч', 'Бот Витёк', 'Бот Толян'];

const lobby = { map: DEFAULT_MAP, hostId: 0 };

const match = {
  running: false,
  state: PHASES.WAIT,
  round: 0,
  score: { A: 0, B: 0 },
  lossStreak: { A: 0, B: 0 },
  attackTeam: 'A',
  deadline: 0,
  planting: null,     // {by, start, pos}
  defusing: null,     // {by, start}
  defuseAccum: 0,
  spike: null,        // {pos, boomAt}
  spikeCarrier: null, // id игрока с шипом (плантить может только он)
  spikeDropped: null, // {pos} — шип лежит на земле (носитель погиб)
  defuseHalfDone: false,
  smokes: [],         // {pos:[x,y,z], r, until} — для LOS ботов
  zones: [],          // {type, pos|a/b, r, dps, from, until, owner} — урон ботам
  healZones: [],      // {kind, team, a?/b?/pos?/r?, rate, until} — хилки Иры
  noises: [],         // {team, pos:[x,z], until, loud} — что боты СЛЫШАТ
  scents: [],         // {owner, team, pos:[x,z], until, pinged:Map} — «нюх мясника» Дениса
  cocoon: null,       // {victim, by, hp, until}
  mapDef: MAPS[DEFAULT_MAP],
  aabbs: mapAabbs(MAPS[DEFAULT_MAP]),
};

function newPlayer(id, ws, bot = false) {
  return {
    id, ws, bot,
    name: bot ? BOT_NAMES[(id - 100) % BOT_NAMES.length] : 'Игрок',
    char: bot ? Object.keys(CHARACTERS)[Math.floor(Math.random() * Object.keys(CHARACTERS).length)] : 'artemiy',
    team: 'A',
    alive: false, hp: 100, armor: 0, maxHp: RULES.BASE_HP,
    credits: RULES.START_CREDITS,
    loadout: { primary: null, sidearm: 'classic' },
    kills: 0, deaths: 0, ult: 0,
    lastPos: [0, 0, 0], yaw: 0,
    ultMark: null, cloneMode: false, _healFrac: 0, tagUntil: 0, lastKillT: -99, _hotUntil: 0, _hotRate: 0,
    ai: bot ? { path: [], pathIdx: 0, goal: null, site: null, nextThink: 0, nextShot: 0, engaging: 0, scanYaw: 0, nextAbility: 0, charges: {}, blindUntil: 0, stunUntil: 0, heardUntil: 0, heardPos: null, _noiseAcc: 0, reactAt: 0, holdSpot: null } : null,
  };
}

const humans = () => [...players.values()].filter(p => !p.bot);
const hostId = () => {
  const ov = players.get(lobby.hostId);
  if (ov && !ov.bot) return ov.id;
  return Math.min(...humans().map(p => p.id), Infinity);
};
const teamOf = (t) => [...players.values()].filter(p => p.team === t);
const enemyTeam = (t) => (t === 'A' ? 'B' : 'A');
const teamAliveCount = (t) => teamOf(t).filter(p => p.alive).length;
const sideOfTeam = (t) => (t === match.attackTeam ? 'attack' : 'defend');
const liveish = () => match.state === PHASES.LIVE || match.state === PHASES.PLANTED;
const ultCap = (p) => (CHARACTERS[p.char] ? CHARACTERS[p.char].ultCost : 7);
// заряд ульты. КАНОН Эпохи 15: копится ТОЛЬКО за убийства (единственный источник — килл в onDeath)
function gainUlt(p, n = 1) { p.ult = Math.min(ultCap(p), p.ult + n); }

function send(p, msg) {
  if (p && p.ws && p.ws.readyState === 1) p.ws.send(JSON.stringify(msg));
}
function broadcast(msg) {
  const s = JSON.stringify(msg);
  for (const p of players.values()) {
    if (p.ws && p.ws.readyState === 1) p.ws.send(s);
  }
}
function lobbyInfo() {
  return {
    t: 'lobby',
    players: [...players.values()].map(p => ({ id: p.id, name: p.name, char: p.char, team: p.team, bot: p.bot })),
    map: lobby.map,
    hostId: hostId() === Infinity ? 0 : hostId(),
    inMatch: match.running,
  };
}
function inSite(pos) {
  for (const [key, s] of Object.entries(match.mapDef.sites)) {
    if (Math.abs(pos[0] - s.x) <= s.w / 2 + 0.5 && Math.abs(pos[2] - s.z) <= s.d / 2 + 0.5) {
      if (s.yMin !== undefined && pos[1] < s.yMin - 0.3) continue;
      return key;
    }
  }
  return null;
}

// шум, который слышат боты; шифт/присед бесшумны (клиент не шлёт noise), глушитель тише
function addNoise(p, loud) {
  if (!liveish()) return;
  match.noises.push({ team: p.team, pos: [p.lastPos[0], p.lastPos[2]], until: now() + (loud ? 1.1 : 0.5), loud });
  if (match.noises.length > 120) match.noises.shift();
}

// LOS для ботов: стены + дымы
function losClear(a, b) {
  for (const box of match.aabbs) {
    if (segmentHitsAabb(a, b, box)) return false;
  }
  const t = now();
  for (const s of match.smokes) {
    if (t < s.until && segmentHitsSphere(a, b, s.pos, s.r)) return false;
  }
  return true;
}

// ===== Матч =====
function startMatch() {
  match.running = true;
  match.round = 0;
  match.score = { A: 0, B: 0 };
  match.lossStreak = { A: 0, B: 0 };
  match.attackTeam = Math.random() < 0.5 ? 'A' : 'B';
  match.mapDef = MAPS[lobby.map] || MAPS[DEFAULT_MAP];
  match.aabbs = mapAabbs(match.mapDef);
  for (const p of players.values()) {
    p.credits = RULES.START_CREDITS;
    p.kills = 0; p.deaths = 0; p.ult = 0;
    p.maxHp = RULES.BASE_HP; p.armor = 0;
    p.loadout = { primary: null, sidearm: 'classic' };
  }
  broadcast({ ...lobbyInfo(), inMatch: true });
  broadcast({ t: 'matchStart', players: lobbyInfo().players, map: match.mapDef.id, score: match.score });
  startRound();
}

function startRound() {
  match.round++;
  if (match.round > 1) match.attackTeam = enemyTeam(match.attackTeam);
  match.state = PHASES.BUY;
  match.deadline = now() + RULES.BUY_TIME;
  match.planting = null; match.defusing = null; match.defuseAccum = 0;
  match.spike = null; match.smokes = []; match.zones = []; match.healZones = []; match.cocoon = null;
  match.spikeDropped = null; match.defuseHalfDone = false; match.noises = []; match.scents = []; match._poppedClones = new Set();
  match.corpses = []; match.pickups = []; match._pickupSeq = 1; // трупы (для кровопира) и брошенное оружие
  // шип получает ОДИН случайный атакер (людям — приоритет)
  const attackers = teamOf(match.attackTeam);
  const humanAtt = attackers.filter(a => !a.bot);
  const pool = humanAtt.length ? humanAtt : attackers;
  match.spikeCarrier = pool.length ? pool[Math.floor(Math.random() * pool.length)].id : null;

  const spawnIdx = { A: 0, B: 0 };
  for (const p of players.values()) {
    p.alive = true;
    p.hp = p.maxHp;
    p.ultMark = null; p.cloneMode = false; p._healFrac = 0; p._hotUntil = 0; p.lastKillT = -99;
    // ульта копится ТОЛЬКО за убийства (канон): раунд/смерть/плант/дефуз заряд не дают
    // позиция
    const side = sideOfTeam(p.team);
    const sp = match.mapDef.spawns[side];
    const pos = sp.pts[spawnIdx[p.team] % sp.pts.length];
    spawnIdx[p.team]++;
    p.lastPos = [...pos];
    p.yaw = sp.yaw;
    if (p.bot) botResetRound(p);
  }
  const credits = {}, status = {};
  for (const p of players.values()) {
    credits[p.id] = p.credits;
    status[p.id] = { hp: p.hp, maxHp: p.maxHp, armor: p.armor, alive: true, ult: p.ult, loadout: p.loadout, pos: p.lastPos, yaw: p.yaw };
  }
  broadcast({
    t: 'roundStart', round: match.round, score: match.score,
    sides: { A: sideOfTeam('A'), B: sideOfTeam('B') },
    spikeCarrier: match.spikeCarrier,
    buyTime: RULES.BUY_TIME, credits, status,
  });
}

function startLive() {
  match.state = PHASES.LIVE;
  match.deadline = now() + RULES.ROUND_TIME;
  broadcast({ t: 'phase', phase: PHASES.LIVE, tLeft: RULES.ROUND_TIME });
}

function endRound(winnerTeam, reason) {
  if (match.state === PHASES.ROUND_END || match.state === PHASES.MATCH_END) return;
  match.state = PHASES.ROUND_END;
  match.deadline = now() + RULES.ROUND_END_TIME;
  match.planting = null; match.defusing = null; match.cocoon = null;
  match.score[winnerTeam]++;
  // эко-серия: победа обнуляет, поражение эскалирует награду проигравшего (1900/2400/2900)
  const loserTeam = enemyTeam(winnerTeam);
  match.lossStreak[winnerTeam] = 0;
  match.lossStreak[loserTeam] = Math.min(3, (match.lossStreak[loserTeam] || 0) + 1);
  const lossReward = [1900, 1900, 2400, 2900][match.lossStreak[loserTeam]];
  for (const p of players.values()) {
    const reward = p.team === winnerTeam ? RULES.WIN_REWARD : lossReward;
    p.credits = Math.min(RULES.MAX_CREDITS, p.credits + reward);
    if (!p.alive) { p.loadout = { primary: null, sidearm: 'classic' }; p.armor = 0; }
  }
  const credits = {};
  for (const p of players.values()) credits[p.id] = p.credits;
  broadcast({ t: 'roundEnd', winner: winnerTeam, reason, score: match.score, credits });
  if (match.score[winnerTeam] >= RULES.ROUNDS_TO_WIN) {
    match.state = PHASES.MATCH_END;
    match.deadline = now() + 12;
    const stats = {};
    for (const p of players.values()) stats[p.id] = { name: p.name, kills: p.kills, deaths: p.deaths, team: p.team, char: p.char };
    broadcast({ t: 'matchEnd', winner: winnerTeam, score: match.score, stats });
  }
}

function backToLobby() {
  match.running = false;
  match.state = PHASES.WAIT;
  match.planting = null; match.defusing = null; match.spike = null; match.cocoon = null;
  broadcast(lobbyInfo());
}

// ===== Урон =====
function applyDamage(victim, rawDmg, attackerId, weapon, part) {
  if (!victim.alive || !liveish()) return;
  // жертва в коконе неуязвима для врагов (кокон отстреливают союзники)
  if (match.cocoon && match.cocoon.victim === victim.id && part !== 'ult') return;
  let dmg = Math.min(320, Math.max(0, rawDmg));
  if (victim.armor > 0 && part !== 'ult') {
    const absorbed = Math.min(victim.armor, dmg * RULES.ARMOR_ABSORB);
    victim.armor = Math.round(victim.armor - absorbed);
    dmg -= absorbed;
  }
  victim.hp = Math.round(victim.hp - dmg);
  victim.tagUntil = now() + 0.45; // «tagging»: пуля вяжет ноги (для ботов — серверно)
  broadcast({ t: 'hp', id: victim.id, hp: victim.hp, armor: victim.armor, by: attackerId, part });
  if (victim.hp <= 0) onDeath(victim, attackerId, weapon, part);
}

function onDeath(victim, killerId, weapon, part) {
  // ульт Артемия: вместо смерти — возвращение на метку
  if (victim.ultMark && now() < victim.ultMark.until) {
    victim.hp = victim.maxHp;
    const mark = victim.ultMark;
    victim.ultMark = null;
    victim.lastPos = [...mark.pos];
    broadcast({ t: 'revive', id: victim.id, pos: mark.pos, yaw: mark.yaw, hp: victim.hp });
    return;
  }
  victim.alive = false;
  victim.hp = 0;
  victim.deaths++;
  const killer = players.get(killerId);
  if (killer && killer.id !== victim.id && killer.team !== victim.team) {
    killer.kills++;
    killer.lastKillT = now(); // «накормлен» — усиливает Кровопир Дениса
    gainUlt(killer, 1);
    // Пассивка Иры (Эпоха 15): её убийство создаёт хил-зону у трупа врага для союзников
    if (killer.char === 'ira') {
      const cpos = [...victim.lastPos];
      match.healZones.push({ kind: 'corpse', team: killer.team, pos: cpos, r: ABILITY.IRA_CORPSE_R, rate: ABILITY.IRA_CORPSE_RATE, until: now() + ABILITY.IRA_CORPSE_TIME });
      broadcast({ t: 'ability', id: killer.id, kind: 'iraCorpse', data: { pos: cpos, r: ABILITY.IRA_CORPSE_R, dur: ABILITY.IRA_CORPSE_TIME } });
    }
    const abilityKill = !WEAPONS[weapon]; // не обычный ствол → способность/крюк/табун
    killer.credits = Math.min(RULES.MAX_CREDITS, killer.credits + (abilityKill ? 300 : RULES.KILL_REWARD));
    send(killer, { t: 'ultPts', pts: killer.ult });
    send(killer, { t: 'credits', credits: killer.credits });
  }
  send(victim, { t: 'ultPts', pts: victim.ult });
  if (match.planting && match.planting.by === victim.id) { match.planting = null; broadcast({ t: 'plantProg', pct: -1 }); }
  if (match.defusing && match.defusing.by === victim.id) stopDefuse();
  if (match.cocoon && match.cocoon.victim === victim.id) {
    broadcast({ t: 'cocoonEnd', victim: victim.id, freed: false });
    match.cocoon = null;
  }
  if (match.state === PHASES.LIVE && match.spikeCarrier === victim.id) {
    match.spikeCarrier = null;
    match.spikeDropped = { pos: [...victim.lastPos] };
    broadcast({ t: 'spikeDrop', pos: match.spikeDropped.pos });
  }
  // труп (для Кровопира Дениса) + брошенное оружие (можно подобрать)
  match.corpses.push({ team: victim.team, pos: [...victim.lastPos], until: now() + ABILITY.CORPSE_LIFE });
  const dropW = victim.loadout && victim.loadout.primary;
  if (dropW && WEAPONS[dropW] && dropW !== 'knife') {
    const pk = { id: match._pickupSeq++, weapon: dropW, pos: [victim.lastPos[0], victim.lastPos[1] || 0, victim.lastPos[2]], until: now() + ABILITY.PICKUP_LIFE };
    match.pickups.push(pk);
    broadcast({ t: 'weaponDrop', id: pk.id, weapon: dropW, pos: pk.pos });
  }
  broadcast({ t: 'death', id: victim.id, by: killerId, weapon, part });
  // исход раунда
  if (match.state === PHASES.LIVE) {
    if (teamAliveCount(victim.team) === 0) endRound(enemyTeam(victim.team), 'elim');
  } else if (match.state === PHASES.PLANTED) {
    const defTeam = enemyTeam(match.attackTeam);
    if (victim.team === defTeam && teamAliveCount(defTeam) === 0) endRound(match.attackTeam, 'elim');
  }
}

function heal(p, amt) {
  if (!p.alive || !liveish()) return;
  const before = p.hp;
  p.hp = Math.min(p.maxHp, Math.round(p.hp + amt));
  if (p.hp !== before) broadcast({ t: 'hp', id: p.id, hp: p.hp, armor: p.armor, by: 0, part: 'heal' });
}

function stopDefuse() {
  if (!match.defusing) return;
  // сохранение прогресса — только по половинкам: перевалил за 50% — остаёшься на 50%, нет — с нуля
  const total = match.defuseAccum + (now() - match.defusing.start);
  const half = RULES.DEFUSE_TIME / 2;
  match.defuseAccum = total >= half ? half : 0;
  match.defusing = null;
  broadcast({ t: 'defuseProg', pct: -1 });
}

// ===== Сообщения =====
function onMessage(p, msg) {
  switch (msg.t) {
    case 'join': {
      p.name = String(msg.name || 'Игрок').slice(0, 16) || 'Игрок';
      p.char = CHARACTERS[msg.char] ? msg.char : 'artemiy';
      // авто-баланс команд (не считая самого себя — он уже в мапе с team='A')
      const aCount = [...players.values()].filter(x => x.id !== p.id && x.team === 'A').length;
      const bCount = [...players.values()].filter(x => x.id !== p.id && x.team === 'B').length;
      p.team = aCount <= bCount ? 'A' : 'B';
      broadcast(lobbyInfo());
      break;
    }
    case 'switchTeam': {
      if (match.running) return;
      const other = enemyTeam(p.team);
      if (teamOf(other).length >= RULES.TEAM_MAX) return;
      p.team = other;
      broadcast(lobbyInfo());
      break;
    }
    case 'setChar': {
      if (match.running) return;
      if (CHARACTERS[msg.char]) p.char = msg.char;
      broadcast(lobbyInfo());
      break;
    }
    case 'addBot': {
      if (p.id !== hostId() || match.running) return;
      const team = msg.team === 'B' ? 'B' : 'A';
      if (teamOf(team).length >= RULES.TEAM_MAX) return;
      const bot = newPlayer(nextBotId++, null, true);
      bot.team = team;
      // не дублируем уже занятых персов, пока есть свободные
      const used = new Set([...players.values()].map(x => x.char));
      const free = Object.keys(CHARACTERS).filter(c => !used.has(c));
      if (free.length) bot.char = free[Math.floor(Math.random() * free.length)];
      players.set(bot.id, bot);
      broadcast(lobbyInfo());
      break;
    }
    case 'transferHost': {
      if (p.id !== hostId() || match.running) return;
      const target = players.get(msg.target);
      if (target && !target.bot) { lobby.hostId = target.id; broadcast(lobbyInfo()); }
      break;
    }
    case 'movePlayer': {
      if (p.id !== hostId() || match.running) return;
      const target = players.get(msg.target);
      if (!target) return;
      const to = msg.team === 'B' ? 'B' : 'A';
      if (target.team !== to && teamOf(to).length < RULES.TEAM_MAX) { target.team = to; broadcast(lobbyInfo()); }
      break;
    }
    case 'kickBot': {
      if (p.id !== hostId() || match.running) return;
      const b = players.get(msg.target);
      if (b && b.bot) { players.delete(b.id); broadcast(lobbyInfo()); }
      break;
    }
    case 'removeBot': {
      if (p.id !== hostId() || match.running) return;
      const bots = [...players.values()].filter(b => b.bot && b.team === msg.team);
      if (bots.length) { players.delete(bots[bots.length - 1].id); broadcast(lobbyInfo()); }
      break;
    }
    case 'setMap': {
      if (p.id !== hostId() || match.running) return;
      if (MAPS[msg.map]) lobby.map = msg.map;
      broadcast(lobbyInfo());
      break;
    }
    case 'startMatch': {
      if (p.id !== hostId() || match.running) return;
      if (teamOf('A').length < 1 || teamOf('B').length < 1) return;
      startMatch();
      break;
    }
    case 'state': {
      if (!match.running) return;
      p.lastPos = msg.p;
      p.yaw = msg.yaw;
      if (match.planting && match.planting.by === p.id) {
        const d = Math.hypot(msg.p[0] - match.planting.pos[0], msg.p[2] - match.planting.pos[2]);
        if (d > 0.7) { match.planting = null; broadcast({ t: 'plantProg', pct: -1 }); }
      }
      if (match.defusing && match.defusing.by === p.id && match.spike) {
        const d = Math.hypot(msg.p[0] - match.spike.pos[0], msg.p[2] - match.spike.pos[2]);
        if (d > 2.8) stopDefuse();
      }
      broadcastExcept(p.id, { ...msg, id: p.id });
      break;
    }
    case 'noise': {
      if (p.alive) addNoise(p, false); // бег
      break;
    }
    case 'shoot': case 'chat': {
      broadcastExcept(p.id, { ...msg, id: p.id });
      if (msg.t === 'chat') { send(p, { ...msg, id: p.id }); }
      else if (p.alive) { const w = WEAPONS[msg.w]; addNoise(p, !(w && w.silenced) && msg.w !== 'knife'); } // выстрел — громкий шум (глушитель тише)
      break;
    }
    case 'flashPop': {
      // владелец сообщил, где хлопнула вспышка — ослепляем смотрящих ботов
      if (!p.alive || !liveish()) return;
      blindBots(msg.pos);
      break;
    }
    case 'clonePop': {
      // лопнули клона Фафика — станит врагов ВЛАДЕЛЬЦА клона по области
      if (!liveish() || !Array.isArray(msg.pos)) return;
      const owner = players.get(msg.owner);
      if (!owner) return;
      if (!match._poppedClones) match._poppedClones = new Set();
      if (match._poppedClones.has(msg.cloneId)) return; // уже лопнут (защита от дублей)
      match._poppedClones.add(msg.cloneId);
      const [px, pz] = msg.pos;
      for (const e of players.values()) {
        if (e.team === owner.team || !e.alive) continue;
        if (Math.hypot(e.lastPos[0] - px, e.lastPos[2] - pz) < ABILITY.CLONE_POP_STUN_R) {
          if (e.bot) e.ai.stunUntil = now() + ABILITY.CLONE_POP_STUN;
          else send(e, { t: 'stun', dur: ABILITY.CLONE_POP_STUN });
        }
      }
      broadcast({ t: 'clonePopped', cloneId: msg.cloneId, pos: msg.pos });
      break;
    }
    case 'buy': {
      if (match.state !== PHASES.BUY) { send(p, { t: 'buyFail', reason: 'Закупка закрыта' }); return; }
      const item = msg.item;
      if (WEAPONS[item] && !WEAPONS[item].melee) {
        const w = WEAPONS[item];
        if (p.credits < w.price) { send(p, { t: 'buyFail', reason: 'Не хватает кредитов' }); return; }
        p.credits -= w.price;
        p.loadout[w.slot] = item;
      } else if (ARMOR[item]) {
        const a = ARMOR[item];
        if (p.credits < a.price) { send(p, { t: 'buyFail', reason: 'Не хватает кредитов' }); return; }
        if (p.armor >= a.value) { send(p, { t: 'buyFail', reason: 'Броня уже есть' }); return; }
        p.credits -= a.price;
        p.armor = a.value;
      } else return;
      send(p, { t: 'buyOk', item, credits: p.credits, loadout: p.loadout, armor: p.armor });
      break;
    }
    case 'hit': {
      if (!p.alive || p.cloneMode) return;   // клон Фафика стрелять не может
      const victim = players.get(msg.target);
      if (!victim || !victim.alive) return;
      // выстрел союзника по кокону — спасение жертвы
      if (match.cocoon && match.cocoon.victim === victim.id && p.team === victim.team) {
        match.cocoon.hp -= Math.min(320, Number(msg.dmg) || 0);
        if (match.cocoon.hp <= 0) {
          broadcast({ t: 'cocoonEnd', victim: victim.id, freed: true });
          match.cocoon = null;
        }
        return;
      }
      if (victim.team === p.team) return; // дружественного огня нет
      applyDamage(victim, Number(msg.dmg) || 0, p.id, msg.weapon || 'unknown', msg.part || 'body');
      break;
    }
    case 'selfDamage': {
      if (!p.alive) return;
      const dmg = Math.min(45, Math.max(0, Number(msg.dmg) || 0));
      const by = players.get(msg.by);
      const attackerId = by && by.team !== p.team ? by.id : 0;
      applyDamage(p, dmg, attackerId, msg.cause || 'zone', msg.cause || 'zone');
      break;
    }
    case 'selfHeal': {
      if (p.char !== 'artemiy') return;
      heal(p, Math.min(15, Math.max(0, Number(msg.amt) || 0)));
      break;
    }
    case 'zone': {
      // владелец зоны сообщает серверу (урон ботам, дымы для их LOS)
      if (!liveish()) return;
      const dur = Math.min(15, Number(msg.dur) || 5);
      const r = Math.min(6.5, Number(msg.r) || 3);
      if (msg.ztype === 'smoke') {
        match.smokes.push({ pos: msg.pos, r, until: now() + dur });
      } else if (msg.ztype === 'firewall') {
        match.zones.push({ type: 'seg', a: msg.a, b: msg.b, r: 1.3, dps: ABILITY.FIRE_DPS, from: now(), until: now() + dur, owner: p.id });
      } else {
        const dpsMap = { fire: ABILITY.FIRE_DPS, mangal: ABILITY.MANGAL_DPS, acid: ABILITY.ACID_DPS, horseshoe: ABILITY.HORSESHOE_DPS, puddle: ABILITY.PUDDLE_DPS };
        const dps = dpsMap[msg.ztype] !== undefined ? dpsMap[msg.ztype] : ABILITY.PUDDLE_DPS;
        match.zones.push({ type: 'circle', pos: msg.pos, r, dps, from: now(), until: now() + dur, owner: p.id });
      }
      break;
    }
    case 'healZone': {
      if (!liveish() || p.char !== 'ira') return;
      const dur = Math.min(22, Number(msg.dur) || 10);
      if (msg.kind === 'crispy') {
        match.healZones.push({ kind: 'crispy', team: p.team, a: msg.a, b: msg.b, rate: ABILITY.CRISPY_HEAL, until: now() + dur });
      } else if (msg.kind === 'banquet') {
        const r = Math.min(8, Number(msg.r) || ABILITY.BANQUET_R);
        // мгновенные +30 всем союзникам, кто уже внутри
        for (const q of players.values()) {
          if (q.alive && q.team === p.team && Math.hypot(q.lastPos[0] - msg.pos[0], q.lastPos[2] - msg.pos[2]) < r) {
            heal(q, ABILITY.BANQUET_INSTANT);
          }
        }
        match.healZones.push({ kind: 'banquet', team: p.team, pos: msg.pos, r, rate: ABILITY.BANQUET_REGEN, until: now() + dur });
      }
      break;
    }
    case 'healBurst': {
      if (!liveish() || p.char !== 'ira') return;
      const r = Math.min(10, Number(msg.r) || ABILITY.BUFFET_R);
      const amount = Math.min(60, Number(msg.amount) || ABILITY.BUFFET_HEAL);
      for (const q of players.values()) {
        if (q.alive && q.team === p.team && Math.hypot(q.lastPos[0] - msg.pos[0], q.lastPos[2] - msg.pos[2]) < r) {
          heal(q, amount);
        }
      }
      break;
    }
    case 'ability': onAbility(p, msg); break;
    case 'plantStart': {
      if (match.state !== PHASES.LIVE || sideOfTeam(p.team) !== 'attack' || !p.alive) return;
      if (p.id !== match.spikeCarrier) { send(p, { t: 'noSpike' }); return; }
      const site = inSite(p.lastPos);
      if (!site || match.planting) return;
      match.planting = { by: p.id, start: now(), pos: [...p.lastPos] };
      broadcast({ t: 'plantProg', pct: 0 });
      break;
    }
    case 'plantCancel':
      if (match.planting && match.planting.by === p.id) { match.planting = null; broadcast({ t: 'plantProg', pct: -1 }); }
      break;
    case 'defuseStart': {
      if (match.state !== PHASES.PLANTED || sideOfTeam(p.team) !== 'defend' || !p.alive || !match.spike) return;
      if (match.defusing) { send(p, { t: 'defuseBusy' }); return; } // шип разминирует ОДИН
      const d = Math.hypot(p.lastPos[0] - match.spike.pos[0], p.lastPos[2] - match.spike.pos[2]);
      if (d > 2.8) return;
      match.defusing = { by: p.id, start: now() };
      broadcast({ t: 'defuseProg', pct: match.defuseAccum / RULES.DEFUSE_TIME });
      break;
    }
    case 'defuseCancel':
      if (match.defusing && match.defusing.by === p.id) stopDefuse();
      break;
  }
}

function broadcastExcept(id, msg) {
  const s = JSON.stringify(msg);
  for (const p of players.values()) {
    if (p.id !== id && p.ws && p.ws.readyState === 1) p.ws.send(s);
  }
}

function onAbility(p, msg) {
  if (!p.alive || !liveish()) return;
  const kind = msg.kind;
  const cost = CHARACTERS[p.char].ultCost;

  // ульты списываются сервером
  if (kind === 'ultMark') {
    if (p.char !== 'artemiy' || p.ult < cost) return;
    p.ult -= cost;
    p.ultMark = { pos: msg.data.pos, yaw: msg.data.yaw, until: now() + ABILITY.PHOENIX_ULT_TIME };
    send(p, { t: 'ultPts', pts: p.ult });
  } else if (kind === 'hookFire') {
    if (p.char !== 'denis' || p.ult < cost) return;
    p.ult -= cost;
    send(p, { t: 'ultPts', pts: p.ult });
  } else if (kind === 'orbital') {
    if (p.char !== 'vova' || p.ult < cost) return;
    p.ult -= cost;
    send(p, { t: 'ultPts', pts: p.ult });
    match.zones.push({
      type: 'circle', pos: [msg.data.pos[0], 0, msg.data.pos[2]], r: ABILITY.ORBITAL_R,
      dps: ABILITY.ORBITAL_DPS, from: now() + ABILITY.ORBITAL_DELAY,
      until: now() + ABILITY.ORBITAL_DELAY + ABILITY.ORBITAL_DUR, owner: p.id,
    });
  } else if (kind === 'xray') {
    if (p.char !== 'sanek' || p.ult < cost) return;
    p.ult -= cost;
    send(p, { t: 'ultPts', pts: p.ult });
  } else if (kind === 'knives') {
    if (p.char !== 'max' || p.ult < cost) return;
    p.ult -= cost;
    send(p, { t: 'ultPts', pts: p.ult });
  } else if (kind === 'banquet') {
    if (p.char !== 'ira' || p.ult < cost) return;
    p.ult -= cost;
    send(p, { t: 'ultPts', pts: p.ult });
  } else if (kind === 'cocoonHit') {
    // Денис попал крюком: сервер ведёт кокон
    const victim = players.get(msg.data.target);
    if (!victim || !victim.alive || victim.team === p.team || match.cocoon) return;
    applyDamage(victim, ABILITY.COCOON_HIT_DMG, p.id, 'hook', 'body');
    if (!victim.alive) return;
    match.cocoon = { victim: victim.id, by: p.id, hp: ABILITY.COCOON_HP, until: now() + ABILITY.COCOON_TIME };
    broadcast({ t: 'cocoon', victim: victim.id, by: p.id, tLeft: ABILITY.COCOON_TIME });
  } else if (kind === 'stampede') {
    if (p.char !== 'koniliy' || p.ult < cost) return;
    p.ult -= cost;
    send(p, { t: 'ultPts', pts: p.ult });
    const fromX = msg.data.from[0], fromZ = msg.data.from[2];
    const toX = msg.data.to[0], toZ = msg.data.to[1];
    let dx = toX - fromX, dz = toZ - fromZ;
    const dl = Math.hypot(dx, dz) || 1;
    const len = Math.min(ABILITY.STAMPEDE_LEN, dl);
    const a = [fromX, 0, fromZ], b = [fromX + dx / dl * len, 0, fromZ + dz / dl * len];
    for (const e of players.values()) {
      if (e.team === p.team || !e.alive) continue;
      if (distToSeg2D(e.lastPos, a, b) < ABILITY.STAMPEDE_WIDTH) {
        // табун только ОГЛУШАЕТ (урона нет)
        if (e.bot) e.ai.stunUntil = now() + ABILITY.STAMPEDE_STUN;
        else send(e, { t: 'stun', dur: ABILITY.STAMPEDE_STUN });
      }
    }
  } else if (kind === 'fafikClones') {
    if (p.char !== 'fafik' || p.ult < cost || p.cloneMode) return;
    p.ult -= cost;
    p.cloneMode = true;
    send(p, { t: 'ultPts', pts: p.ult });
  } else if (kind === 'fafikDeClone') {
    if (p.char !== 'fafik') return;
    p.cloneMode = false;
  } else if (kind === 'bloodfeast') {
    if (p.char !== 'denis') return;
    // только у ТЕЛА недавно убитого врага (а не по рофлу в любой момент)
    const ci = (match.corpses || []).findIndex(c => c.team !== p.team && now() < c.until &&
      Math.hypot(p.lastPos[0] - c.pos[0], p.lastPos[2] - c.pos[2]) < ABILITY.BLOODFEAST_R);
    if (ci < 0) { send(p, { t: 'abilityFail', kind: 'bloodfeast', reason: 'НУЖНО ТЕЛО ВРАГА РЯДОМ' }); return; }
    const fed = now() - p.lastKillT < ABILITY.BLOODFEAST_FED_WINDOW;
    heal(p, fed ? ABILITY.BLOODFEAST_FED : ABILITY.BLOODFEAST_INSTANT);
    p._hotUntil = now() + ABILITY.BLOODFEAST_HOT_TIME;
    p._hotRate = fed ? ABILITY.BLOODFEAST_HOT_FED : ABILITY.BLOODFEAST_HOT;
    p.lastKillT = -99;              // «съел» бонус кормёжки
    match.corpses[ci].until = 0;    // тело обглодано
  } else if (kind === 'scent') {
    if (p.char !== 'denis') return;
    match.scents.push({ owner: p.id, team: p.team, pos: [msg.data.pos[0], msg.data.pos[2]], until: now() + ABILITY.SCENT_LIFE, pinged: new Map() });
  } else if (kind === 'smokes') {
    // дымы: запоминаем для LOS ботов
    for (const pos of msg.data.positions || []) {
      match.smokes.push({ pos, r: ABILITY.SMOKE_R, until: now() + ABILITY.SMOKE_TIME });
    }
  } else if (kind === 'sovaShock') {
    // Сова C — шок-стрела: летит и на ПОПАДАНИИ (после долёта) бьёт по области
    if (p.char !== 'sova') return;
    const c = msg.data.to || [0, 0, 0], f = msg.data.from || [c[0], 1, c[2]];
    const travel = Math.min(0.8, Math.max(0.12, Math.hypot(c[0] - f[0], c[2] - f[2]) * 0.018));
    setTimeout(() => {
      if (!match.running) return;
      for (const e of players.values()) {
        if (e.team === p.team || !e.alive) continue;
        if (Math.hypot(e.lastPos[0] - c[0], e.lastPos[2] - c[2]) < ABILITY.SOVA_SHOCK_R) applyDamage(e, ABILITY.SOVA_SHOCK_DMG, p.id, 'sovaShock', 'body');
      }
    }, travel * 1000);
  } else if (kind === 'sovaMark' || kind === 'sovaDrone') {
    // Сова Q/E — стрела/дрон: после долёта палит команде врагов у точки попадания (по прямой видимости)
    if (p.char !== 'sova') return;
    const c = msg.data.to || [0, 0, 0], f = msg.data.from || [c[0], 1, c[2]];
    const R = kind === 'sovaDrone' ? ABILITY.SOVA_DRONE_R : ABILITY.SOVA_MARK_R;
    const travel = Math.min(0.8, Math.max(0.12, Math.hypot(c[0] - f[0], c[2] - f[2]) * 0.018));
    setTimeout(() => {
      if (!match.running) return;
      for (const e of players.values()) {
        if (e.team === p.team || !e.alive) continue;
        if (Math.hypot(e.lastPos[0] - c[0], e.lastPos[2] - c[2]) >= R) continue;
        if (!losClear([c[0], 1.3, c[2]], [e.lastPos[0], e.lastPos[1] + 1.2, e.lastPos[2]])) continue;
        broadcast({ t: 'ability', id: p.id, kind: 'sovaPing', data: { target: e.id } });
      }
    }, travel * 1000);
  } else if (kind === 'sovaFury') {
    // Сова X (ульта) — ярость охотника: 3 залпа энергии по направлению, пробивают стены, бьют линией
    if (p.char !== 'sova' || p.ult < cost) return;
    p.ult -= cost;
    send(p, { t: 'ultPts', pts: p.ult });
    const fromX = msg.data.from[0], fromZ = msg.data.from[2];
    const dl = Math.hypot(msg.data.dir[0], msg.data.dir[2]) || 1;
    const dx = msg.data.dir[0] / dl, dz = msg.data.dir[2] / dl;
    const a = [fromX, 0, fromZ], b = [fromX + dx * ABILITY.SOVA_FURY_LEN, 0, fromZ + dz * ABILITY.SOVA_FURY_LEN];
    let wave = 0;
    const fire = () => {
      wave++;
      if (!match.running) return;
      for (const e of players.values()) {
        if (e.team === p.team || !e.alive) continue;
        if (distToSeg2D(e.lastPos, a, b) < ABILITY.SOVA_FURY_WIDTH) applyDamage(e, ABILITY.SOVA_FURY_DMG, p.id, 'sovaFury', 'body');
      }
      if (wave < ABILITY.SOVA_FURY_WAVES) setTimeout(fire, 320);
    };
    fire();
  }
  broadcast({ t: 'ability', id: p.id, kind, data: msg.data || {} });
}

// ===== Боты =====
function botResetRound(bot) {
  const ai = bot.ai;
  ai.path = []; ai.pathIdx = 0; ai.goal = null; ai.site = null;
  ai.nextThink = 0; ai.nextShot = 0; ai.engaging = 0; ai.scanYaw = bot.yaw;
  ai.nextAbility = now() + 3 + Math.random() * 3; ai.target = null;
  ai.blindUntil = 0; ai.stunUntil = 0; ai.heardUntil = 0; ai.heardPos = null; ai._noiseAcc = 0; ai.reactAt = 0; ai.holdSpot = null;
  // автозакупка
  if (bot.credits >= 3900) { bot.loadout.primary = 'vandal'; bot.armor = 50; bot.credits -= 3900; }
  else if (bot.credits >= 2000) { bot.loadout.primary = 'spectre'; bot.armor = 25; bot.credits -= 2000; }
  else if (bot.credits >= 800 && !bot.loadout.primary) { bot.loadout.sidearm = 'sheriff'; bot.credits -= 800; }
}

function botWeapon(bot) {
  return WEAPONS[bot.loadout.primary || bot.loadout.sidearm || 'classic'];
}

function navNearest(pos) {
  const nodes = match.mapDef.nav.nodes;
  let best = 0, bd = Infinity;
  for (let i = 0; i < nodes.length; i++) {
    const d = Math.hypot(pos[0] - nodes[i][0], pos[2] - nodes[i][1]);
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}

function navPath(fromIdx, toIdx) {
  const { nodes, edges } = match.mapDef.nav;
  const adj = new Map();
  for (const [a, b] of edges) {
    if (!adj.has(a)) adj.set(a, []);
    if (!adj.has(b)) adj.set(b, []);
    adj.get(a).push(b); adj.get(b).push(a);
  }
  const prev = new Map([[fromIdx, -1]]);
  const q = [fromIdx];
  while (q.length) {
    const cur = q.shift();
    if (cur === toIdx) break;
    for (const nb of adj.get(cur) || []) {
      if (!prev.has(nb)) { prev.set(nb, cur); q.push(nb); }
    }
  }
  if (!prev.has(toIdx)) return [toIdx];
  const path = [];
  for (let cur = toIdx; cur !== -1; cur = prev.get(cur)) path.unshift(cur);
  return path;
}

function botEye(b) { return [b.lastPos[0], b.lastPos[1] + 1.6, b.lastPos[2]]; }

// вспышка ослепляет ботов, которые на неё смотрят (с LOS)
function blindBots(flashPos) {
  const fp = [flashPos[0], flashPos[1] || 1.5, flashPos[2]];
  for (const b of players.values()) {
    if (!b.bot || !b.alive) continue;
    const eye = botEye(b);
    const to = [fp[0] - eye[0], fp[1] - eye[1], fp[2] - eye[2]];
    const dist = Math.hypot(to[0], to[2]);
    if (dist > 40 || dist < 0.1) continue;
    const dot = (to[0] * -Math.sin(b.yaw) + to[2] * -Math.cos(b.yaw)) / dist;
    if (dot < 0.2) continue; // не смотрит
    if (!losClear(eye, fp)) continue;
    const k = (dot - 0.2) / 0.8;
    b.ai.blindUntil = Math.max(b.ai.blindUntil, now() + 0.5 + k * (ABILITY.FLASH_MAX_BLIND - 0.5));
  }
}

// бот слышит ближайший вражеский шум (громкий — дальше)
function botHearEnemy(bot) {
  const t = now();
  let best = null, bd = Infinity;
  for (const n of match.noises) {
    if (t > n.until || n.team === bot.team) continue;
    const range = n.loud ? 28 : 14;
    const d = Math.hypot(n.pos[0] - bot.lastPos[0], n.pos[1] - bot.lastPos[2]);
    if (d < range && d < bd) { bd = d; best = n; }
  }
  return best ? best.pos : null;
}

function botVisibleEnemy(bot) {
  if (now() < bot.ai.blindUntil) return null; // ослеплённый бот не видит
  const fx = -Math.sin(bot.yaw), fz = -Math.cos(bot.yaw); // куда смотрит
  let best = null, bd = 44;
  for (const e of players.values()) {
    if (e.team === bot.team || !e.alive) continue;
    const ex = e.lastPos[0] - bot.lastPos[0], ez = e.lastPos[2] - bot.lastPos[2];
    const d = Math.hypot(ex, ez);
    if (d >= bd) continue;
    // ПОЛЕ ЗРЕНИЯ ~140° (±70). За спиной не видят — ловят слухом (можно зайти в тыл!)
    const dot = d > 0.1 ? (ex * fx + ez * fz) / d : 1;
    if (dot < 0.34 && d > 4.5) continue; // ближних (<4.5м) замечают периферией
    if (losClear(botEye(bot), [e.lastPos[0], e.lastPos[1] + 1.4, e.lastPos[2]])) { bd = d; best = e; }
  }
  return best ? { enemy: best, dist: bd } : null;
}

function botSetGoal(bot, nodeIdx, goal) {
  const ai = bot.ai;
  ai.path = navPath(navNearest(bot.lastPos), nodeIdx);
  ai.pathIdx = 0;
  ai.goal = goal;
  ai.holdSpot = null; // новая цель — пересчитать личную позицию
}

function botPlantNode(site) {
  const s = match.mapDef.sites[site];
  const nodes = match.mapDef.nav.nodes;
  let best = 0, bd = Infinity;
  for (let i = 0; i < nodes.length; i++) {
    const d = Math.hypot(nodes[i][0] - s.x, nodes[i][1] - s.z);
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}

// #6 личная позиция удержания — боты РАЗБЕГАЮТСЯ по сайту, а не кучкуются в точке
function botHoldSpot(bot, siteKey) {
  const s = match.mapDef.sites[siteKey];
  const idx = bot.id % 7;
  const ang = (idx / 7) * Math.PI * 2 + bot.id * 0.9;
  const rx = (s.w / 2 - 1.4) * (0.45 + (idx % 3) * 0.27);
  const rz = (s.d / 2 - 1.4) * (0.45 + (idx % 2) * 0.4);
  return [s.x + Math.cos(ang) * rx, (s.z || 0) + Math.sin(ang) * rz];
}
function botGoHold(bot, dt, combat, siteKey) {
  const ai = bot.ai;
  if (!ai.holdSpot) ai.holdSpot = botHoldSpot(bot, siteKey);
  const hd = Math.hypot(bot.lastPos[0] - ai.holdSpot[0], bot.lastPos[2] - ai.holdSpot[1]);
  if (hd > 1.1) { if (!combat) moveToward(bot, [ai.holdSpot[0], 0, ai.holdSpot[1]], dt); }
  else if (!combat) bot.yaw += dt * 0.6; // держит свою позицию, сканирует
}

function botShoot(bot, e, dist) {
  const t = now();
  const ai = bot.ai;
  const w = botWeapon(bot);
  // ПЛАВНЫЙ доворот на цель (не мгновенный снап на 180)
  const tgtYaw = Math.atan2(-(e.lastPos[0] - bot.lastPos[0]), -(e.lastPos[2] - bot.lastPos[2]));
  let dy = tgtYaw - bot.yaw;
  while (dy > Math.PI) dy -= Math.PI * 2;
  while (dy < -Math.PI) dy += Math.PI * 2;
  bot.yaw += dy * 0.32;                 // догоняет цель пошустрее
  if (t < ai.reactAt) return;           // время реакции после засечки — есть окно на фланг
  if (Math.abs(dy) > 0.5) return;       // ещё не довёл прицел — не стреляет «спиной»
  if (t < ai.nextShot) return;
  ai.nextShot = t + Math.max(0.12, 60 / w.rpm) + Math.random() * 0.12;
  const spr = 1.0 + Math.min(1.7, dist * 0.04); // прицел заметно точнее
  const dir = [
    e.lastPos[0] - bot.lastPos[0] + (Math.random() - 0.5) * spr,
    (e.lastPos[1] + 1.2) - (bot.lastPos[1] + 1.6),
    e.lastPos[2] - bot.lastPos[2] + (Math.random() - 0.5) * spr,
  ];
  const len = Math.hypot(...dir) || 1;
  const bw = bot.loadout.primary || bot.loadout.sidearm || 'classic';
  broadcast({ t: 'shoot', id: bot.id, o: botEye(bot), d: dir.map(v => v / len), w: bw });
  addNoise(bot, !(WEAPONS[bw] && WEAPONS[bw].silenced));
  if (TICK_TELEMETRY) _botShots++;
  // адекватный вызов: попадают заметно чаще, иногда вешают голову
  const pHit = Math.max(0.13, Math.min(0.42, 0.46 - dist * 0.009));
  if (Math.random() < pHit) {
    if (TICK_TELEMETRY) _botHits++;
    const head = Math.random() < 0.13;  // 13% голов
    applyDamage(e, head ? w.head : w.dmg, bot.id, bw, head ? 'head' : 'body');
  }
}

// ===== боты используют способности =====
function botBroadcastAbility(bot, kind, data) {
  broadcast({ t: 'ability', id: bot.id, kind, data: data || {} });
}
function botZoneAt(bot, ztype, point, r, dur, dps) {
  // сервер-зона (для урона ботам) + бросок-визуал к точке (люди сами репортят урон)
  match.zones.push({ type: 'circle', pos: [point[0], 0, point[2]], r, dps, from: now(), until: now() + dur, owner: bot.id });
  const eye = botEye(bot);
  const dir = [point[0] - eye[0], 0.4 - eye[1] + (point[1] || 0), point[2] - eye[2]];
  const dl = Math.hypot(...dir) || 1;
  const d = dir.map(v => v / dl);
  if (ztype === 'fire') botBroadcastAbility(bot, 'molly', { from: eye, dir: d });
  else botBroadcastAbility(bot, 'throwZone', { from: eye, dir: d, kind: ztype });
}
function botFlash(bot, enemy, tapok) {
  const eye = botEye(bot);
  const tgt = enemy ? enemy.lastPos : [bot.lastPos[0] - Math.sin(bot.yaw) * 8, 1.4, bot.lastPos[2] - Math.cos(bot.yaw) * 8];
  const dir = [tgt[0] - eye[0], 1.4 - eye[1], tgt[2] - eye[2]];
  const dl = Math.hypot(...dir) || 1;
  botBroadcastAbility(bot, 'flash', { from: eye, dir: dir.map(v => v / dl), tapok: !!tapok });
  const popX = eye[0] + (tgt[0] - eye[0]) / (dl / (ABILITY.FLASH_SPEED * ABILITY.FLASH_FUSE));
  const popZ = eye[2] + (tgt[2] - eye[2]) / (dl / (ABILITY.FLASH_SPEED * ABILITY.FLASH_FUSE));
  setTimeout(() => { if (liveish()) blindBots([popX, 1.5, popZ]); }, ABILITY.FLASH_FUSE * 1000);
}
function botSmoke(bot) {
  const p = [bot.lastPos[0] - Math.sin(bot.yaw) * 6, 0, bot.lastPos[2] - Math.cos(bot.yaw) * 6];
  match.smokes.push({ pos: p, r: ABILITY.SMOKE_R, until: now() + ABILITY.SMOKE_TIME });
  botBroadcastAbility(bot, 'smokes', { positions: [p], stink: bot.char === 'denis' });
}
function botHealAllies(bot, pos, r, amount) {
  for (const q of players.values()) {
    if (q.alive && q.team === bot.team && Math.hypot(q.lastPos[0] - pos[0], q.lastPos[2] - pos[2]) < r) heal(q, amount);
  }
}

function botUseAbility(bot, seen, combat) {
  const t = now();
  const ai = bot.ai;
  if (t < ai.nextAbility || !liveish()) return;
  const cost = CHARACTERS[bot.char].ultCost;
  const e = ai.target;
  const cd = (s) => { ai.nextAbility = t + s; };

  switch (bot.char) {
    case 'artemiy':
      if (bot.hp < 45 && bot.ult >= cost) {
        bot.ult -= cost;
        bot.ultMark = { pos: [...bot.lastPos], yaw: bot.yaw, until: t + ABILITY.PHOENIX_ULT_TIME };
        botBroadcastAbility(bot, 'ultMark', { pos: [...bot.lastPos], yaw: bot.yaw });
        cd(10);
      } else if (combat && e) { botZoneAt(bot, 'fire', e.lastPos, ABILITY.FIRE_ZONE_R, ABILITY.FIRE_ZONE_TIME, ABILITY.FIRE_DPS); cd(8); }
      break;
    case 'vova':
      if (bot.ult >= cost && combat && e) {
        bot.ult -= cost;
        match.zones.push({ type: 'circle', pos: [e.lastPos[0], 0, e.lastPos[2]], r: ABILITY.ORBITAL_R, dps: ABILITY.ORBITAL_DPS, from: t + ABILITY.ORBITAL_DELAY, until: t + ABILITY.ORBITAL_DELAY + ABILITY.ORBITAL_DUR, owner: bot.id });
        botBroadcastAbility(bot, 'orbital', { pos: [e.lastPos[0], 0, e.lastPos[2]] });
        cd(13);
      } else if (combat && e) { botFlash(bot, e); cd(7); }
      else { botSmoke(bot); cd(10); }
      break;
    case 'sanek':
      if (combat && e) { botZoneAt(bot, 'acid', e.lastPos, ABILITY.ACID_R, ABILITY.ACID_TIME, ABILITY.ACID_DPS); cd(8); }
      break;
    case 'denis':
      if (bot.ult >= cost && combat && e && seen && seen.dist < ABILITY.COCOON_RANGE && !match.cocoon) {
        bot.ult -= cost;
        applyDamage(e, ABILITY.COCOON_HIT_DMG, bot.id, 'hook', 'body');
        if (e.alive) {
          match.cocoon = { victim: e.id, by: bot.id, hp: ABILITY.COCOON_HP, until: t + ABILITY.COCOON_TIME };
          broadcast({ t: 'cocoon', victim: e.id, by: bot.id, tLeft: ABILITY.COCOON_TIME });
          botBroadcastAbility(bot, 'cocoonHit', { target: e.id });
        }
        cd(11);
      } else if (bot.hp < bot.maxHp - 35) {
        // Кровопир: подъедается, когда ранен
        const fed = t - bot.lastKillT < ABILITY.BLOODFEAST_FED_WINDOW;
        heal(bot, fed ? ABILITY.BLOODFEAST_FED : ABILITY.BLOODFEAST_INSTANT);
        bot._hotUntil = t + ABILITY.BLOODFEAST_HOT_TIME; bot._hotRate = fed ? ABILITY.BLOODFEAST_HOT_FED : ABILITY.BLOODFEAST_HOT;
        bot.lastKillT = -99;
        botBroadcastAbility(bot, 'bloodfeast', {});
        cd(9);
      } else if (!combat) { botSmoke(bot); cd(11); }
      break;
    case 'fafik':
      // дуэлянт: бросает тапок-флешку по врагу (клоны-мобильность оставим людям)
      if (combat && e) { botFlash(bot, e, true); cd(8); }
      break;
    case 'koniliy':
      if (bot.ult >= cost && combat && e) {
        bot.ult -= cost;
        const a = [bot.lastPos[0], 0, bot.lastPos[2]];
        let dx = e.lastPos[0] - a[0], dz = e.lastPos[2] - a[2]; const dl = Math.hypot(dx, dz) || 1;
        const len = Math.min(ABILITY.STAMPEDE_LEN, Math.max(8, dl));
        const b = [a[0] + dx / dl * len, 0, a[2] + dz / dl * len];
        for (const en of players.values()) {
          if (en.team === bot.team || !en.alive) continue;
          if (distToSeg2D(en.lastPos, a, b) < ABILITY.STAMPEDE_WIDTH) {
            // табун только ОГЛУШАЕТ, урона нет
            if (en.bot) en.ai.stunUntil = now() + ABILITY.STAMPEDE_STUN;
            else send(en, { t: 'stun', dur: ABILITY.STAMPEDE_STUN });
          }
        }
        botBroadcastAbility(bot, 'stampede', { from: [a[0], 0, a[2]], to: [b[0], b[2]] });
        cd(13);
      } else if (combat && e) { botZoneAt(bot, 'horseshoe', e.lastPos, ABILITY.HORSESHOE_R, ABILITY.HORSESHOE_TIME, ABILITY.HORSESHOE_DPS); cd(8); }
      break;
    case 'ira': {
      let hurt = null, hd = 1e9;
      for (const q of players.values()) {
        if (q.team !== bot.team || !q.alive) continue;
        if (q.hp < q.maxHp - 20) { const d = Math.hypot(q.lastPos[0] - bot.lastPos[0], q.lastPos[2] - bot.lastPos[2]); if (d < hd) { hd = d; hurt = q; } }
      }
      if (bot.ult >= cost && hurt) {
        bot.ult -= cost;
        const pos = [bot.lastPos[0], 0, bot.lastPos[2]];
        botHealAllies(bot, pos, ABILITY.BANQUET_R, ABILITY.BANQUET_INSTANT);
        match.healZones.push({ kind: 'banquet', team: bot.team, pos, r: ABILITY.BANQUET_R, rate: ABILITY.BANQUET_REGEN, until: t + ABILITY.BANQUET_TIME });
        botBroadcastAbility(bot, 'banquet', { pos });
        cd(15);
      } else if (hurt && hd < 12) {
        const pos = [hurt.lastPos[0], 0, hurt.lastPos[2]];
        botHealAllies(bot, pos, ABILITY.BUFFET_R, ABILITY.BUFFET_HEAL);
        botBroadcastAbility(bot, 'buffetPop', { pos });
        cd(9);
      }
      break;
    }
    case 'max':
      if (combat && e && seen && seen.dist > 6) {
        let dx = e.lastPos[0] - bot.lastPos[0], dz = e.lastPos[2] - bot.lastPos[2]; const dl = Math.hypot(dx, dz) || 1;
        { const [dnx, dnz] = collideXZ(bot.lastPos[0], bot.lastPos[2], bot.lastPos[0] + dx / dl * ABILITY.DASH_DIST, bot.lastPos[2] + dz / dl * ABILITY.DASH_DIST, bot.lastPos[1]); bot.lastPos[0] = dnx; bot.lastPos[2] = dnz; }
        botBroadcastAbility(bot, 'dash', {});
        cd(7);
      }
      break;
  }
}

function tickBot(bot, dt) {
  const t = now();
  const ai = bot.ai;
  if (!bot.alive) return;
  if (match.cocoon && match.cocoon.victim === bot.id) return;
  if (t < ai.stunUntil) return;          // оглушён табуном — стоит
  if (match.state === PHASES.BUY) return; // заморозка на закупке

  const side = sideOfTeam(bot.team);
  const blinded = t < ai.blindUntil;      // ослеплён вспышкой — не видит и не стреляет
  const seen = blinded ? null : botVisibleEnemy(bot);
  if (seen) {
    // засёк новую цель (или после потери) — задержка реакции: у тебя есть окно
    if (ai.target !== seen.enemy || t >= ai.engaging) ai.reactAt = t + 0.14 + Math.random() * 0.18;
    ai.engaging = t + 1.4; ai.target = seen.enemy; ai.targetDist = seen.dist;
  }
  const combat = !blinded && t < ai.engaging && ai.target && ai.target.alive;

  // стрельба поверх движения (не замораживает бота)
  if (combat && seen) botShoot(bot, ai.target, seen.dist);
  // способности агента (не колдует ослеплённым)
  if (!blinded) botUseAbility(bot, seen, combat);

  // реакция на ЗВУК: не в бою и не ослеплён — поворачивается на шум, близкий проверяет
  if (!combat && !blinded) {
    const heard = botHearEnemy(bot);
    if (heard) { ai.heardPos = heard; ai.heardUntil = t + 1.6; }
    if (ai.heardPos && t < ai.heardUntil) {
      const hdx = ai.heardPos[0] - bot.lastPos[0], hdz = ai.heardPos[1] - bot.lastPos[2];
      bot.yaw = Math.atan2(-hdx, -hdz); // пре-аим на звук
      const hd = Math.hypot(hdx, hdz);
      if (hd > 2.5 && hd < 13) { moveToward(bot, [ai.heardPos[0], 0, ai.heardPos[1]], dt, true); return; }
    }
  }

  // близкий враг — придержать позицию для точности (дуэль в упор)
  const holdForDuel = combat && seen && seen.dist < 12;

  // --- назначение цели по фазе ---
  if (side === 'attack') {
    if (match.state === PHASES.LIVE) {
      const isCarrier = match.spikeCarrier === bot.id;
      // шип лежит на земле — свободные атакеры бегут подбирать
      if (match.spikeDropped && !isCarrier) {
        if (ai.goal !== 'fetch') botSetGoal(bot, navNearest(match.spikeDropped.pos), 'fetch');
        if (ai.pathIdx >= ai.path.length) {
          moveToward(bot, [match.spikeDropped.pos[0], match.spikeDropped.pos[1], match.spikeDropped.pos[2]], dt, combat);
          return;
        }
      } else if (ai.goal === 'fetch' && !match.spikeDropped) {
        // шип подобрали — возвращаемся к плану
        ai.goal = null; ai.site = null; ai.path = []; ai.pathIdx = 0;
      }
      if (!ai.site) {
        ai.site = Math.random() < 0.5 ? 'A' : 'B';
        botSetGoal(bot, botPlantNode(ai.site), isCarrier ? 'plant' : 'hold');
      }
      // подобрал шип по пути — теперь его очередь плантить
      if (isCarrier && ai.goal === 'hold') ai.goal = 'plant';
      if (ai.goal === 'plant' && isCarrier && ai.pathIdx >= ai.path.length && inSite(bot.lastPos)) {
        if (!match.planting && !combat) { // при враге рядом сначала отбиться
          match.planting = { by: bot.id, start: t, pos: [...bot.lastPos] };
          broadcast({ t: 'plantProg', pct: 0 });
        }
        if (match.planting && match.planting.by === bot.id) { if (!combat) return; }
        else if (!combat) { bot.yaw += dt * 0.8; return; }
      } else if (ai.goal === 'hold' && ai.pathIdx >= ai.path.length) {
        botGoHold(bot, dt, combat, ai.site); // прикрывает носителя, разбегаясь по сайту
        if (!combat) return;
      }
    } else if (match.state === PHASES.PLANTED) {
      if (ai.goal !== 'holdSpike') botSetGoal(bot, navNearest(match.spike.pos), 'holdSpike');
      if (ai.pathIdx >= ai.path.length && !combat) { botGoHold(bot, dt, combat, ai.site || 'A'); return; }
    }
  } else {
    if (match.state === PHASES.LIVE) {
      if (!ai.site) { ai.site = Math.random() < 0.5 ? 'A' : 'B'; botSetGoal(bot, botPlantNode(ai.site), 'hold'); }
      if (ai.goal === 'hold' && ai.pathIdx >= ai.path.length) {
        botGoHold(bot, dt, combat, ai.site); // РАЗБЕГАЮТСЯ по сайту, не кучкуются
        return;
      }
    } else if (match.state === PHASES.PLANTED) {
      if (ai.goal !== 'defuse') botSetGoal(bot, navNearest(match.spike.pos), 'defuse');
      if (ai.pathIdx >= ai.path.length) {
        const d = Math.hypot(bot.lastPos[0] - match.spike.pos[0], bot.lastPos[2] - match.spike.pos[2]);
        if (d > 1.6 && !holdForDuel) {
          moveToward(bot, [match.spike.pos[0], match.spike.pos[1], match.spike.pos[2]], dt);
        } else if (!match.defusing && !combat) {
          match.defusing = { by: bot.id, start: t };
          broadcast({ t: 'defuseProg', pct: match.defuseAccum / RULES.DEFUSE_TIME });
        }
        return;
      }
    }
  }

  // --- движение по пути (продолжается даже в бою, кроме дуэли в упор) ---
  if (!holdForDuel && ai.pathIdx < ai.path.length) {
    const node = match.mapDef.nav.nodes[ai.path[ai.pathIdx]];
    const target = [node[0], node[2] || 0, node[1]];
    if (moveToward(bot, target, dt, combat) < 1.1) { ai.pathIdx++; ai._stuckT = 0; }
    else if (ai._blocked) {                       // упёрся — копим и обходим/перестраиваемся
      ai._stuckT = (ai._stuckT || 0) + dt;
      if (ai._stuckT > 0.5) { ai._stuckT = 0; ai.pathIdx++; }              // пропускаем ноду
      if (ai.pathIdx >= ai.path.length) { ai.goal = null; ai.nextThink = 0; } // путь кончился — переосмыслить
    } else ai._stuckT = 0;
  }
}

// коллизия бота со стенами: круг (радиус) vs AABB, со скольжением вдоль оси.
// учитывает уровень по Y (платформы/мосты на другой высоте не мешают).
const BOT_R = 0.34;
function botHitsWall(x, z, y) {
  const yBot = y + 0.25, yTop = y + 1.55;
  for (const b of match.aabbs) {
    if ((b.maxY - b.minY) < 2.9) continue;   // только НАСТОЯЩИЕ стены; мелкие укрытия/платформы/насесты бот обходит (не застревает)
    if (b.maxY <= yBot || b.minY >= yTop) continue;
    if (x + BOT_R > b.minX && x - BOT_R < b.maxX && z + BOT_R > b.minZ && z - BOT_R < b.maxZ) return true;
  }
  return false;
}
function collideXZ(px, pz, nx, nz, y) {
  let rx = nx, rz = nz;
  if (botHitsWall(rx, pz, y)) rx = px;              // упёрлись по X — скользим вдоль Z
  if (botHitsWall(rx, rz, y)) rz = pz;              // упёрлись по Z
  if (botHitsWall(rx, rz, y)) { rx = px; rz = pz; } // угол — стоим
  return [rx, rz];
}

function moveToward(bot, target, dt, combat = false) {
  const dx = target[0] - bot.lastPos[0], dz = target[2] - bot.lastPos[2];
  const d = Math.hypot(dx, dz);
  let speed = combat ? 3.6 : 5.5; // в бою идут медленнее (осторожнее)
  if (now() < bot.tagUntil) speed *= 0.62; // словил пулю — вязнет
  if (d > 0.01) {
    const step = Math.min(d, speed * dt);
    const bx = bot.lastPos[0], bz = bot.lastPos[2];
    const [nx, nz] = collideXZ(bx, bz, bx + dx / d * step, bz + dz / d * step, bot.lastPos[1]);
    bot.lastPos[0] = nx;
    bot.lastPos[2] = nz;
    const moved = Math.hypot(nx - bx, nz - bz);
    bot.ai._blocked = moved < step * 0.35;   // почти не сдвинулся = упёрся в стену/ящик
    bot.ai._noiseAcc = (bot.ai._noiseAcc || 0) + moved;
    if (bot.ai._noiseAcc > 2.7) { bot.ai._noiseAcc = 0; addNoise(bot, false); }
    // высота — плавно к высоте цели (лестницы)
    bot.lastPos[1] += (target[1] - bot.lastPos[1]) * Math.min(1, dt * 6);
    if (!combat) bot.yaw = Math.atan2(-dx, -dz); // в бою прицел держит botShoot
  }
  return d;
}

// ===== Главный тик (20 Гц) =====
const TICK_TELEMETRY = !!process.env.TICK_TELEMETRY;  // гейт-замер p95 тика + точность ботов (в проде выключен)
const _tickTimes = [];
let _botShots = 0, _botHits = 0;                       // ТОЛЬКО пули ботов (для точности в гейте)
setInterval(() => {
  const _t0 = TICK_TELEMETRY ? process.hrtime.bigint() : 0n;
  const t = now();
  if (!match.running) return;

  // фазы
  switch (match.state) {
    case PHASES.BUY:
      if (t >= match.deadline) startLive();
      break;
    case PHASES.LIVE: {
      if (match.planting) {
        const pct = (t - match.planting.start) / RULES.PLANT_TIME;
        if (pct >= 1) {
          const planter = players.get(match.planting.by);
          match.spike = { pos: [...match.planting.pos], boomAt: t + RULES.SPIKE_TIME };
          match.spikeCarrier = null;
          match.planting = null;
          match.state = PHASES.PLANTED;
          match.deadline = match.spike.boomAt;
          if (planter) {
            planter.credits = Math.min(RULES.MAX_CREDITS, planter.credits + RULES.PLANT_REWARD);
            // плант больше не даёт ульту (канон: только за киллы)
            send(planter, { t: 'credits', credits: planter.credits });
          }
          broadcast({ t: 'planted', pos: match.spike.pos, tLeft: RULES.SPIKE_TIME });
          for (const b of players.values()) if (b.bot) { b.ai.goal = null; b.ai.site = null; }
          const defTeam = enemyTeam(match.attackTeam);
          if (teamAliveCount(defTeam) === 0) endRound(match.attackTeam, 'elim');
        } else {
          broadcast({ t: 'plantProg', pct });
        }
      }
      // подбор лежащего шипа любым живым атакером
      if (match.spikeDropped) {
        for (const q of players.values()) {
          if (!q.alive || sideOfTeam(q.team) !== 'attack') continue;
          if (Math.hypot(q.lastPos[0] - match.spikeDropped.pos[0], q.lastPos[2] - match.spikeDropped.pos[2]) < 1.5) {
            match.spikeCarrier = q.id;
            match.spikeDropped = null;
            broadcast({ t: 'spikePick', id: q.id });
            break;
          }
        }
      }
      // подбор брошенного оружия с трупов (только апгрейд — ствол дороже текущего)
      if (match.pickups && match.pickups.length) {
        for (const pk of match.pickups) {
          if (pk.taken) continue;
          if (t >= pk.until) { pk.taken = true; broadcast({ t: 'weaponGone', id: pk.id }); continue; }
          for (const q of players.values()) {
            if (!q.alive) continue;
            if (Math.hypot(q.lastPos[0] - pk.pos[0], q.lastPos[2] - pk.pos[2]) > ABILITY.PICKUP_R) continue;
            const cur = WEAPONS[q.loadout.primary], nw = WEAPONS[pk.weapon];
            if (!nw || (cur && cur.price >= nw.price)) continue; // не апгрейд — не берём
            q.loadout.primary = pk.weapon; pk.taken = true;
            broadcast({ t: 'weaponPickup', id: pk.id, by: q.id, weapon: pk.weapon });
            if (!q.bot) send(q, { t: 'setWeapon', weapon: pk.weapon });
            break;
          }
        }
        match.pickups = match.pickups.filter(pk => !pk.taken);
      }
      if (match.state === PHASES.LIVE && t >= match.deadline) endRound(enemyTeam(match.attackTeam), 'time');
      break;
    }
    case PHASES.PLANTED: {
      if (match.defusing) {
        const total = match.defuseAccum + (t - match.defusing.start);
        if (!match.defuseHalfDone && total >= RULES.DEFUSE_TIME / 2) {
          match.defuseHalfDone = true;
          broadcast({ t: 'defuseHalf' });
        }
        const pct = total / RULES.DEFUSE_TIME;
        if (pct >= 1) {
          match.defusing = null;
          // дефуз больше не даёт ульту (канон: только за киллы)
          broadcast({ t: 'defused' });
          endRound(enemyTeam(match.attackTeam), 'defuse');
        } else {
          broadcast({ t: 'defuseProg', pct });
        }
      }
      if (match.state === PHASES.PLANTED && t >= match.deadline) {
        broadcast({ t: 'boom', pos: match.spike.pos });
        endRound(match.attackTeam, 'boom');
      }
      break;
    }
    case PHASES.ROUND_END:
      if (t >= match.deadline) startRound();
      return;
    case PHASES.MATCH_END:
      if (t >= match.deadline) backToLobby();
      return;
  }

  // ульт Артемия — возврат по таймеру
  for (const p of players.values()) {
    if (p.ultMark && t >= p.ultMark.until) {
      const mark = p.ultMark;
      p.ultMark = null;
      if (p.alive) {
        p.hp = p.maxHp;
        p.lastPos = [...mark.pos];
        broadcast({ t: 'revive', id: p.id, pos: mark.pos, yaw: mark.yaw, hp: p.hp });
      }
    }
  }

  // кокон Дениса
  if (match.cocoon) {
    const c = match.cocoon;
    const victim = players.get(c.victim);
    const denis = players.get(c.by);
    if (!victim || !victim.alive || !denis || !denis.alive) {
      if (victim && victim.alive) broadcast({ t: 'cocoonEnd', victim: c.victim, freed: true });
      match.cocoon = null;
    } else {
      // бот-жертву тащим на сервере (человек тащит себя сам на клиенте)
      if (victim.bot) {
        const dx = denis.lastPos[0] - victim.lastPos[0], dz = denis.lastPos[2] - victim.lastPos[2];
        const d = Math.hypot(dx, dz);
        if (d > 1.6) {
          const step = Math.min(d - 1.5, 9 * 0.05);
          victim.lastPos[0] += dx / d * step;
          victim.lastPos[2] += dz / d * step;
        }
      }
      if (t >= c.until) {
        match.cocoon = null;
        broadcast({ t: 'cocoonEnd', victim: c.victim, freed: false });
        applyDamage(victim, 9999, c.by, 'hook', 'ult');
      }
    }
  }

  if (liveish()) {
    // урон зон по ботам (люди сами репортят selfDamage)
    for (const z of match.zones) {
      if (t < z.from || t > z.until) continue;
      for (const b of players.values()) {
        if (!b.bot || !b.alive) continue;
        let inside = false;
        if (z.type === 'circle') {
          inside = Math.hypot(b.lastPos[0] - z.pos[0], b.lastPos[2] - z.pos[2]) < z.r && b.lastPos[1] < (z.pos[1] || 0) + 2.5;
        } else {
          inside = distToSeg2D(b.lastPos, z.a, z.b) < z.r;
        }
        if (inside) applyDamage(b, z.dps * 0.05, z.owner, 'zone', 'zone');
      }
    }
    match.zones = match.zones.filter(z => t <= z.until);
    match.smokes = match.smokes.filter(s => t <= s.until);

    // хил-зоны Иры: лечим союзников (люди и боты) по позиции, дробный аккумулятор
    if (match.healZones.length) {
      for (const q of players.values()) {
        if (!q.alive || q.hp >= q.maxHp) continue;
        let rate = 0;
        for (const hz of match.healZones) {
          if (q.team !== hz.team) continue;
          let inside = false;
          if (hz.kind === 'crispy') inside = distToSeg2D(q.lastPos, hz.a, hz.b) < 1.4 && q.lastPos[1] < 2.6;
          else inside = Math.hypot(q.lastPos[0] - hz.pos[0], q.lastPos[2] - hz.pos[2]) < hz.r;
          if (inside) rate = Math.max(rate, hz.rate);
        }
        if (rate > 0) {
          q._healFrac = (q._healFrac || 0) + rate * 0.05;
          if (q._healFrac >= 1) {
            const whole = Math.floor(q._healFrac);
            q._healFrac -= whole;
            heal(q, whole);
          }
        }
      }
    }
    match.healZones = match.healZones.filter(z => t <= z.until);

    // Денис: реген Кровопира (HoT)
    for (const p of players.values()) {
      if (!p.alive || t >= p._hotUntil || p.hp >= p.maxHp) continue;
      p._healFrac = (p._healFrac || 0) + p._hotRate * 0.05;
      if (p._healFrac >= 1) { const whole = Math.floor(p._healFrac); p._healFrac -= whole; heal(p, whole); }
    }

    // Денис: «нюх мясника» — приманки палят врагов команде (раненых чуют вдвое дальше)
    for (const sc of match.scents) {
      if (t > sc.until) continue;
      for (const e of players.values()) {
        if (e.team === sc.team || !e.alive) continue;
        const d = Math.hypot(e.lastPos[0] - sc.pos[0], e.lastPos[2] - sc.pos[1]);
        const range = e.hp < ABILITY.SCENT_WOUND_HP ? ABILITY.SCENT_R * ABILITY.SCENT_BLOOD_MUL : ABILITY.SCENT_R;
        if (d >= range) continue;
        // не палит сквозь стены — нужна прямая видимость от приманки к врагу
        if (!losClear([sc.pos[0], 1.2, sc.pos[1]], [e.lastPos[0], e.lastPos[1] + 1.2, e.lastPos[2]])) continue;
        if (t > (sc.pinged.get(e.id) || 0)) {
          sc.pinged.set(e.id, t + ABILITY.SCENT_REVEAL * 0.8);
          broadcast({ t: 'ability', id: sc.owner, kind: 'scentPing', data: { target: e.id } });
        }
      }
    }
    match.scents = match.scents.filter(sc => t <= sc.until);

    // ИИ ботов
    for (const b of players.values()) {
      if (b.bot) {
        try { tickBot(b, 0.05); } catch (e) { console.error('bot error:', e.message); }
      }
    }
  }

  // трансляция состояния ботов
  for (const b of players.values()) {
    if (b.bot && b.alive && match.state !== PHASES.WAIT) {
      broadcast({ t: 'state', id: b.id, p: b.lastPos.map(v => +v.toFixed(2)), yaw: +b.yaw.toFixed(2), pitch: 0, crouch: false });
    }
  }
  if (TICK_TELEMETRY) {
    const ms = Number(process.hrtime.bigint() - _t0) / 1e6;
    _tickTimes.push(ms);
    if (_tickTimes.length >= 40) {
      const s = [..._tickTimes].sort((a, b) => a - b);
      console.log('TICKP95 ' + s[Math.floor(s.length * 0.95)].toFixed(2));
      console.log('BOTACC ' + _botHits + ' ' + _botShots);
      _tickTimes.length = 0;
    }
  }
}, 50);

function distToSeg2D(p, a, b) {
  const abx = b[0] - a[0], abz = b[2] - a[2];
  const len2 = abx * abx + abz * abz;
  let k = len2 ? ((p[0] - a[0]) * abx + (p[2] - a[2]) * abz) / len2 : 0;
  k = Math.max(0, Math.min(1, k));
  return Math.hypot(p[0] - (a[0] + abx * k), p[2] - (a[2] + abz * k));
}

// ===== WebSocket =====
const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
  if (humans().length >= RULES.TEAM_MAX * 2) {
    ws.send(JSON.stringify({ t: 'full' }));
    ws.close();
    return;
  }
  const id = nextHumanId++;
  const p = newPlayer(id, ws);
  players.set(id, p);
  console.log(`[+] Игрок ${id} подключился (людей: ${humans().length})`);
  send(p, { t: 'welcome', id });
  send(p, lobbyInfo());
  if (match.running) send(p, { t: 'matchAbort', reason: 'Матч уже идёт — подожди в лобби' });

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }
    try { onMessage(p, msg); } catch (e) { console.error('msg error:', e); }
  });

  ws.on('close', () => {
    if (match.running && match.state === PHASES.LIVE && match.spikeCarrier === id) {
      match.spikeCarrier = null;
      match.spikeDropped = { pos: [...p.lastPos] };
      broadcast({ t: 'spikeDrop', pos: match.spikeDropped.pos });
    }
    players.delete(id);
    console.log(`[-] Игрок ${id} отключился`);
    if (humans().length === 0) {
      // все люди вышли — чистим ботов и матч целиком, начинаем с нуля
      players.clear();
      match.running = false;
      match.state = PHASES.WAIT;
      match.planting = null; match.defusing = null; match.spike = null; match.cocoon = null;
      match.zones = []; match.healZones = []; match.smokes = [];
      return;
    } else if (match.running) {
      broadcast({ t: 'chat', id: 0, text: `${p.name} покинул матч` });
      // если вся команда из людей ушла и ботов в ней нет — конец
      if (teamOf(p.team).length === 0) {
        endRound(enemyTeam(p.team), 'elim');
        match.score[enemyTeam(p.team)] = RULES.ROUNDS_TO_WIN;
      }
    }
    broadcast(lobbyInfo());
  });
});

httpServer.listen(port, '0.0.0.0', () => {
  console.log('==========================================');
  console.log('  VALORANT LAN v2 — сервер запущен');
  console.log(`  Локально:  http://localhost:${port}`);
  import('os').then(os => {
    for (const ifaces of Object.values(os.networkInterfaces())) {
      for (const i of ifaces || []) {
        if (i.family === 'IPv4' && !i.internal) console.log(`  По сети:   http://${i.address}:${port}  <- дай эту ссылку друзьям`);
      }
    }
    console.log('==========================================');
  });
});
