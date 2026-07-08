// Точка входа v2: меню → лобби (команды/боты/карта) → матч.
import * as THREE from './three.module.js';
import { Net } from './net.js';
import { Sfx } from './audio.js';
import { buildMap } from './map.js';
import { Effects } from './effects.js';
import { LocalPlayer } from './player.js';
import { WeaponSystem } from './weapons.js';
import { RemotePlayer } from './remote.js';
import { Abilities } from './abilities.js';
import { HUD } from './hud.js';
import { makeComposer } from './postfx.js';
import { WEAPONS, CHARACTERS, MAPS, PHASES, ABILITY, BOT_PRESETS, PASSIVES, ICONS } from './shared.js';

const DIFF_NAMES = { easy: 'ЛЁГКИЕ', medium: 'СРЕДНИЕ', hard: 'ЖЁСТКИЕ' };

// IBL-окружение: эквирект-небо с солнцем → PMREM. Даёт металлу оружия реалистичные отражения.
function makeEnvMap(renderer) {
  const cv = document.createElement('canvas');
  cv.width = 512; cv.height = 256;
  const c = cv.getContext('2d');
  const g = c.createLinearGradient(0, 0, 0, 256);
  g.addColorStop(0, '#243a56'); g.addColorStop(0.45, '#8fa6bd');
  g.addColorStop(0.52, '#cfd6d2'); g.addColorStop(1, '#3f4a44');
  c.fillStyle = g; c.fillRect(0, 0, 512, 256);
  // солнце
  const sg = c.createRadialGradient(150, 70, 4, 150, 70, 70);
  sg.addColorStop(0, 'rgba(255,248,225,1)'); sg.addColorStop(1, 'rgba(255,248,225,0)');
  c.fillStyle = sg; c.beginPath(); c.arc(150, 70, 70, 0, 7); c.fill();
  const tex = new THREE.CanvasTexture(cv);
  tex.mapping = THREE.EquirectangularReflectionMapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const env = pmrem.fromEquirectangular(tex).texture;
  tex.dispose(); pmrem.dispose();
  return env;
}

// Настоящее небо + IBL из HDRI (Poly Haven CC0), если скачано. Иначе остаётся процедурное окружение.
async function loadHdriEnv(renderer, scene) {
  let manifest;
  try { manifest = await (await fetch('assets/manifest.json')).json(); } catch (e) { return false; }
  const url = manifest?.hdri?.sky;
  if (!url) return false;
  const { RGBELoader } = await import('./three/loaders/RGBELoader.js');
  const tex = await new Promise((res, rej) => new RGBELoader().load(url, res, undefined, rej));
  tex.mapping = THREE.EquirectangularReflectionMapping;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const env = pmrem.fromEquirectangular(tex).texture;
  pmrem.dispose();
  scene.environment = env;             // IBL: настоящие отражения/свет
  scene.environmentIntensity = 0.55;   // приглушаем, иначе яркое небо флудит ambient и роняет контраст
  scene.background = tex;              // настоящее небо в фоне
  scene.backgroundIntensity = 0.45;    // тусклее — солнце не слепит и не раздувает bloom (без дорогого blur неба)
  const dome = scene.getObjectByName('proceduralSky');
  if (dome) dome.visible = false;      // прячем процедурный купол
  if (scene.fog) scene.fog.far = 260;  // отодвигаем туман, чтобы небо читалось
  G.hdriOn = true;
  return true;
}

const $ = (id) => document.getElementById(id);
const now = () => performance.now() / 1000;

// маркер брошенного оружия на земле (силуэт ствола + подсветка-кольцо)
function makePickupMarker(pos, seeThrough = false) {
  const g = new THREE.Group();
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.09, 0.13),
    new THREE.MeshStandardMaterial({ color: 0x1b1e24, roughness: 0.5, metalness: 0.4 }));
  body.position.y = 0.14; body.rotation.y = 0.5;
  g.add(body);
  const ring = new THREE.Mesh(new THREE.RingGeometry(0.35, 0.5, 20),
    new THREE.MeshBasicMaterial({ color: 0x14d3c0, transparent: true, opacity: 0.5, side: THREE.DoubleSide, depthWrite: false }));
  ring.rotation.x = -Math.PI / 2; ring.position.y = 0.04;
  g.add(ring);
  if (seeThrough) {   // пассивка Совы: видит иконки брошенного оружия СКВОЗЬ стены
    g.traverse(o => { if (o.material) { o.material.depthTest = false; o.material.transparent = true; o.renderOrder = 999; } });
  }
  g.position.set(pos[0], pos[1] || 0, pos[2]);
  return g;
}
function clearPickupMarkers() {
  if (!G.pickupMarkers) return;
  for (const m of G.pickupMarkers.values()) G.scene.remove(m);
  G.pickupMarkers.clear();
}

const ABILITY_WEAPON_NAMES = {
  hook: 'Мясной крюк', fire: 'Огонь', puddle: 'Тухлятина', acid: 'Кислота',
  orbital: 'Орбитальный удар', turret: 'Турель', knives: 'Стальные перья', zone: 'Зона',
  mangal: 'Мангал', horseshoe: 'Подкова', stampede: 'Табун',
  sovaShock: 'Шок-стрела', sovaFury: 'Ярость охотника',
  geraUlt: 'Невесомость',
};

// ===== Глобальное состояние =====
const G = {
  scene: null, camera: null, renderer: null,
  net: null, myId: 0, myTeam: 'A', side: 'attack',
  me: { name: 'Игрок', char: 'artemiy', hp: 100, maxHp: 100, armor: 0, credits: 800, ult: 0, alive: true },
  players: new Map(),   // id -> {id, name, char, team, bot}
  remotes: new Map(),   // id -> RemotePlayer
  stats: {},            // id -> {kills, deaths}
  phase: PHASES.WAIT, round: 0, score: { A: 0, B: 0 },
  deadline: 0,
  freeze: true,
  map: null, player: null,
  weapons: null, abilities: null, fx: null, sfx: new Sfx(), hud: null,
  spikePos: null, spikeFx: null,
  spikeCarrier: 0, spikeDroppedPos: null, spikeDropFx: null,
  pulled: null, stunnedUntil: 0, slowMul: 1, blindUntil: 0, blindStink: false, shake: 0,
  boostUntil: 0, banquetUntil: 0, gallopUntil: 0, tagUntil: 0, levitUntil: 0, trapSlowUntil: 0, xrayUntil: 0, cocoonedId: null, knives: null,
  banquets: [], cloneMode: false, clonedIds: new Set(),
  scoped: false, aimT: 0, buyOpen: false, chatOpen: false, holdAction: null,
  spectateTarget: 0,
  spottedUntil: new Map(), revealed: new Map(),
  shootables: [],
  worldReady: false,
  relock: null,
  liveish() { return this.phase === PHASES.LIVE || this.phase === PHASES.PLANTED; },
};
window.G = G;

// #8 не дать случайно закрыть вкладку (Ctrl+W и пр.) посреди матча
window.addEventListener('beforeunload', (e) => {
  if (G.worldReady && G.phase !== PHASES.WAIT && G.phase !== PHASES.MATCH_END) { e.preventDefault(); e.returnValue = ''; }
});

// ===== Меню =====
let selChar = localStorage.getItem('valChar') || 'artemiy';

function buildMenu() {
  const wrap = $('charSelect');
  wrap.innerHTML = '';
  for (const [id, c] of Object.entries(CHARACTERS)) {
    const card = document.createElement('div');
    card.className = 'char-card' + (id === selChar ? ' sel' : '');
    card.style.setProperty('--card-color', c.color);
    const abils = Object.entries(c.abilities)
      .map(([k, a]) => `<div class="char-ab"><b>${k}</b> ${a.name} — ${a.desc}</div>`).join('');
    const p = PASSIVES[id];
    const passive = p ? `<div class="char-ab char-passive"><b>⚡</b> ${p.name} — ${p.desc}</div>` : '';
    card.innerHTML = `
      <div class="char-name" style="color:${c.color}"><span class="char-icon">${ICONS[id] || ''}</span> ${c.name}</div>
      <div class="char-title" style="color:${c.color}">${c.title.toUpperCase()}</div>
      <div class="char-desc">${c.desc}</div>${passive}${abils}`;
    card.addEventListener('click', () => {
      selChar = id;
      localStorage.setItem('valChar', id);
      for (const el of wrap.children) el.classList.remove('sel');
      card.classList.add('sel');
      if (G.net) G.net.send({ t: 'setChar', char: id });
    });
    wrap.appendChild(card);
  }
  $('nameInput').value = localStorage.getItem('valName') || '';
  $('addrInput').value = location.host || 'localhost:27015';
}
buildMenu();

$('btnPlay').addEventListener('click', () => {
  G.sfx.init();
  const name = $('nameInput').value.trim() || 'Игрок' + Math.floor(Math.random() * 100);
  localStorage.setItem('valName', name);
  G.me.name = name;
  G.me.char = selChar;
  const addr = $('addrInput').value.trim() || location.host;
  $('btnPlay').disabled = true;
  $('menuError').textContent = '';
  connect(addr);
});

function connect(addr) {
  G.net = new Net(`ws://${addr}`, onMessage, onDisconnect, () => {
    G.net.send({ t: 'join', name: G.me.name, char: G.me.char });
    $('menu').classList.add('hidden');
    $('lobbyOverlay').classList.remove('hidden');
    $('lobbyLinks').innerHTML = `Друзья заходят по адресу: <b>http://${addr}</b> <span style="color:#8b978f;font-size:11px">(точный LAN-адрес — в консоли сервера)</span>`;
  });
  setTimeout(() => {
    if (G.net.ws.readyState !== 1 && !G.worldReady) {
      $('btnPlay').disabled = false;
      $('menuError').textContent = 'Не удалось подключиться к ' + addr;
    }
  }, 4000);
}

function onDisconnect() {
  if (!G.worldReady) {
    $('menu').classList.remove('hidden');
    $('lobbyOverlay').classList.add('hidden');
    $('btnPlay').disabled = false;
    $('menuError').textContent = 'Соединение закрыто';
    return;
  }
  $('lobbyOverlay').classList.remove('hidden');
  $('lobbyStatus').textContent = 'Связь с сервером потеряна. Обнови страницу (F5).';
}

// ===== Мир =====
function initWorld(mapId) {
  if (!G.worldReady) {
    G.scene = new THREE.Scene();
    G.camera = new THREE.PerspectiveCamera(74, innerWidth / innerHeight, 0.05, 400);
    G.scene.add(G.camera);
    G.renderer = new THREE.WebGLRenderer({ antialias: true });
    G.renderer.setSize(innerWidth, innerHeight);
    G.renderer.setPixelRatio(Math.min(1.5, devicePixelRatio)); // ниже 2 — заметно больше FPS на hi-DPI при почти той же резкости
    G.renderer.shadowMap.enabled = true;
    G.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    G.renderer.outputColorSpace = THREE.SRGBColorSpace;
    G.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    G.renderer.toneMappingExposure = 0.98;
    $('game').appendChild(G.renderer.domElement);
    // IBL — процедурное окружение мгновенно, потом асинхронно подменяется настоящим HDRI (если скачан)
    try { G.scene.environment = makeEnvMap(G.renderer); } catch (e) { console.warn('IBL fail', e); }
    loadHdriEnv(G.renderer, G.scene).catch(e => console.warn('HDRI fail', e));
    // постпроцессинг (bloom/FXAA/грейд) с фолбэком на прямой рендер
    try { G.post = makeComposer(G.renderer, G.scene, G.camera); } catch (e) { console.warn('postfx fail', e); G.post = null; }
    addEventListener('resize', () => {
      G.camera.aspect = innerWidth / innerHeight;
      G.camera.updateProjectionMatrix();
      G.renderer.setSize(innerWidth, innerHeight);
      if (G.post) G.post.setSize(innerWidth, innerHeight);
    });
    G.map = buildMap(G.scene, MAPS[mapId], G.renderer);
    G.fx = new Effects(G.scene);
    G.player = new LocalPlayer(G);
    G.hud = new HUD(G);
    G.hud.bindLobby(lobbyHooks);
    G.weapons = new WeaponSystem(G);
    G.abilities = new Abilities(G);
    G.hud.buildBuy((item) => G.net.send({ t: 'buy', item }));
    G.hud.prepMinimap(G.map.def);
    $('game').classList.remove('hidden');
    $('hud').classList.remove('hidden');
    bindGameKeys();
    startLoops();
    G.worldReady = true;
  } else if (G.map.def.id !== mapId) {
    G.scene.remove(G.map.group);
    G.map = buildMap(G.scene, MAPS[mapId], G.renderer);
    if (G.hdriOn) { const d = G.scene.getObjectByName('proceduralSky'); if (d) d.visible = false; }
    G.hud.prepMinimap(G.map.def);
  }
}

// лобби-кнопки (навешиваются в HUD.bindLobby)
const lobbyHooks = {
  addBot: (team) => G.net.send({ t: 'addBot', team }),
  delBot: (team) => G.net.send({ t: 'removeBot', team }),
  setMap: (map) => G.net.send({ t: 'setMap', map }),
  setDifficulty: (difficulty) => G.net.send({ t: 'setDifficulty', difficulty }),
  switchTeam: () => G.net.send({ t: 'switchTeam' }),
  start: () => G.net.send({ t: 'startMatch' }),
  movePlayer: (id, curTeam) => G.net.send({ t: 'movePlayer', target: id, team: curTeam === 'A' ? 'B' : 'A' }),
  transferHost: (id) => G.net.send({ t: 'transferHost', target: id }),
  kickBot: (id) => G.net.send({ t: 'kickBot', target: id }),
  changeAgent: (charId) => {
    selChar = charId;
    localStorage.setItem('valChar', charId);
    G.me.char = charId;
    if (G.net) G.net.send({ t: 'setChar', char: charId });
  },
};
let lastLobby = null;

// ===== Обработка сообщений =====
function onMessage(msg) {
  switch (msg.t) {
    case 'welcome':
      G.myId = msg.id;
      break;
    case 'full':
      $('menuError').textContent = 'Сервер полон.';
      $('btnPlay').disabled = false;
      break;
    case 'lobby': {
      lastLobby = msg;
      // реестр игроков (нужен и в матче — имена, команды)
      for (const p of msg.players) {
        G.players.set(p.id, p);
        if (p.id === G.myId) G.myTeam = p.team;
      }
      // удаляем ушедших
      const ids = new Set(msg.players.map(p => p.id));
      for (const id of [...G.players.keys()]) {
        if (!ids.has(id)) {
          G.players.delete(id);
          const r = G.remotes.get(id);
          if (r) { r.dispose(); G.remotes.delete(id); }
        }
      }
      if (!msg.inMatch) {
        G.phase = PHASES.WAIT;
        G.freeze = true;
        if (G.hud) G.hud.hideEnd();
        $('lobbyOverlay').classList.remove('hidden');
        // renderLobby нужен и до создания мира
        if (!G.hud) {
          // временный рендер без HUD-класса: создаём мир заранее нельзя (карта неизвестна ок)
        }
      }
      renderLobbySafe(msg);
      break;
    }
    case 'matchStart': {
      G.stats = {};
      for (const p of msg.players) {
        G.players.set(p.id, p);
        G.stats[p.id] = { kills: 0, deaths: 0 };
        if (p.id === G.myId) { G.myTeam = p.team; }
      }
      initWorld(msg.map);
      // пересоздаём модели всех остальных
      for (const r of G.remotes.values()) r.dispose();
      G.remotes.clear();
      for (const p of msg.players) {
        if (p.id !== G.myId) G.remotes.set(p.id, new RemotePlayer(G, p.id, p));
      }
      G.hud.hideEnd();
      $('lobbyOverlay').classList.add('hidden');
      $('pauseOverlay').classList.remove('hidden');
      break;
    }
    case 'roundStart': onRoundStart(msg); break;
    case 'phase':
      if (msg.phase === PHASES.LIVE) {
        G.phase = PHASES.LIVE;
        G.freeze = false;
        G.deadline = now() + msg.tLeft;
        G.hud.closeBuy();
        G.hud.announce('БОЙ!', roleHint(), 2);
        G.sfx.roundStart();
        relock();
      }
      break;
    case 'state': {
      const r = G.remotes.get(msg.id);
      if (r) r.onState(msg);
      break;
    }
    case 'shoot': {
      const r = G.remotes.get(msg.id);
      if (r) r.onShoot(msg);
      break;
    }
    case 'ability':
      if (G.abilities) G.abilities.onAbility(msg.id, msg.kind, msg.data);
      break;
    case 'hp': onHp(msg); break;
    case 'death': onDeath(msg); break;
    case 'revive': onRevive(msg); break;
    case 'ultPts': G.me.ult = msg.pts; break;
    case 'credits':
      G.me.credits = msg.credits;
      G.hud.setCredits(msg.credits);
      break;
    case 'stun': {
      const cc = (G.me && G.me.char === 'fafik') ? 0.7 : 1;  // пассивка Фафика: контузия короче на 30%
      G.stunnedUntil = now() + (msg.dur || 1) * cc;
      G.shake = Math.max(G.shake, 2);
      G.hud.announce('', 'ОГЛУШЕНИЕ', 1.2);
      break;
    }
    case 'geraPull': {
      // «Воронка» Геры стягивает меня к центру конуса (частичный само-подтяг)
      const cur = G.player.pos;
      const to = new THREE.Vector3(cur.x + (msg.to[0] - cur.x) * 0.6, cur.y, cur.z + (msg.to[1] - cur.z) * 0.6);
      G.pulled = { from: cur.clone(), to, t: 0, dur: msg.dur || 0.9 };
      break;
    }
    case 'geraLevit':
      // «Невесомость» Геры: всплываю и вязну. Сервер шлёт маркер ~каждые 0.4с, пока я в куполе,
      // поэтому клиенту хватает короткого окна на каждое сообщение (в серверном времени msg.until смысла не имеет).
      G.levitUntil = now() + 0.5;   // слоу — в player.speedFactor по G.levitUntil
      if (G.player.grounded) { G.player.vel.y = 2.2; G.player.grounded = false; } // «потерял опору»
      G.shake = Math.max(G.shake, 1.0);
      break;
    case 'clonePopped':
      // клон лопнул у всех + шоквейв (стан приходит отдельным 'stun', если задело)
      if (G.abilities) G.abilities.popClone(msg.cloneId, msg.pos);
      break;
    case 'weaponDrop': {
      if (!G.pickupMarkers) G.pickupMarkers = new Map();
      const m = makePickupMarker(msg.pos, G.me && G.me.char === 'sova');  // Сова видит сквозь стены
      G.scene.add(m);
      G.pickupMarkers.set(msg.id, m);
      break;
    }
    case 'weaponPickup':
    case 'weaponGone':
      if (G.pickupMarkers && G.pickupMarkers.has(msg.id)) {
        G.scene.remove(G.pickupMarkers.get(msg.id));
        G.pickupMarkers.delete(msg.id);
      }
      break;
    case 'setWeapon': {
      const cur = (G.weapons && G.weapons.loadout) || { sidearm: 'classic' };
      G.weapons.setLoadout({ primary: msg.weapon, sidearm: cur.sidearm }, true);
      G.hud.announce('', 'ПОДОБРАНО: ' + ((WEAPONS[msg.weapon] || {}).name || msg.weapon), 1.6);
      try { G.sfx.buy(); } catch {}
      break;
    }
    case 'abilityFail':
      try { G.sfx.error(); } catch {}
      G.hud.announce('', msg.reason || 'НЕЛЬЗЯ', 1.4);
      break;
    case 'buyOk':
      G.me.credits = msg.credits;
      G.me.armor = msg.armor;
      G.hud.setCredits(msg.credits);
      G.hud.setArmor(msg.armor);
      G.weapons.setLoadout(msg.loadout, true);
      G.hud.refreshBuy();
      G.sfx.buy();
      break;
    case 'buyFail':
      G.sfx.error();
      G.hud.announce('', msg.reason.toUpperCase(), 1.5);
      break;
    case 'cocoon': {
      G.cocoonedId = msg.victim;
      G.abilities.makeCocoonRope(msg.victim, msg.by);
      G.sfx.hookHit();
      if (msg.victim === G.myId) {
        G.stunnedUntil = now() + msg.tLeft + 0.3;
        const denis = G.remotes.get(msg.by);
        G.pulled = { follow: () => (denis ? denis.pos : G.player.pos) };
        G.shake = 2;
        G.hud.announce('ТЕБЯ ТАЩИТ ДЕНИС!', 'СОЮЗНИКИ МОГУТ ОТСТРЕЛИТЬ КОКОН', msg.tLeft);
      } else {
        const info = G.players.get(msg.victim);
        if (info && info.team === G.myTeam) {
          G.hud.announce('', `${info.name} В КОКОНЕ — СТРЕЛЯЙ ПО КОКОНУ!`, 2.5);
        }
      }
      break;
    }
    case 'cocoonEnd': {
      G.cocoonedId = null;
      G.abilities.disposeCocoonRope();
      if (msg.victim === G.myId) {
        G.pulled = null;
        G.stunnedUntil = 0;
        if (msg.freed) G.hud.announce('СВОБОДЕН!', 'КОКОН УНИЧТОЖЕН', 2);
      }
      break;
    }
    case 'plantProg':
      if (msg.pct < 0) {
        G.hud.progress('', -1);
        if (G.holdAction === 'plant') G.holdAction = null;
      } else {
        G.hud.progress('УСТАНОВКА ШИПА', msg.pct);
        if (now() - (G._lastTickSnd || 0) > 0.25) { G._lastTickSnd = now(); G.sfx.plantTick(); }
      }
      break;
    case 'planted':
      G.phase = PHASES.PLANTED;
      G.deadline = now() + msg.tLeft;
      G.spikeCarrier = 0;
      G.spikePos = msg.pos;
      G.spikeFx = G.fx.spikeMesh(new THREE.Vector3(msg.pos[0], msg.pos[1] || 0, msg.pos[2]));
      G.hud.progress('', -1);
      G.holdAction = null;
      G.hud.announce('ШИП УСТАНОВЛЕН', G.side === 'defend' ? 'ОБЕЗВРЕДЬ (ДЕРЖИ F) ИЛИ ВСЁ ВЗОРВЁТСЯ' : 'ЗАЩИЩАЙ ШИП', 3);
      G.sfx.planted();
      break;
    case 'defuseProg':
      if (msg.pct < 0) {
        G.hud.progress('', -1);
        if (G.holdAction === 'defuse') G.holdAction = null;
      } else {
        G.hud.progress('ОБЕЗВРЕЖИВАНИЕ', msg.pct);
        // единый тик, слышно только рядом с шипом (чтобы можно было фейкать дефьюз)
        const near = G.spikePos && Math.hypot(G.player.pos.x - G.spikePos[0], G.player.pos.z - G.spikePos[2]) < 22;
        if (near && now() - (G._lastTickSnd || 0) > 0.28) { G._lastTickSnd = now(); G.sfx.defuseTick(); }
      }
      break;
    case 'spikeDrop': {
      G.spikeCarrier = 0;
      G.spikeDroppedPos = msg.pos;
      if (G.spikeDropFx) G.spikeDropFx.kill();
      G.spikeDropFx = G.fx.spikeMesh(new THREE.Vector3(msg.pos[0], msg.pos[1] || 0, msg.pos[2]), 'dropped');
      G.hud.announce('', G.side === 'attack' ? 'ШИП НА ЗЕМЛЕ — ПОДБЕРИ ЕГО!' : 'НОСИТЕЛЬ ШИПА УБИТ', 2.5);
      break;
    }
    case 'spikePick': {
      G.spikeCarrier = msg.id;
      G.spikeDroppedPos = null;
      if (G.spikeDropFx) { G.spikeDropFx.kill(); G.spikeDropFx = null; }
      if (msg.id === G.myId) G.hud.announce('', 'ШИП У ТЕБЯ — ДОНЕСИ И ПОСТАВЬ (4)', 2);
      G.sfx.buy();
      break;
    }
    case 'noSpike':
      G.sfx.error();
      G.hud.announce('', 'ШИП НЕ У ТЕБЯ', 1.5);
      break;
    case 'defuseBusy':
      G.sfx.error();
      G.hud.announce('', 'ШИП УЖЕ РАЗМИНИРУЮТ', 1.5);
      break;
    case 'defuseHalf':
      // намеренно тихо и без текста: половина фиксируется скрытно (фейки на слух)
      break;
    case 'defused':
      G.hud.progress('', -1);
      G.sfx.defused();
      if (G.spikeFx) { G.spikeFx.kill(); G.spikeFx = null; }
      break;
    case 'boom': {
      const p = new THREE.Vector3(msg.pos[0], 0.5, msg.pos[2]);
      G.fx.explosion(p);
      G.sfx.spatial([msg.pos[0], 0.5, msg.pos[2]], () => G.sfx.explosion());
      G.shake = 5;
      G.blindUntil = Math.max(G.blindUntil, now() + 0.5);
      G.blindStink = false;
      if (G.spikeFx) { G.spikeFx.kill(); G.spikeFx = null; }
      break;
    }
    case 'roundEnd': onRoundEnd(msg); break;
    case 'matchEnd': onMatchEnd(msg); break;
    case 'matchAbort':
      G.hud && G.hud.announce('', msg.reason.toUpperCase(), 2.5);
      break;
    case 'chat': {
      if (msg.id === 0) {
        G.hud && G.hud.chat('СЕРВЕР', msg.text, '#8b978f');
        break;
      }
      const info = G.players.get(msg.id);
      const mine = msg.id === G.myId;
      G.hud && G.hud.chat(info ? info.name : '?', msg.text, mine || (info && info.team === G.myTeam) ? '#0ac8b9' : '#ff4655');
      break;
    }
  }
}

function renderLobbySafe(msg) {
  // HUD может ещё не существовать (мир не создан) — рендерим лобби напрямую
  if (G.hud) {
    G.hud.renderLobby(msg, G.myId);
  } else {
    // создаём временный HUD-объект нельзя; используем минимальный рендер
    tempRenderLobby(msg);
  }
}

// минимальный рендер лобби до создания мира
let tempLobbyBound = false;
function tempRenderLobby(msg) {
  if (!tempLobbyBound) {
    tempLobbyBound = true;
    HUDLobbyBindOnce();
  }
  HUDLobbyRender(msg);
}
function HUDLobbyBindOnce() {
  $('btnAddBotA').addEventListener('click', () => lobbyHooks.addBot('A'));
  $('btnAddBotB').addEventListener('click', () => lobbyHooks.addBot('B'));
  $('btnDelBotA').addEventListener('click', () => lobbyHooks.delBot('A'));
  $('btnDelBotB').addEventListener('click', () => lobbyHooks.delBot('B'));
  $('btnSwitchTeam').addEventListener('click', () => lobbyHooks.switchTeam());
  $('btnStart').addEventListener('click', () => lobbyHooks.start());
  const mb = $('mapButtons');
  mb.innerHTML = '';
  for (const [id, m] of Object.entries(MAPS)) {
    const b = document.createElement('button');
    b.textContent = m.name.toUpperCase();
    b.dataset.map = id;
    b.title = m.desc;
    b.addEventListener('click', () => lobbyHooks.setMap(id));
    mb.appendChild(b);
  }
  const db = $('diffButtons');
  db.innerHTML = '';
  for (const id of Object.keys(BOT_PRESETS)) {
    const b = document.createElement('button');
    b.textContent = DIFF_NAMES[id] || id.toUpperCase();
    b.dataset.diff = id;
    b.addEventListener('click', () => lobbyHooks.setDifficulty(id));
    db.appendChild(b);
  }
  // #10/#12 клики по строкам ростера (делегирование)
  const onRosterClick = (e) => {
    const btn = e.target.closest('button[data-act]');
    if (!btn) return;
    const row = btn.closest('.roster-row');
    const id = Number(row.dataset.id);
    const p = (lastLobby.players || []).find(x => x.id === id);
    if (!p) return;
    const act = btn.dataset.act;
    if (act === 'agent') openAgentPicker();
    else if (act === 'move') lobbyHooks.movePlayer(id, p.team);
    else if (act === 'host') lobbyHooks.transferHost(id);
    else if (act === 'kick') lobbyHooks.kickBot(id);
  };
  $('teamARoster').addEventListener('click', onRosterClick);
  $('teamBRoster').addEventListener('click', onRosterClick);
  // выбор агента
  buildAgentPicker();
  $('apClose').addEventListener('click', () => $('agentPicker').classList.add('hidden'));
}
function buildAgentPicker() {
  const grid = $('apGrid');
  grid.innerHTML = '';
  for (const [id, c] of Object.entries(CHARACTERS)) {
    const card = document.createElement('div');
    card.className = 'ap-card';
    card.style.setProperty('--card-color', c.color);
    card.innerHTML = `<div class="ap-name" style="color:${c.color}">${c.name}</div><div class="ap-role">${c.title.toUpperCase()}</div><div class="ap-desc">${c.desc}</div>`;
    card.addEventListener('click', () => { lobbyHooks.changeAgent(id); $('agentPicker').classList.add('hidden'); });
    grid.appendChild(card);
  }
}
function openAgentPicker() {
  for (const card of $('apGrid').children) {
    const nm = card.querySelector('.ap-name').textContent;
    card.classList.toggle('sel', CHARACTERS[selChar] && CHARACTERS[selChar].name === nm);
  }
  $('agentPicker').classList.remove('hidden');
}
function HUDLobbyRender(data) {
  const myId = G.myId;
  const isHost = data.hostId === myId;
  $('lobbyOverlay').classList.toggle('hide-host', !isHost);
  $('mapRowGuest').classList.toggle('hidden', isHost);
  $('mapNameGuest').textContent = (MAPS[data.map] || {}).name || data.map;
  for (const b of $('mapButtons').children) b.classList.toggle('sel', b.dataset.map === data.map);
  const diff = data.difficulty || 'medium';
  $('diffRowGuest').classList.toggle('hidden', isHost);
  $('diffNameGuest').textContent = DIFF_NAMES[diff] || diff;
  for (const b of $('diffButtons').children) b.classList.toggle('sel', b.dataset.diff === diff);
  const render = (team, el) => {
    el.innerHTML = '';
    for (const p of data.players.filter(x => x.team === team)) {
      const row = document.createElement('div');
      row.className = 'roster-row' + (p.id === myId ? ' me' : '');
      row.dataset.id = p.id;
      const cfg = CHARACTERS[p.char] || { name: p.char, color: '#888' };
      const star = p.id === data.hostId ? '<span class="r-host">★</span>' : '';
      let acts = '';
      if (p.id === myId) acts += `<button data-act="agent" title="Сменить агента">⇄</button>`;
      if (isHost && p.id !== myId) acts += `<button data-act="move" title="В другую команду">⇆</button>`;
      if (isHost && p.id !== myId && !p.bot) acts += `<button data-act="host" title="Сделать хостом">★</button>`;
      if (isHost && p.bot) acts += `<button data-act="kick" title="Убрать бота">✕</button>`;
      row.innerHTML = `${star}${p.bot ? '🤖' : ''}<b class="r-name">${p.name.replace(/[<>&]/g, '')}</b>` +
        `<span class="r-char" style="color:${cfg.color}">${cfg.name.toUpperCase()}</span>` +
        `<span class="r-acts">${acts}</span>`;
      el.appendChild(row);
    }
  };
  render('A', $('teamARoster'));
  render('B', $('teamBRoster'));
  const a = data.players.filter(p => p.team === 'A').length;
  const b = data.players.filter(p => p.team === 'B').length;
  $('btnStart').disabled = !(a >= 1 && b >= 1) || data.inMatch;
  $('lobbyStatus').textContent = data.inMatch
    ? 'Матч идёт — дождись конца'
    : isHost ? 'Ты хост: собери команды, жми «Начать». Клик по агенту в строке — сменить перса' : 'Ждём хоста. Кликни свою строку, чтобы сменить агента';
  $('lobbyHint').textContent = isHost && (a < 1 || b < 1) ? 'В каждой команде нужен хотя бы один игрок или бот' : '';
}

function roleHint() {
  return G.side === 'attack' ? 'ТЫ АТАКУЕШЬ — УСТАНОВИ ШИП (4) НА САЙТЕ A ИЛИ B' : 'ТЫ ЗАЩИЩАЕШЬ — НЕ ДАЙ ПОСТАВИТЬ ШИП';
}

function onRoundStart(msg) {
  clearPickupMarkers();       // убрать маркеры брошенного оружия прошлого раунда
  G.phase = PHASES.BUY;
  G.freeze = true;
  G.round = msg.round;
  G.score = msg.score;
  G.deadline = now() + msg.buyTime;
  G.side = msg.sides[G.myTeam];
  G.holdAction = null; G.pulled = null; G.stunnedUntil = 0; G.blindUntil = 0;
  G.slowMul = 1; G.cocoonedId = null; G.xrayUntil = 0; G.banquetUntil = 0; G.boostUntil = 0;
  G.levitUntil = 0; G.trapSlowUntil = 0; G.gallopUntil = 0;
  G.spottedUntil.clear(); G.revealed.clear();
  G.spikePos = null;
  if (G.spikeFx) { G.spikeFx.kill(); G.spikeFx = null; }
  G.spikeCarrier = msg.spikeCarrier || 0;
  G.spikeDroppedPos = null;
  if (G.spikeDropFx) { G.spikeDropFx.kill(); G.spikeDropFx = null; }
  G.shootables = [];

  const st = msg.status[G.myId];
  G.me.hp = st.hp; G.me.maxHp = st.maxHp; G.me.armor = st.armor; G.me.ult = st.ult;
  G.me.credits = msg.credits[G.myId];
  G.me.alive = true;
  G.player.teleport(st.pos, st.yaw);

  for (const [pid, r] of G.remotes) {
    const s = msg.status[pid];
    if (s) r.resetRound(s.pos, s.yaw);
  }

  G.abilities.resetRound();
  G.weapons.setLoadout(st.loadout, true);
  G.weapons.vmRoot.visible = true;
  G.weapons.toggleScope(false);

  G.hud.setHp(G.me.hp, G.me.maxHp);
  G.hud.setArmor(G.me.armor);
  G.hud.setCredits(G.me.credits);
  G.hud.setScore(G.score[G.myTeam], G.score[G.myTeam === 'A' ? 'B' : 'A']);
  G.hud.setRound(G.round);
  G.hud.setRole(G.side === 'attack' ? '— АТАКА —' : '— ЗАЩИТА —');
  G.hud.progress('', -1);
  G.hud.announce(`РАУНД ${G.round}`, G.spikeCarrier === G.myId ? 'ШИП У ТЕБЯ — ДОНЕСИ И ПОСТАВЬ (4)' : roleHint(), 3);
  G.hud.openBuy();
}

function onHp(msg) {
  if (msg.id === G.myId) {
    const dropped = msg.hp < G.me.hp;
    G.me.hp = msg.hp;
    G.me.armor = msg.armor;
    G.hud.setHp(G.me.hp, G.me.maxHp);
    G.hud.setArmor(G.me.armor);
    if (dropped && msg.part !== 'heal') {
      G.hud.damage();
      G.sfx.hurt();
      G.tagUntil = now() + 0.45;   // пуля вязнет в ногах — «tagging», как в CS
    }
  } else {
    // чужая модель вздрагивает от попадания
    const r = G.remotes.get(msg.id);
    if (r && msg.part !== 'heal') r.flinch();
  }
}

function weaponLabel(w) {
  return WEAPONS[w] ? WEAPONS[w].name : (ABILITY_WEAPON_NAMES[w] || w);
}

function nameOf(id) {
  if (id === G.myId) return G.me.name;
  const info = G.players.get(id);
  return info ? info.name : '?';
}

function onDeath(msg) {
  const victimMe = msg.id === G.myId;
  if (G.stats[msg.id]) G.stats[msg.id].deaths++;
  if (G.stats[msg.by] && msg.by !== msg.id) G.stats[msg.by].kills++;

  const teamOfId = (id) => (id === G.myId ? G.myTeam : (G.players.get(id) || {}).team);
  const killerAlly = teamOfId(msg.by) === G.myTeam;
  const victimAlly = teamOfId(msg.id) === G.myTeam;
  G.hud.killfeed(nameOf(msg.by), killerAlly, weaponLabel(msg.weapon), nameOf(msg.id), victimAlly, msg.part === 'head', victimMe);
  G.abilities.onPlayerDeath(msg.id);

  if (victimMe) {
    G.me.alive = false;
    G.me.hp = 0;
    G.hud.setHp(0, G.me.maxHp);
    G.weapons.vmRoot.visible = false;
    G.weapons.toggleScope(false);
    G.holdAction = null;
    G.pulled = null;
    G.spectateTarget = 0;
    pickSpectate(1); // сразу начать наблюдать за живым союзником
    G.hud.announce('ВЫ ПОГИБЛИ', '', 2.5);
  } else {
    const r = G.remotes.get(msg.id);
    if (r) r.die();
    if (msg.by === G.myId) {
      G.sfx.kill();
      // ножи Макса обновляются за убийство
      if (G.knives) {
        G.knives.count = ABILITY.KNIVES_COUNT;
        G.knives.until = now() + ABILITY.KNIVES_TIME;
        G.weapons.updateHud();
      }
      // Твист Макса: рывок (C) обновляется за убийство
      if (G.abilities && G.me.char === 'max') {
        const maxC = CHARACTERS.max.abilities.C.charges || 2;
        G.abilities.charges.C = Math.min(maxC, (G.abilities.charges.C || 0) + 1);
      }
    }
  }
}

function onRevive(msg) {
  G.abilities.clearAll ? null : null;
  // маркеры ульты Артемия убираем
  for (const m of G.abilities.ultMarkers) m.fx.kill();
  G.abilities.ultMarkers = [];
  if (msg.id === G.myId) {
    G.me.alive = true;
    G.me.hp = msg.hp;
    G.player.teleport(msg.pos, msg.yaw);
    G.weapons.vmRoot.visible = true;
    G.hud.setHp(G.me.hp, G.me.maxHp);
    if (msg.src === 'banquet') G.hud.announce('ВОСКРЕШЕНИЕ', 'ИРА ПОДНЯЛА ТЕБЯ', 2);
    else G.hud.announce('ВТОРОЕ ДЫХАНИЕ', 'ТЫ ВЕРНУЛСЯ', 2);
  } else {
    const r = G.remotes.get(msg.id);
    if (r) { r.revive(msg.pos); }
  }
  G.fx.explosion(new THREE.Vector3(msg.pos[0], 0.5, msg.pos[2]));
  G.sfx.phoenixUlt();
}

const REASONS = {
  elim: 'Команда противника уничтожена',
  time: 'Время вышло',
  boom: 'Шип взорвался',
  defuse: 'Шип обезврежен',
};

function onRoundEnd(msg) {
  G.phase = PHASES.ROUND_END;
  G.freeze = true;
  G.score = msg.score;
  G.me.credits = msg.credits[G.myId];
  G.hud.setCredits(G.me.credits);
  G.hud.setScore(G.score[G.myTeam], G.score[G.myTeam === 'A' ? 'B' : 'A']);
  G.hud.progress('', -1);
  G.holdAction = null;
  const win = msg.winner === G.myTeam;
  G.hud.announce(win ? 'РАУНД ВЫИГРАН' : 'РАУНД ПРОИГРАН', (REASONS[msg.reason] || '').toUpperCase(), 4);
  win ? G.sfx.roundWin() : G.sfx.roundLose();
}

function onMatchEnd(msg) {
  G.phase = PHASES.MATCH_END;
  const win = msg.winner === G.myTeam;
  const lines = Object.values(msg.stats)
    .sort((a, b) => b.kills - a.kills)
    .map(s => `${s.team === G.myTeam ? '🟦' : '🟥'} ${s.name}: ${s.kills} / ${s.deaths}`)
    .join('<br>');
  G.hud.endScreen(win, `${msg.score[G.myTeam]} : ${msg.score[G.myTeam === 'A' ? 'B' : 'A']}`, lines);
  win ? G.sfx.matchWin() : G.sfx.matchLose();
}

// ===== Клавиши =====
function inSite(pos) {
  for (const s of Object.values(G.map.def.sites)) {
    if (Math.abs(pos.x - s.x) <= s.w / 2 && Math.abs(pos.z - s.z) <= s.d / 2) {
      if (s.yMin !== undefined && pos.y < s.yMin - 0.3) continue;
      return true;
    }
  }
  return false;
}

function relock() {
  if (!G.buyOpen && !G.chatOpen && G.phase !== PHASES.MATCH_END && G.renderer && !G.hud.mapTargetCb) {
    G.renderer.domElement.requestPointerLock();
  }
}
G.relock = relock;

function bindGameKeys() {
  window.addEventListener('keydown', (e) => {
    if (e.code === 'Tab') { e.preventDefault(); G.hud.scoreboard(true); return; }
    if (G.chatOpen) {
      if (e.code === 'Enter') {
        const text = $('chatInput').value.trim();
        if (text) G.net.send({ t: 'chat', text });
        $('chatInput').value = '';
        $('chatInput').classList.add('hidden');
        $('chatInput').blur();
        G.chatOpen = false;
        relock();
      } else if (e.code === 'Escape') {
        $('chatInput').classList.add('hidden');
        $('chatInput').blur();
        G.chatOpen = false;
      }
      return;
    }
    if (e.repeat) return;
    switch (e.code) {
      case 'Enter':
        if (G.phase === PHASES.WAIT) return;
        G.chatOpen = true;
        $('chatInput').classList.remove('hidden');
        $('chatInput').focus();
        break;
      case 'KeyB':
        if (G.phase === PHASES.BUY) {
          G.buyOpen ? (G.hud.closeBuy(), relock()) : G.hud.openBuy();
        }
        break;
      case 'Escape':
        if (G.buyOpen) { G.hud.closeBuy(); relock(); }
        if (G.hud.mapTargetCb) G.hud.endMapTarget();
        break;
      case 'KeyC': G.abilities && G.abilities.use('C'); break;
      case 'KeyQ': G.abilities && G.abilities.use('Q'); break;
      case 'KeyE': G.abilities && G.abilities.use('E'); break;
      case 'KeyX': G.abilities && G.abilities.use('X'); break;
      case 'KeyP': // тумблер пост-эффектов (bloom/грейд)
        if (G.post) { disablePost(); G.hud.announce('', 'ПОСТ-ЭФФЕКТЫ ВЫКЛ', 1.2); }
        else { enablePost(); G.hud.announce('', 'ПОСТ-ЭФФЕКТЫ ВКЛ', 1.2); }
        break;
      case 'KeyO': // тумблер SSAO (контактные тени в углах) — тяжёлый
        if (G.post && G.post.setSSAO) {
          G.ssaoOn = !G.post.ssaoOn();
          G.post.setSSAO(G.ssaoOn);
          G.hud.announce('', G.ssaoOn ? 'SSAO ВКЛ' : 'SSAO ВЫКЛ', 1.2);
        } else G.hud.announce('', 'SSAO НЕДОСТУПНО (включи пост — P)', 1.2);
        break;
      case 'Digit4':
        if (G.phase === PHASES.LIVE && G.side === 'attack' && G.me.alive && G.spikeCarrier !== G.myId) {
          G.sfx.error();
          G.hud.announce('', 'ШИП НЕ У ТЕБЯ', 1.2);
          break;
        }
        if (G.phase === PHASES.LIVE && G.side === 'attack' && G.me.alive && inSite(G.player.pos) && G.player.grounded) {
          G.holdAction = 'plant';
          G.net.send({ t: 'plantStart' });
        }
        break;
      case 'KeyF':
        if (G.phase === PHASES.PLANTED && G.side === 'defend' && G.me.alive && G.spikePos) {
          const d = Math.hypot(G.player.pos.x - G.spikePos[0], G.player.pos.z - G.spikePos[2]);
          if (d < 2.5) {
            G.holdAction = 'defuse';
            G.net.send({ t: 'defuseStart' });
          }
        }
        break;
    }
  });
  window.addEventListener('keyup', (e) => {
    if (e.code === 'Tab') { G.hud.scoreboard(false); return; }
    if (e.code === 'Digit4' && G.holdAction === 'plant') {
      G.holdAction = null;
      G.net.send({ t: 'plantCancel' });
    }
    if (e.code === 'KeyF' && G.holdAction === 'defuse') {
      G.holdAction = null;
      G.net.send({ t: 'defuseCancel' });
    }
  });

  $('pauseOverlay').addEventListener('click', () => {
    G.sfx.init();
    relock();
  });
  // клик по мёртвому — следующий союзник в спектаторе
  window.addEventListener('mousedown', (e) => {
    if (e.button === 0 && !G.me.alive && G.liveish() && document.pointerLockElement) pickSpectate(1);
  });
  document.addEventListener('pointerlockchange', () => {
    const locked = !!document.pointerLockElement;
    const lobbyShown = !$('lobbyOverlay').classList.contains('hidden');
    $('pauseOverlay').classList.toggle('hidden',
      locked || G.buyOpen || G.phase === PHASES.MATCH_END || G.chatOpen || !!G.hud.mapTargetCb || lobbyShown);
  });
}

// ===== Циклы =====
let lastFrame = 0, lastLos = 0, lastBeep = 0, lastAbHud = 0;
let perfT = 0, perfN = 0, perfChecked = false;

function disablePost() {
  if (G.post) { try { G.post.composer.dispose(); } catch {} G.post = null; }
}
function enablePost() {
  if (!G.post && G.renderer) {
    try { G.post = makeComposer(G.renderer, G.scene, G.camera); if (G.ssaoOn) G.post.setSSAO(true); } catch (e) { G.post = null; }
  }
}

function startLoops() {
  setInterval(() => {
    if (!G.worldReady || !G.net || G.phase === PHASES.WAIT) return;
    G.net.send({
      t: 'state',
      p: [+G.player.pos.x.toFixed(3), +G.player.pos.y.toFixed(3), +G.player.pos.z.toFixed(3)],
      yaw: +G.player.yaw.toFixed(3),
      pitch: +G.player.pitch.toFixed(3),
      crouch: G.player.crouch,
    });
  }, 50);

  requestAnimationFrame(frame);
}

function frame(tms) {
  requestAnimationFrame(frame);
  const t = tms / 1000;
  const dt = Math.min(0.05, t - lastFrame || 0.016);
  lastFrame = t;

  G.player.update(dt);
  G.weapons.update(dt);
  G.abilities.update(dt);
  for (const r of G.remotes.values()) r.update(dt);
  G.fx.update(dt);

  if (G.phase === PHASES.BUY || G.phase === PHASES.LIVE || G.phase === PHASES.PLANTED) {
    const remain = G.deadline - now();
    G.hud.setTimer(remain, remain < 12 || G.phase === PHASES.PLANTED);
  }

  if (G.phase === PHASES.PLANTED && G.spikeFx) {
    const remain = Math.max(0, G.deadline - now());
    const rate = Math.max(0.13, remain / 45);
    G.spikeFx.blinkRate = rate;
    if (now() - lastBeep > rate) {
      lastBeep = now();
      const d = G.spikePos ? Math.hypot(G.player.pos.x - G.spikePos[0], G.player.pos.z - G.spikePos[2]) : 99;
      if (d < 45) G.sfx.spikeBeep(remain < 10);
    }
  }

  // кто из врагов виден (миникарта)
  if (t - lastLos > 0.25 && G.me.alive) {
    lastLos = t;
    const eye = G.player.eyePos();
    for (const [pid, r] of G.remotes) {
      const info = G.players.get(pid);
      if (!info || info.team === G.myTeam || !r.alive) continue;
      const target = r.eyePos();
      if (eye.distanceTo(target) < 60 && G.abilities.losClear(eye, target)) {
        G.spottedUntil.set(pid, now() + 0.8);
      }
    }
  }

  if (G.phase === PHASES.LIVE && G.side === 'attack' && G.me.alive) {
    if (G.spikeCarrier === G.myId) {
      G.hud.setRole(inSite(G.player.pos) ? '⯁ ТЫ НА САЙТЕ — ДЕРЖИ [4], ЧТОБЫ ПОСТАВИТЬ ШИП' : '— АТАКА — ШИП У ТЕБЯ');
    } else if (G.spikeDroppedPos) {
      G.hud.setRole('— АТАКА — ШИП НА ЗЕМЛЕ, ПОДБЕРИ!');
    } else {
      G.hud.setRole('— АТАКА — шип у ' + nameOf(G.spikeCarrier));
    }
  }

  if (t - lastAbHud > 0.2) {
    lastAbHud = t;
    G.hud.updateAbilities(G.abilities.hudState());
  }

  // #17 спектатор после смерти — камера следит за живым союзником
  if (!G.me.alive && G.liveish()) updateSpectator();
  else $('specHint').classList.add('hidden');

  G.sfx.setListener(G.camera); // 3D-звук: слушатель = камера

  // авто-фолбэк постпроцессинга на слабых GPU (первые ~2.5 сек геймплея)
  if (G.post && !perfChecked && G.phase !== PHASES.WAIT) {
    perfT += dt; perfN++;
    if (perfT > 2.5) {
      perfChecked = true;
      // авто-снижение графики ради FPS: сначала выключаем пост, при совсем слабом — ещё и pixelRatio до 1
      const fps = perfN / perfT;
      if (fps < 50) {
        disablePost();
        try {
          if (fps < 40) { G.renderer.setPixelRatio(1); G.renderer.setSize(innerWidth, innerHeight); } // главный рычаг FPS
        } catch {}
        G.hud.announce('', `ГРАФИКА СНИЖЕНА ДЛЯ FPS (~${Math.round(fps)}) · P — вернуть пост`, 3.5);
      }
    }
  }

  G.hud.frame();
  if (G.post) G.post.render(dt);
  else G.renderer.render(G.scene, G.camera);
}

// ===== Спектатор (#17) =====
function livingAllies() {
  return [...G.remotes.entries()]
    .filter(([pid, r]) => r.alive && (G.players.get(pid) || {}).team === G.myTeam)
    .map(([pid]) => pid);
}
function pickSpectate(dir) {
  const allies = livingAllies();
  if (!allies.length) { G.spectateTarget = 0; return; }
  let idx = allies.indexOf(G.spectateTarget);
  G.spectateTarget = allies[(idx + (dir || 1) + allies.length) % allies.length];
}
function updateSpectator() {
  const info = G.players.get(G.spectateTarget);
  let r = G.remotes.get(G.spectateTarget);
  if (!r || !r.alive || !info || info.team !== G.myTeam) { pickSpectate(1); r = G.remotes.get(G.spectateTarget); }
  const hint = $('specHint');
  if (!r) { hint.textContent = 'ОЖИДАНИЕ КОНЦА РАУНДА…'; hint.classList.remove('hidden'); return; }
  const yaw = r.group.rotation.y;
  const fwd = new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw));
  const eye = r.pos.clone().add(new THREE.Vector3(0, 1.75, 0));
  G.camera.position.copy(eye).addScaledVector(fwd, -2.4).add(new THREE.Vector3(0, 0.55, 0));
  G.camera.lookAt(eye.clone().addScaledVector(fwd, 5));
  if (G.camera.fov !== 74) { G.camera.fov = 74; G.camera.updateProjectionMatrix(); }
  const nm = (G.players.get(G.spectateTarget) || {}).name || '';
  hint.textContent = '👁 СЛЕЖУ ЗА: ' + nm + '  ·  клик — следующий';
  hint.classList.remove('hidden');
}
