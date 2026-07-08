// Способности v2 — пять агентов:
// Артемий (огонь), Денис (вонь + крюк-кокон), Вова (дымы + орбиталка),
// Макс (мобильность + ножи), Санёк (турель, сигналка, кислота, рентген).
// Паттерн: use() шлёт ability на сервер, сервер рассылает ВСЕМ (и валидирует ульты),
// эффекты применяются в onAbility — все клиенты видят одно и то же.
import * as THREE from './three.module.js';
import { ABILITY, CHARACTERS } from './shared.js';
import { buildHumanoid } from './remote.js';

const now = () => performance.now() / 1000;

export class Abilities {
  constructor(G) {
    this.G = G;
    this.char = G.me.char;
    this.charges = {};
    this.zones = [];        // {type:'fire'|'wall'|'acid'|'puddle'|'orbital', owner, until, from?, pos?/r?, a?/b?, fx?}
    this.smokes = [];       // {pos:Vector3, r, until} — для LOS
    this.orbs = [];         // летящие вспышки {pos, vel, curve, born, owner, mesh, stink}
    this.mollies = [];      // летящие снаряды {pos, vel, owner, mesh, kind:'molly'|'puddle'|'acid'}
    this.hook = null;       // крюк-ульта Дениса {owner, pos, dir, traveled, state, mesh, rope, until}
    this.cocoonRope = null; // верёвка кокона {line, victim, by}
    this.turrets = new Map(); // ownerId -> {fx, pos, hp, nextShot}
    this.traps = [];        // {owner, pos, fx, used}
    this.ultMarkers = [];
    // Ира
    this.scouts = [];       // {owner, pos, dir, fx, born, detected:Set}
    this.buffets = [];      // {owner, pos, vel, mesh}
    this.buffetPickups = [];// {owner, pos, mesh}
    this.crispyWalls = [];  // {owner, a, b, fx, until}
    this.buffetReloadUsed = false;
    // Фафик
    this.cloneSets = new Map(); // ownerId -> {clones:[{h,pos,target,phase}], born}
    this.decoys = [];       // {owner, h, pos, dir?, kind:'stand'|'run', until, phase, traveled}
    this.swapDecoy = null;  // активный клон для рокировки (только у владельца)
    this.cloneById = new Map(); // cloneId -> {h, owner} — клоны для отстрела/стана
    this._cloneSeq = 0;         // общий счётчик (синхронен у всех: одинаковый порядок ability-сообщений)
    // Денис
    this.scents = [];       // {owner, pos, mesh, until} — приманки «нюх мясника»
    this.accum = { dmg: {}, heal: 0, t: 0 }; // dmg по причинам {cause: {amt, by}}
    this.ray = new THREE.Raycaster();
    this.resetRound();
  }

  chargesFor(char) {
    const c = {};
    for (const [k, a] of Object.entries(CHARACTERS[char].abilities)) c[k] = a.charges || 0;
    return c;
  }

  resetRound() {
    this.charges = this.chargesFor(this.char);
    this.clearAll();
  }

  clearAll() {
    const G = this.G;
    for (const z of this.zones) z.fx && z.fx.kill && z.fx.kill();
    this.zones = [];
    this.smokes = [];
    for (const o of this.orbs) G.scene.remove(o.mesh);
    this.orbs = [];
    for (const m of this.mollies) G.scene.remove(m.mesh);
    this.mollies = [];
    this.disposeHook();
    this.disposeCocoonRope();
    for (const t of this.turrets.values()) t.fx.kill();
    this.turrets.clear();
    for (const t of this.traps) t.fx.kill();
    this.traps = [];
    for (const m of this.ultMarkers) m.fx.kill();
    this.ultMarkers = [];
    // Ира
    for (const s of this.scouts) s.fx.kill();
    this.scouts = [];
    for (const b of this.buffets) G.scene.remove(b.mesh);
    this.buffets = [];
    for (const p of this.buffetPickups) G.scene.remove(p.mesh);
    this.buffetPickups = [];
    for (const w of this.crispyWalls) w.fx.kill();
    this.crispyWalls = [];
    this.buffetReloadUsed = false;
    for (const set of this.cloneSets.values()) for (const c of set.clones) G.scene.remove(c.h.group);
    this.cloneSets.clear();
    for (const d of this.decoys) G.scene.remove(d.h.group);
    this.decoys = []; this.swapDecoy = null;
    if (this.cloneById) this.cloneById.clear();
    for (const sc of this.scents) G.scene.remove(sc.mesh);
    this.scents = [];
    G.cloneMode = false;
    G.gallopUntil = 0;
    if (G.clonedIds) G.clonedIds.clear();
    if (G.banquets) for (const bq of G.banquets) bq.fx && bq.fx.kill();
    G.banquets = [];
    G.slowMul = 1;
    G.boostUntil = 0;
    G.xrayUntil = 0;
    G.cocoonedId = null;
    if (G.knives && G.weapons) G.weapons.endKnives();
    this.accum = { dmg: {}, heal: 0, t: 0 };
  }

  canUse() {
    const G = this.G;
    return G.me.alive && !G.freeze && !G.pulled && now() > G.stunnedUntil && !G.chatOpen && !G.buyOpen;
  }

  lookDir() {
    const d = new THREE.Vector3();
    this.G.camera.getWorldDirection(d);
    return d;
  }

  // точка на земле по направлению взгляда (до 22 м) — для дымов/кислоты Дениса и Санька
  groundPoint(maxDist = 22) {
    const G = this.G;
    const eye = G.player.eyePos();
    const dir = this.lookDir();
    this.ray.set(eye, dir);
    this.ray.far = maxDist;
    const hits = this.ray.intersectObjects(G.map.solids, false);
    const p = hits[0] ? hits[0].point.clone() : eye.clone().addScaledVector(dir, maxDist);
    p.y = Math.max(0, p.y);
    return p;
  }

  ultReady() {
    return this.G.me.ult >= CHARACTERS[this.char].ultCost;
  }

  // ===== ввод =====
  use(key) {
    if (!this.canUse()) return;
    const G = this.G;
    const eye = G.player.eyePos();
    const dir = this.lookDir();
    const send = (kind, data) => G.net.send({ t: 'ability', kind, data: data || {} });

    switch (this.char) {
      case 'artemiy':
        if (key === 'C' && this.charges.C > 0) send('flash', { from: eye.toArray(), dir: dir.toArray(), curve: true });
        else if (key === 'Q' && this.charges.Q > 0) send('molly', { from: eye.toArray(), dir: dir.toArray() });
        else if (key === 'E' && this.charges.E > 0) send('wall', { from: [G.player.pos.x, 0, G.player.pos.z], yaw: G.player.yaw });
        else if (key === 'X') {
          if (this.ultReady()) send('ultMark', { pos: [G.player.pos.x, G.player.pos.y, G.player.pos.z], yaw: G.player.yaw });
          else G.sfx.error();
        }
        break;

      case 'denis':
        if (key === 'C' && this.charges.C > 0) send('bloodfeast', {});
        else if (key === 'Q' && this.charges.Q > 0) { const p = this.groundPoint(16); send('scent', { pos: [p.x, 0, p.z] }); }
        else if (key === 'E' && this.charges.E > 0) {
          const p = this.groundPoint();
          send('smokes', { positions: [[p.x, p.y, p.z]], stink: true });
        } else if (key === 'X') {
          if (this.ultReady()) send('hookFire', { from: eye.toArray(), dir: dir.toArray() });
          else G.sfx.error();
        }
        break;

      case 'vova':
        if (key === 'C' && this.charges.C > 0) {
          G.hud.mapTarget('ДЫМ: КЛИКНИ ПО КАРТЕ', (x, z) => send('smokes', { positions: [[x, 0, z]], stink: false }));
        } else if (key === 'Q' && this.charges.Q > 0) send('flash', { from: eye.toArray(), dir: dir.toArray() });
        else if (key === 'E' && this.charges.E > 0) {
          const c = eye.clone().addScaledVector(dir.clone().setY(0).normalize(), 7);
          const perp = new THREE.Vector3(-dir.z, 0, dir.x).normalize();
          const g = ABILITY.SMOKE_WALL_GAP;
          send('smokes', {
            positions: [-g, 0, g].map(o => {
              const p = c.clone().addScaledVector(perp, o);
              return [p.x, 0, p.z];
            }),
            stink: false,
          });
        } else if (key === 'X') {
          if (this.ultReady()) G.hud.mapTarget('ОРБИТАЛЬНЫЙ УДАР: КЛИКНИ ПО КАРТЕ', (x, z) => send('orbital', { pos: [x, 0, z] }));
          else G.sfx.error();
        }
        break;

      case 'max':
        if (key === 'C' && this.charges.C > 0) { send('dash', {}); }
        else if (key === 'Q' && this.charges.Q > 0 && G.player.grounded) { send('launch', {}); }
        else if (key === 'E' && this.charges.E > 0) { send('boost', {}); }
        else if (key === 'X') {
          if (this.ultReady()) send('knives', {});
          else G.sfx.error();
        }
        break;

      case 'sanek':
        if (key === 'C' && this.charges.C > 0) send('trap', { pos: [G.player.pos.x, 0, G.player.pos.z] });
        else if (key === 'Q' && this.charges.Q > 0) {
          const p = this.groundPoint(6);
          send('turret', { pos: [p.x, p.y, p.z] });
        } else if (key === 'E' && this.charges.E > 0) send('throwZone', { from: eye.toArray(), dir: dir.toArray(), kind: 'acid' });
        else if (key === 'X') {
          if (this.ultReady()) send('xray', {});
          else G.sfx.error();
        }
        break;

      case 'fafik': {
        const flatF = new THREE.Vector3(dir.x, 0, dir.z).normalize();
        if (key === 'C' && this.charges.C > 0) send('flash', { from: eye.toArray(), dir: dir.toArray(), tapok: true });
        else if (key === 'Q' && this.charges.Q > 0) {
          // Двойник: рывок вперёд, на месте — клон-приманка
          send('twin', { from: [G.player.pos.x, 0, G.player.pos.z], dir: [flatF.x, flatF.z], yaw: G.player.yaw });
        } else if (key === 'E') {
          if (this.swapDecoy) { send('swapDo', {}); }       // рокировка с уже запущенным клоном
          else if (this.charges.E > 0) send('swapCast', { from: [G.player.pos.x, 0, G.player.pos.z], dir: [flatF.x, flatF.z], yaw: G.player.yaw });
        } else if (key === 'X') {
          if (G.cloneMode) { G.net.send({ t: 'ability', kind: 'fafikDeClone', data: {} }); }
          else if (this.ultReady()) {
            G.hud.mapTarget('КЛОНЫ БАТИ: КУДА БЕГУТ? КЛИКНИ ПО КАРТЕ', (x, z) =>
              send('fafikClones', { from: [G.player.pos.x, 0, G.player.pos.z], to: [x, z] }));
          } else G.sfx.error();
        }
        break;
      }

      case 'koniliy': {
        const flat0 = new THREE.Vector3(dir.x, 0, dir.z).normalize();
        if (key === 'C' && this.charges.C > 0) send('throwZone', { from: eye.toArray(), dir: dir.toArray(), kind: 'horseshoe' });
        else if (key === 'Q' && this.charges.Q > 0) send('neigh', { from: eye.toArray(), dir: dir.toArray() });
        else if (key === 'E' && this.charges.E > 0) send('gallop', {});
        else if (key === 'X') {
          if (this.ultReady()) {
            G.hud.mapTarget('ТАБУН: НАПРАВЛЕНИЕ — КЛИКНИ ПО КАРТЕ', (x, z) =>
              send('stampede', { from: [G.player.pos.x, 0, G.player.pos.z], to: [x, z] }));
          } else G.sfx.error();
        }
        break;
      }

      case 'ira': {
        const flat = new THREE.Vector3(dir.x, 0, dir.z).normalize();
        if (key === 'C' && this.charges.C > 0) {
          send('scout', { from: [G.player.pos.x, 0, G.player.pos.z], dir: [flat.x, flat.z] });
        } else if (key === 'Q' && this.charges.Q > 0) {
          const base = new THREE.Vector3(G.player.pos.x, 0, G.player.pos.z);
          const perp = new THREE.Vector3(-flat.z, 0, flat.x);
          const c = base.addScaledVector(flat, 2.2);
          const a = c.clone().addScaledVector(perp, -ABILITY.CRISPY_LEN / 2);
          const b = c.clone().addScaledVector(perp, ABILITY.CRISPY_LEN / 2);
          send('crispy', { a: a.toArray(), b: b.toArray() });
          G.net.send({ t: 'healZone', kind: 'crispy', a: a.toArray(), b: b.toArray(), dur: ABILITY.CRISPY_TIME });
        } else if (key === 'E' && this.charges.E > 0) {
          send('buffet', { from: eye.toArray(), dir: dir.toArray() });
        } else if (key === 'X') {
          if (this.ultReady()) {
            const p = this.groundPoint(9);
            send('banquet', { pos: [p.x, 0, p.z] });
            G.net.send({ t: 'healZone', kind: 'banquet', pos: [p.x, 0, p.z], r: ABILITY.BANQUET_R, dur: ABILITY.BANQUET_TIME });
          } else G.sfx.error();
        }
        break;
      }

      case 'sova': {
        const eyeA = eye.toArray();
        // groundPoint рейкастит по стенам → стрела втыкается В СТЕНУ, а не сквозь неё
        if (key === 'C' && this.charges.C > 0) { const p = this.groundPoint(30); send('sovaShock', { from: eyeA, to: [p.x, p.y, p.z] }); }
        else if (key === 'Q' && this.charges.Q > 0) { const p = this.groundPoint(35); send('sovaMark', { from: eyeA, to: [p.x, p.y, p.z] }); }
        else if (key === 'E' && this.charges.E > 0) { const p = this.groundPoint(30); send('sovaDrone', { from: eyeA, to: [p.x, p.y, p.z] }); }
        else if (key === 'X') {
          if (this.ultReady()) send('sovaFury', { from: eyeA, dir: dir.toArray() });
          else G.sfx.error();
        }
        break;
      }

      case 'gera': {
        const flat = new THREE.Vector3(dir.x, 0, dir.z).normalize();
        if (key === 'C' && this.charges.C > 0) {
          const p = this.groundPoint(22);   // «Развеятель» — по точке прицела
          send('geraDispel', { pos: [p.x, p.y, p.z] });
        } else if (key === 'Q' && this.charges.Q > 0) {
          // грэпл: рейкаст к твёрдой поверхности, подтягиваемся туда (в т.ч. на уступ)
          this.ray.set(eye, dir); this.ray.far = ABILITY.GERA_GRAPPLE_RANGE;
          const hits = this.ray.intersectObjects(G.map.solids, false);
          if (hits[0]) {
            const to = hits[0].point.clone().addScaledVector(dir, -0.8);   // встать чуть НЕ доходя
            to.y = Math.max(0, hits[0].point.y);                            // на высоту уступа
            send('geraGrapple', { from: eye.toArray(), to: [to.x, to.y, to.z] });
          } else G.sfx.error();
        } else if (key === 'E' && this.charges.E > 0) {
          send('geraVortex', { from: [G.player.pos.x, 0, G.player.pos.z], dir: [flat.x, 0, flat.z] });
        } else if (key === 'X') {
          if (this.ultReady()) { const p = this.groundPoint(9); send('geraUlt', { pos: [p.x, 0, p.z] }); }
          else G.sfx.error();
        }
        break;
      }
    }
  }

  // ===== эхо сервера =====
  onAbility(id, kind, data) {
    const G = this.G;
    const mine = id === G.myId;
    const zk = data && data.kind;
    const keyByKind = {
      flash: this.char === 'vova' ? 'Q' : 'C', molly: 'Q', wall: 'E',
      throwZone: zk === 'acid' ? 'E' : zk === 'horseshoe' ? 'C' : zk === 'mangal' ? 'E' : 'Q',
      smokes: this.char === 'vova' ? (data && data.positions && data.positions.length > 1 ? 'E' : 'C') : this.char === 'fafik' ? 'Q' : 'E',
      dash: 'C', launch: 'Q', boost: 'E', trap: 'C', turret: 'Q',
      scout: 'C', crispy: 'Q', buffet: 'E', neigh: 'Q', gallop: 'E',
      bloodfeast: 'C', scent: 'Q', twin: 'Q', swapCast: 'E',
      sovaShock: 'C', sovaMark: 'Q', sovaDrone: 'E',
      geraDispel: 'C', geraGrapple: 'Q', geraVortex: 'E',
    };
    if (mine && keyByKind[kind] && this.charges[keyByKind[kind]] > 0) this.charges[keyByKind[kind]]--;

    switch (kind) {
      case 'flash': case 'neigh': {
        const orbColor = data.tapok ? 0x9a7a4a : kind === 'neigh' ? 0xcdb88a : data.stink ? 0xa8d060 : 0xfff0c0;
        const mesh = G.fx.glowOrb(orbColor, 0.35);
        const pos = new THREE.Vector3(...data.from);
        const dir = new THREE.Vector3(...data.dir);
        mesh.position.copy(pos);
        const curve = data.curve
          ? new THREE.Vector3().crossVectors(dir, new THREE.Vector3(0, 1, 0)).normalize().multiplyScalar(10)
          : new THREE.Vector3();
        this.orbs.push({ pos, vel: dir.multiplyScalar(ABILITY.FLASH_SPEED * (data.curve ? 1 : 1.4)), curve, born: now(), owner: id, mesh, stink: !!data.stink });
        if (kind === 'neigh') G.sfx.neigh(this.volTo(pos)); else G.sfx.flashThrow();
        break;
      }
      case 'molly': case 'throwZone': {
        const zoneKind = kind === 'molly' ? 'fire' : data.kind; // puddle|acid|mangal|horseshoe
        const orbCol = { fire: 0xff7722, mangal: 0xff8844, acid: 0xd6e84d, horseshoe: 0xc9c2b0, puddle: 0x8fae4a }[zoneKind] || 0x8fae4a;
        const mesh = G.fx.glowOrb(orbCol, 0.4);
        const pos = new THREE.Vector3(...data.from);
        mesh.position.copy(pos);
        const vel = new THREE.Vector3(...data.dir).multiplyScalar(15);
        vel.y += 3;
        this.mollies.push({ pos, vel, owner: id, mesh, kind: zoneKind });
        G.sfx.flashThrow();
        break;
      }
      case 'wall': {
        const from = new THREE.Vector3(data.from[0], 0, data.from[2]);
        const fwd = new THREE.Vector3(-Math.sin(data.yaw), 0, -Math.cos(data.yaw));
        const a = from.clone().addScaledVector(fwd, 1.5);
        const b = from.clone().addScaledVector(fwd, 1.5 + ABILITY.WALL_LEN);
        const fx = G.fx.fireWallFx(a, b);
        this.zones.push({ type: 'wall', owner: id, until: now() + ABILITY.WALL_TIME, a, b, fx });
        if (mine) G.net.send({ t: 'zone', ztype: 'firewall', a: a.toArray(), b: b.toArray(), dur: ABILITY.WALL_TIME });
        G.sfx.fireIgnite(this.volTo(a));
        break;
      }
      case 'smokes': {
        const ownerTeam = (G.players.get(id) || {}).team;
        const geraSees = this.char === 'gera' && ownerTeam && ownerTeam !== G.myTeam; // пассивка «Ясный глаз»: вражеский дым полупрозрачен
        for (const p of data.positions || []) {
          const pos = new THREE.Vector3(p[0], p[1] || 0, p[2]);
          const fx = G.fx.smoke(pos, ABILITY.SMOKE_R, ABILITY.SMOKE_TIME, data.stink, geraSees ? 0.2 : 1);
          this.smokes.push({ pos: pos.clone().setY((p[1] || 0) + ABILITY.SMOKE_R * 0.55), r: ABILITY.SMOKE_R, until: now() + ABILITY.SMOKE_TIME, fx, team: ownerTeam });
        }
        G.sfx.smokePop(data.stink);
        break;
      }
      case 'ultMark': {
        const pos = new THREE.Vector3(data.pos[0], 0, data.pos[2]);
        const fx = G.fx.ultMarkerFx(pos);
        this.ultMarkers.push({ fx, until: now() + ABILITY.PHOENIX_ULT_TIME, pos });
        G.sfx.phoenixUlt();
        if (mine) G.hud.announce('', 'ВТОРОЕ ДЫХАНИЕ АКТИВНО — 10 СЕК', 2);
        break;
      }
      case 'orbital': {
        const pos = new THREE.Vector3(data.pos[0], 0, data.pos[2]);
        G.fx.orbital(pos, ABILITY.ORBITAL_DELAY, ABILITY.ORBITAL_DUR, ABILITY.ORBITAL_R);
        this.zones.push({
          type: 'orbital', owner: id, pos, r: ABILITY.ORBITAL_R,
          from: now() + ABILITY.ORBITAL_DELAY, until: now() + ABILITY.ORBITAL_DELAY + ABILITY.ORBITAL_DUR,
        });
        G.sfx.orbitalWarn();
        G.hud.announce('', mine ? 'УДАР ВЫЗВАН' : 'ОРБИТАЛЬНЫЙ УДАР!', 1.5);
        break;
      }
      case 'hookFire': {
        this.disposeHook();
        const pos = new THREE.Vector3(...data.from);
        const dir = new THREE.Vector3(...data.dir);
        const mesh = new THREE.Mesh(
          new THREE.ConeGeometry(0.14, 0.4, 6),
          new THREE.MeshLambertMaterial({ color: '#8a8f98' })
        );
        mesh.position.copy(pos);
        G.scene.add(mesh);
        const ropeGeo = new THREE.BufferGeometry().setFromPoints([pos.clone(), pos.clone()]);
        const rope = new THREE.Line(ropeGeo, new THREE.LineBasicMaterial({ color: 0x333333 }));
        G.scene.add(rope);
        this.hook = { owner: id, pos, dir, traveled: 0, state: 'fly', mesh, rope, until: now() + 3 };
        G.sfx.hookThrow();
        break;
      }
      case 'dash': {
        if (mine) G.player.dash(ABILITY.DASH_DIST);
        else {
          const r = G.remotes.get(id);
          if (r) G.fx.burst(r.pos.clone().add(new THREE.Vector3(0, 1, 0)), { n: 10, color: 0x9fdcf0, speed: 3, life: 0.3, size: 0.15 });
        }
        G.sfx.dash(mine ? 1 : 0.4);
        break;
      }
      case 'launch': {
        if (mine) G.player.launch(ABILITY.LAUNCH_V);
        G.sfx.dash(mine ? 0.8 : 0.3);
        break;
      }
      case 'boost': {
        if (mine) {
          G.boostUntil = now() + ABILITY.BOOST_TIME;
          G.hud.announce('', 'ПОРЫВ: +40% СКОРОСТИ', 1.5);
        }
        G.sfx.dash(0.5);
        break;
      }
      case 'knives': {
        if (mine) G.weapons.startKnives();
        G.sfx.knivesUlt();
        break;
      }
      case 'trap': {
        const pos = new THREE.Vector3(data.pos[0], 0, data.pos[2]);
        // врагам сигналку не показываем
        const myTrap = G.players.get(id) && G.players.get(id).team === G.myTeam;
        const fx = myTrap ? G.fx.trap(pos) : { kill: () => {} };
        this.traps.push({ owner: id, pos, fx, used: false });
        if (mine) G.sfx.click();
        break;
      }
      case 'trapTrig': {
        const victimIsMe = data.target === G.myId;
        const ownerAlly = G.players.get(id) && G.players.get(id).team === G.myTeam;
        if (ownerAlly && !victimIsMe) {
          const r = G.remotes.get(data.target);
          if (r) r.revealedUntil = now() + ABILITY.TRAP_REVEAL;
          G.revealed.set(data.target, now() + ABILITY.TRAP_REVEAL);
        }
        if (victimIsMe) G.hud.announce('', 'ВАС ЗАСЕКЛА СИГНАЛКА!', 1.5);
        G.sfx.trapPing();
        break;
      }
      case 'turret': {
        const pos = new THREE.Vector3(data.pos[0], data.pos[1] || 0, data.pos[2]);
        const fx = G.fx.turret(pos);
        // регистрируем как расстреливаемый объект
        fx.group.traverse(m => { if (m.isMesh) m.userData.shootId = 'turret:' + id; });
        G.shootables.push({ mesh: fx.group.children[0], shootId: 'turret:' + id });
        G.shootables.push({ mesh: fx.group.children[1], shootId: 'turret:' + id });
        this.turrets.set(id, { fx, pos, hp: ABILITY.TURRET_HP, nextShot: 0 });
        G.sfx.turretPlace();
        break;
      }
      case 'turretShot': {
        const t = this.turrets.get(id);
        if (t) {
          G.fx.tracer(t.pos.clone().add(new THREE.Vector3(0, 0.5, 0)), new THREE.Vector3(...data.to), 0xffe48a);
          G.sfx.turretShot(this.volTo(t.pos));
        }
        break;
      }
      case 'turretDmg': {
        // урон по турели применяет её владелец
        if (data.owner === G.myId) {
          const t = this.turrets.get(G.myId);
          if (t) {
            t.hp -= data.dmg;
            if (t.hp <= 0) G.net.send({ t: 'ability', kind: 'turretDead', data: { owner: G.myId } });
          }
        }
        break;
      }
      case 'turretDead': {
        this.removeTurret(data.owner);
        break;
      }
      case 'xray': {
        const ownerAlly = G.players.get(id) && G.players.get(id).team === G.myTeam;
        if (ownerAlly) {
          G.xrayUntil = now() + ABILITY.XRAY_TIME;
          G.hud.announce('', 'РЕНТГЕН: ВРАГИ ПОДСВЕЧЕНЫ', 2);
        } else {
          G.hud.announce('', 'ВАС ПРОСВЕЧИВАЮТ НАСКВОЗЬ!', 2);
        }
        G.sfx.xray();
        break;
      }
      case 'cocoonHit': break; // сервер сам разошлёт t:'cocoon'

      // ===== Ира =====
      case 'scout': {
        const from = new THREE.Vector3(data.from[0], 0.25, data.from[2]);
        const dir = new THREE.Vector3(data.dir[0], 0, data.dir[1]).normalize();
        const fx = G.fx.chickenScout();
        fx.group.position.copy(from);
        this.scouts.push({ owner: id, pos: from.clone(), dir, fx, born: now(), detected: new Set() });
        G.sfx.chickenSpawn();
        break;
      }
      case 'crispy': {
        const a = new THREE.Vector3(...data.a);
        const b = new THREE.Vector3(...data.b);
        const fx = G.fx.crispyWall(a, b, 2.6);
        this.crispyWalls.push({ owner: id, a, b, fx, until: now() + ABILITY.CRISPY_TIME });
        G.sfx.crispyPlace(this.volTo(a));
        break;
      }
      case 'buffet': {
        const mesh = new THREE.Mesh(
          new THREE.CylinderGeometry(0.16, 0.13, 0.28, 12),
          new THREE.MeshStandardMaterial({ color: 0xe8302c, roughness: 0.6 })
        );
        const pos = new THREE.Vector3(...data.from);
        mesh.position.copy(pos);
        G.scene.add(mesh);
        const vel = new THREE.Vector3(...data.dir).multiplyScalar(14);
        vel.y += 3.5;
        this.buffets.push({ owner: id, pos, vel, mesh });
        G.sfx.throwLight();
        break;
      }
      case 'buffetPop': {
        const pos = new THREE.Vector3(data.pos[0], data.pos[1] || 0, data.pos[2]);
        G.fx.steam(() => pos, ABILITY.BUFFET_R * 0.5, 3, 0xffe8c0);
        G.fx.healBurst(pos.clone().add(new THREE.Vector3(0, 0.5, 0)));
        G.sfx.buffetPop(this.volTo(pos));
        // маркер-подбор (только владелец может перезарядить)
        if (mine && !this.buffetReloadUsed) {
          const pm = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.15, 0.3, 12), new THREE.MeshStandardMaterial({ color: 0xe8302c, emissive: 0x551008, emissiveIntensity: 0.4 }));
          pm.position.set(pos.x, 0.15, pos.z);
          G.scene.add(pm);
          this.buffetPickups.push({ owner: id, pos: new THREE.Vector3(pos.x, 0, pos.z), mesh: pm });
        }
        break;
      }
      case 'iraCorpse': {   // Пассивка Иры: её убийство создаёт хил-зону у трупа врага для союзников
        const pos = new THREE.Vector3(data.pos[0], data.pos[1] || 0, data.pos[2]);
        const r = data.r || ABILITY.IRA_CORPSE_R;
        G.fx.steam(() => pos, r * 0.6, data.dur || ABILITY.IRA_CORPSE_TIME, 0x88ffa0);  // зелёный лечебный пар
        G.fx.healBurst(pos.clone().add(new THREE.Vector3(0, 0.4, 0)));
        G.sfx.buffetPop(this.volTo(pos));
        break;
      }
      case 'scoutPing': {
        const ownerAlly = G.players.get(id) && G.players.get(id).team === G.myTeam;
        if (ownerAlly) {
          const r = G.remotes.get(data.target);
          if (r) r.revealedUntil = now() + ABILITY.SCOUT_REVEAL;
          G.revealed.set(data.target, now() + ABILITY.SCOUT_REVEAL);
        } else if (data.target === G.myId) {
          G.hud.announce('', 'ВАС ЗАСЁК КУРИНЫЙ ДОЗОР!', 1.5);
        }
        G.sfx.chickenCluck(0.8);
        break;
      }
      case 'sovaPing': {   // Сова: разведстрела/дрон подсветили врага команде
        const ownerAlly = G.players.get(id) && G.players.get(id).team === G.myTeam;
        if (ownerAlly) {
          const r = G.remotes.get(data.target);
          if (r) r.revealedUntil = now() + ABILITY.SOVA_MARK_REVEAL;
          G.revealed.set(data.target, now() + ABILITY.SOVA_MARK_REVEAL);
        } else if (data.target === G.myId) {
          G.hud.announce('', 'ВАС ЗАСЕКЛА СОВА!', 1.4);
        }
        break;
      }
      case 'sovaShock': case 'sovaMark': case 'sovaDrone': {
        // ЛЕТЯЩАЯ СТРЕЛА: from → to, эффект срабатывает в точке попадания при долёте
        const from = new THREE.Vector3(...(data.from || [0, 1, 0]));
        const to = new THREE.Vector3(...(data.to || [0, 0, 0]));
        const travel = Math.min(0.8, Math.max(0.12, from.distanceTo(to) * 0.018));
        const col = kind === 'sovaShock' ? 0x9fe8ff : 0x3fa9c9;
        G.sfx.spatial(data.from, () => G.sfx.playBuf('whoosh', { vol: 0.42, rate: 1.5 })); // выстрел из лука
        G.fx.sovaArrow(from, to, travel, col, () => {
          const p = to;
          if (kind === 'sovaShock') {
            G.fx.burst(new THREE.Vector3(p.x, p.y + 0.3, p.z), { n: 22, color: 0x9fe8ff, speed: 6.5, life: 0.5, size: 0.13, gravity: -3 });
            G.fx.ring(new THREE.Vector3(p.x, p.y + 0.05, p.z), 0x3fa9c9, ABILITY.SOVA_SHOCK_R);
            G.sfx.spatial([p.x, p.y + 0.3, p.z], () => G.sfx.playBuf('zap', { vol: 0.65 }));
          } else {
            const rr = kind === 'sovaDrone' ? 6 : ABILITY.SOVA_MARK_R * 0.6;
            G.fx.burst(new THREE.Vector3(p.x, p.y + 0.3, p.z), { n: 10, color: 0x9fe8ff, speed: 3, life: 0.5, size: 0.1, gravity: 0 });
            G.fx.ring(new THREE.Vector3(p.x, p.y + 0.05, p.z), 0x3fa9c9, rr);
            G.sfx.spatial([p.x, p.y + 0.3, p.z], () => G.sfx.playBuf('ting', { vol: 0.55 }));
            if (mine && kind === 'sovaDrone') G.hud.announce('', 'ФИЛИН: СКАН', 1.0);
          }
        });
        break;
      }
      case 'sovaFury': {   // 3 энергозалпа по линии (пробивают стены)
        const from = new THREE.Vector3(...data.from);
        const dr = new THREE.Vector3(...data.dir).setY(0).normalize();
        for (let w = 0; w < ABILITY.SOVA_FURY_WAVES; w++) {
          setTimeout(() => {
            for (let dd = 2; dd < ABILITY.SOVA_FURY_LEN; dd += 2.5) {
              G.fx.burst(from.clone().addScaledVector(dr, dd).setY(1.1), { n: 3, color: 0x9fe8ff, speed: 2, life: 0.32, size: 0.16, gravity: 0 });
            }
          }, w * 320);
        }
        G.sfx.spatial(data.from, () => G.sfx.playBuf('energy', { vol: 0.6 }));
        break;
      }
      case 'banquet': {
        const pos = new THREE.Vector3(data.pos[0], 0, data.pos[2]);
        const fx = G.fx.banquetBucket(pos, ABILITY.BANQUET_R);
        const team = G.players.get(id) ? G.players.get(id).team : 'A';
        G.banquets.push({ owner: id, team, pos, r: ABILITY.BANQUET_R, until: now() + ABILITY.BANQUET_TIME, fx });
        G.sfx.banquetSummon();
        G.hud.announce(mine ? 'ФИНАЛЬНЫЙ БАНКЕТ' : (team === G.myTeam ? 'СОЮЗНЫЙ БАНКЕТ — В УКРЫТИЕ!' : 'ВРАЖЕСКИЙ БАНКЕТ'), '', 2.5);
        break;
      }

      // ===== Гера: анти-смокер =====
      case 'geraDispel': {   // развеивает вражеские дымы в радиусе + вспышка
        const pos = new THREE.Vector3(data.pos[0], data.pos[1] || 0, data.pos[2]);
        G.fx.burst(pos.clone().add(new THREE.Vector3(0, 1, 0)), { n: 22, color: 0x5fe0d0, speed: 7, life: 0.5, size: 0.2, gravity: 1 });
        const gTeam = (G.players.get(id) || {}).team;
        for (const s of this.smokes) {   // локально гасим ТОЛЬКО вражеские дымы (свои не трогаем)
          if (s.team && s.team !== gTeam && Math.hypot(s.pos.x - pos.x, s.pos.z - pos.z) < ABILITY.GERA_DISPEL_R + s.r) { if (s.fx) s.fx.kill(); s.until = 0; }
        }
        this.smokes = this.smokes.filter(s => s.until > now());
        G.sfx.flashPop(0.5);
        if (mine) G.hud.announce('', 'РАЗВЕЯТЕЛЬ', 1.2);
        break;
      }
      case 'geraGrapple': {   // грэпл-ропа + зип у владельца
        const from = new THREE.Vector3(...data.from);
        const to = new THREE.Vector3(...data.to);
        const rope = new THREE.Line(new THREE.BufferGeometry().setFromPoints([from, to]), new THREE.LineBasicMaterial({ color: 0x5fe0d0 }));
        G.scene.add(rope);
        setTimeout(() => G.scene.remove(rope), 350);
        if (mine) G.pulled = { from: G.player.pos.clone(), to: to.clone(), t: 0, dur: Math.max(0.18, from.distanceTo(to) / ABILITY.GERA_GRAPPLE_SPEED) };
        G.sfx.hookThrow();
        break;
      }
      case 'geraVortex': {   // конус стягивания — цепочка искр по направлению
        const f = new THREE.Vector3(data.from[0], 0.8, data.from[2]);
        const dr = new THREE.Vector3(data.dir[0], 0, data.dir[2]).normalize();
        for (let dd = 2; dd < ABILITY.GERA_VORTEX_RANGE; dd += 2) {
          G.fx.burst(f.clone().addScaledVector(dr, dd), { n: 4, color: 0x5fe0d0, speed: 4, life: 0.4, size: 0.15, gravity: 0 });
        }
        G.sfx.dash(0.6);
        break;
      }
      case 'geraUlt': {   // купол невесомости
        const pos = new THREE.Vector3(data.pos[0], 0, data.pos[2]);
        G.fx.steam(() => pos, ABILITY.GERA_ULT_R, ABILITY.GERA_ULT_TIME, 0x9fe8ff);
        G.hud.announce('', mine ? 'НЕВЕСОМОСТЬ' : 'НЕВЕСОМОСТЬ ГЕРЫ!', 1.5);
        G.sfx.xray();
        break;
      }

      // ===== Конилий: галоп + табун =====
      case 'gallop': {
        if (mine) { G.gallopUntil = now() + ABILITY.GALLOP_TIME; G.hud.announce('', 'ГАЛОП: +50% СКОРОСТИ', 1.5); }
        const src = this.posOf(id);
        if (src) G.fx.burst(src.clone().add(new THREE.Vector3(0, 0.3, 0)), { n: 14, color: 0xcaa870, speed: 3, life: 0.5, size: 0.14, gravity: 2 });
        G.sfx.gallop(mine ? 1 : 0.5);
        break;
      }
      case 'stampede': {
        const from = new THREE.Vector3(data.from[0], 0, data.from[2]);
        let to = new THREE.Vector3(data.to[0], 0, data.to[1]);
        const d = to.clone().sub(from);
        const len = Math.min(ABILITY.STAMPEDE_LEN, d.length() || 1);
        d.normalize();
        to = from.clone().addScaledVector(d, len);
        G.fx.stampede(from, to);
        G.sfx.stampede();
        if (mine) G.hud.announce('ТАБУН', 'КОНИ ПОНЕСЛИ!', 2);
        else if (G.players.get(id) && G.players.get(id).team !== G.myTeam) G.hud.announce('', 'ТАБУН НЕСЁТСЯ — В СТОРОНУ!', 1.5);
        break;
      }

      // ===== Фафик: клоны =====
      case 'fafikClones': {
        G.clonedIds.add(id);
        if (mine) { G.cloneMode = true; G.hud.announce('КЛОНЫ БАТИ', 'НАЖМИ X СНОВА — ВЕРНУТЬ СТРЕЛЬБУ', 2.5); }
        const from = new THREE.Vector3(data.from[0], 0, data.from[2]);
        const to = new THREE.Vector3(data.to[0], 0, data.to[1]);
        const dirv = to.clone().sub(from); dirv.y = 0;
        const yaw = Math.atan2(-dirv.x, -dirv.z);
        const perp = new THREE.Vector3(-dirv.z, 0, dirv.x).normalize();
        const clones = [];
        for (let i = 0; i < ABILITY.CLONES_COUNT; i++) {
          const h = buildHumanoid('fafik');
          const off = (i - (ABILITY.CLONES_COUNT - 1) / 2) * 0.9;
          const start = from.clone().addScaledVector(perp, off);
          h.group.position.copy(start);
          h.group.rotation.y = yaw;
          G.scene.add(h.group);
          this.registerDecoy(h, id);
          clones.push({ h, pos: start.clone(), target: to.clone().addScaledVector(perp, off), phase: Math.random() * 6 });
        }
        this.cloneSets.set(id, { clones, born: now(), owner: id });
        G.sfx.dadClones();
        break;
      }
      case 'fafikDeClone': {
        G.clonedIds.delete(id);
        if (mine) { G.cloneMode = false; G.hud.announce('', 'КЛОНЫ РАССЕЯНЫ — ТЫ СНОВА СТРЕЛЯЕШЬ', 1.5); }
        const set = this.cloneSets.get(id);
        if (set) { for (const c of set.clones) G.scene.remove(c.h.group); this.cloneSets.delete(id); }
        G.sfx.dadDeClone();
        break;
      }

      // ===== Денис: реворк C/Q =====
      case 'bloodfeast': {
        // хил считает сервер; тут — визуал пожирания
        const src = this.posOf(id);
        if (src) {
          const c = src.clone().add(new THREE.Vector3(0, 1, 0));
          G.fx.burst(c, { n: 16, color: 0xaa1122, speed: 2.4, life: 0.5, size: 0.16, gravity: 4, tex: G.fx.bloodTex });
          G.fx.ring(src, 0x88cc44, 3);
        }
        G.sfx.feast(this.volTo(src || G.player.pos));
        break;
      }
      case 'scent': {
        const pos = new THREE.Vector3(data.pos[0], 0, data.pos[2]);
        const mesh = new THREE.Mesh(
          new THREE.SphereGeometry(0.22, 10, 8),
          new THREE.MeshStandardMaterial({ color: 0x7a2b26, roughness: 0.8 })
        );
        mesh.scale.set(1.2, 0.7, 1.1);
        mesh.position.set(pos.x, 0.16, pos.z);
        G.scene.add(mesh);
        this.scents.push({ owner: id, pos, mesh, until: now() + ABILITY.SCENT_LIFE });
        G.sfx.throwLight();
        break;
      }
      case 'scentPing': {
        const ownerAlly = G.players.get(id) && G.players.get(id).team === G.myTeam;
        if (ownerAlly) {
          const r = G.remotes.get(data.target);
          if (r) r.revealedUntil = now() + ABILITY.SCENT_REVEAL;
          G.revealed.set(data.target, now() + ABILITY.SCENT_REVEAL);
        } else if (data.target === G.myId) {
          G.hud.announce('', 'ДЕНИС ЧУЕТ ТЕБЯ ПО КРОВИ!', 1.4);
        }
        G.sfx.growl(0.7);
        break;
      }

      // ===== Фафик: реворк Q/E (дуэлянт-обманщик) =====
      case 'twin': {
        if (mine) G.player.dash(ABILITY.TWIN_DASH);
        const from = new THREE.Vector3(data.from[0], 0, data.from[2]);
        const h = buildHumanoid('fafik');
        h.group.position.copy(from);
        h.group.rotation.y = data.yaw || 0;
        G.scene.add(h.group);
        this.registerDecoy(h, id);
        this.decoys.push({ owner: id, h, pos: from.clone(), kind: 'stand', until: now() + ABILITY.TWIN_DECOY_TIME, phase: 0 });
        G.sfx.dash(mine ? 1 : 0.4);
        break;
      }
      case 'swapCast': {
        const from = new THREE.Vector3(data.from[0], 0, data.from[2]);
        const dirv = new THREE.Vector3(data.dir[0], 0, data.dir[1]).normalize();
        const h = buildHumanoid('fafik');
        h.group.position.copy(from);
        h.group.rotation.y = data.yaw || 0;
        G.scene.add(h.group);
        this.registerDecoy(h, id);
        const decoy = { owner: id, h, pos: from.clone(), dir: dirv, kind: 'run', until: now() + ABILITY.SWAP_LIFE, phase: 0, traveled: 0 };
        this.decoys.push(decoy);
        if (mine) { this.swapDecoy = decoy; G.hud.announce('', 'РОКИРОВКА ГОТОВА — НАЖМИ E ЕЩЁ РАЗ', 2); }
        G.sfx.dadClones();
        break;
      }
      case 'swapDo': {
        const runs = this.decoys.filter(d => d.owner === id && d.kind === 'run');
        const decoy = runs[runs.length - 1];
        if (decoy) {
          if (mine) {
            G.player.teleport([decoy.pos.x, 0, decoy.pos.z], G.player.yaw);
            this.swapDecoy = null;
            G.fx.ring(decoy.pos, 0x9fd0ff, 3);
          }
          G.fx.burst(decoy.pos.clone().add(new THREE.Vector3(0, 1, 0)), { n: 12, color: 0x9fd0f0, speed: 4, life: 0.35, size: 0.15 });
          G.scene.remove(decoy.h.group);
          this.decoys = this.decoys.filter(d => d !== decoy);
        }
        G.sfx.dadDeClone();
        break;
      }
    }
  }

  removeTurret(owner) {
    const t = this.turrets.get(owner);
    if (t) {
      t.fx.kill();
      this.turrets.delete(owner);
      this.G.shootables = this.G.shootables.filter(s => s.shootId !== 'turret:' + owner);
      this.G.fx.burst(t.pos.clone().add(new THREE.Vector3(0, 0.5, 0)), { n: 16, color: 0xffcc44, speed: 4, life: 0.4, size: 0.2 });
    }
  }

  onPlayerDeath(id) {
    if (this.turrets.has(id)) this.removeTurret(id);
  }

  onShootableHit(shootId, dmg) {
    const G = this.G;
    if (shootId.startsWith('turret:')) {
      const owner = Number(shootId.split(':')[1]);
      if (owner === G.myId) {
        const t = this.turrets.get(G.myId);
        if (t) {
          t.hp -= dmg;
          if (t.hp <= 0) G.net.send({ t: 'ability', kind: 'turretDead', data: { owner: G.myId } });
        }
      } else {
        G.net.send({ t: 'ability', kind: 'turretDmg', data: { owner, dmg } });
      }
    } else if (shootId.startsWith('clone:')) {
      // #1 отстрел клона Фафика — просим сервер лопнуть его и оглушить врагов вокруг
      const c = this.cloneById.get(shootId);
      if (c) this.G.net.send({ t: 'clonePop', cloneId: shootId, pos: [c.h.group.position.x, c.h.group.position.z], owner: c.owner });
    }
  }

  // регистрирует гуманоида-клона как отстреливаемую цель (cloneId одинаков у всех клиентов)
  registerDecoy(h, owner) {
    const cloneId = 'clone:' + (this._cloneSeq++);
    for (const m of h.hitMeshes) { m.userData.shootId = cloneId; this.G.shootables.push({ mesh: m, shootId: cloneId }); }
    this.cloneById.set(cloneId, { h, owner });
    return cloneId;
  }
  // лопнуть клона у ВСЕХ (по общему cloneId) + шоквейв; стан считает сервер
  popClone(cloneId, pos) {
    const c = this.cloneById.get(cloneId);
    if (c) {
      const h = c.h;
      this.G.scene.remove(h.group);
      this.G.shootables = this.G.shootables.filter(s => s.shootId !== cloneId);
      this.decoys = this.decoys.filter(d => d.h !== h);
      for (const set of this.cloneSets.values()) set.clones = set.clones.filter(cc => cc.h !== h);
      if (this.swapDecoy && this.swapDecoy.h === h) this.swapDecoy = null;
      this.cloneById.delete(cloneId);
    }
    const p = new THREE.Vector3(pos[0], 0, pos[2]);
    this.G.fx.burst(p.clone().add(new THREE.Vector3(0, 1, 0)), { n: 20, color: 0x9fc0e6, speed: 5, life: 0.5, size: 0.18 });
    this.G.fx.ring(p, 0x9fc0e6, ABILITY.CLONE_POP_STUN_R * 1.4);
    this.G.fx.light(p.clone().add(new THREE.Vector3(0, 1, 0)), 0xaaccff, 4, 14, 0.35);
    this.G.sfx.clonePop(this.volTo(p));
  }

  disposeHook() {
    if (!this.hook) return;
    this.G.scene.remove(this.hook.mesh);
    this.G.scene.remove(this.hook.rope);
    this.hook = null;
  }

  makeCocoonRope(victim, by) {
    this.disposeCocoonRope();
    const geo = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3()]);
    const line = new THREE.Line(geo, new THREE.LineBasicMaterial({ color: 0x553322 }));
    this.G.scene.add(line);
    this.cocoonRope = { line, victim, by };
  }
  disposeCocoonRope() {
    if (this.cocoonRope) {
      this.G.scene.remove(this.cocoonRope.line);
      this.cocoonRope = null;
    }
  }

  posOf(id) {
    const G = this.G;
    if (id === G.myId) return G.player.pos.clone();
    const r = G.remotes.get(id);
    return r ? r.pos.clone() : null;
  }

  losClear(from, to) {
    const dir = to.clone().sub(from);
    const dist = dir.length();
    dir.normalize();
    this.ray.set(from, dir);
    this.ray.far = dist - 0.2;
    if (this.ray.intersectObjects(this.G.map.solids, false).length > 0) return false;
    const t = now();
    for (const s of this.smokes) {
      if (t < s.until) {
        // отрезок против сферы
        const ab = to.clone().sub(from);
        const ac = s.pos.clone().sub(from);
        const len2 = ab.lengthSq();
        let k = len2 ? ac.dot(ab) / len2 : 0;
        k = Math.max(0, Math.min(1, k));
        if (from.clone().addScaledVector(ab, k).distanceTo(s.pos) <= s.r) return false;
      }
    }
    return true;
  }

  volTo(pos) {
    const d = this.G.player.pos.distanceTo(pos);
    return Math.max(0.15, 1 - d / 40);
  }

  addAccum(cause, amt, by) {
    if (!this.accum.dmg[cause]) this.accum.dmg[cause] = { amt: 0, by };
    this.accum.dmg[cause].amt += amt;
  }

  // ===== главный тик =====
  update(dt) {
    const G = this.G;
    const t = now();

    // --- вспышки ---
    for (let i = this.orbs.length - 1; i >= 0; i--) {
      const o = this.orbs[i];
      o.vel.addScaledVector(o.curve, dt);
      const step = o.vel.clone().multiplyScalar(dt);
      this.ray.set(o.pos, step.clone().normalize());
      this.ray.far = step.length() + 0.2;
      if (this.ray.intersectObjects(G.map.solids, false).length > 0) {
        o.vel.set(0, 0, 0); o.curve.set(0, 0, 0);
      } else {
        o.pos.add(step);
      }
      o.mesh.position.copy(o.pos);
      if (t - o.born >= ABILITY.FLASH_FUSE) {
        G.fx.light(o.pos, o.stink ? 0xa8d060 : 0xffffff, 8, 20, 0.3);
        G.fx.ring(o.pos, o.stink ? 0xa8d060 : 0xffffff, 4);
        G.sfx.flashPop(this.volTo(o.pos));
        const eye = G.player.eyePos();
        const toOrb = o.pos.clone().sub(eye);
        const dist = toOrb.length();
        toOrb.normalize();
        const dot = this.lookDir().dot(toOrb);
        if (G.me.alive && dist < 40 && dot > 0.3 && this.losClear(eye, o.pos)) {
          const k = (dot - 0.3) / 0.7;
          const cc = this.char === 'fafik' ? 0.7 : 1;   // пассивка Фафика «Батина закалка»: ослепление короче на 30%
          G.blindUntil = t + (0.4 + k * (ABILITY.FLASH_MAX_BLIND - 0.4)) * cc;
          G.blindStink = o.stink;
        }
        // владелец сообщает серверу — тот ослепляет смотрящих ботов
        if (o.owner === G.myId) G.net.send({ t: 'flashPop', pos: [o.pos.x, o.pos.y, o.pos.z] });
        G.scene.remove(o.mesh);
        this.orbs.splice(i, 1);
      }
    }

    // --- летящие зоны (молли/тухлятина/кислота) ---
    for (let i = this.mollies.length - 1; i >= 0; i--) {
      const m = this.mollies[i];
      m.vel.y -= 14 * dt;
      const step = m.vel.clone().multiplyScalar(dt);
      let landed = false;
      this.ray.set(m.pos, step.clone().normalize());
      this.ray.far = step.length() + 0.15;
      const hits = this.ray.intersectObjects(G.map.solids, false);
      if (hits.length > 0) { m.pos.copy(hits[0].point); landed = true; }
      else { m.pos.add(step); if (m.pos.y <= 0.05) landed = true; }
      m.mesh.position.copy(m.pos);
      if (landed) {
        const zonePos = new THREE.Vector3(m.pos.x, Math.max(0, m.pos.y - 0.1), m.pos.z);
        const cfg = {
          fire: { r: ABILITY.FIRE_ZONE_R, dur: ABILITY.FIRE_ZONE_TIME },
          mangal: { r: ABILITY.MANGAL_R, dur: ABILITY.MANGAL_TIME },
          puddle: { r: ABILITY.PUDDLE_R, dur: ABILITY.PUDDLE_TIME },
          acid: { r: ABILITY.ACID_R, dur: ABILITY.ACID_TIME },
          horseshoe: { r: ABILITY.HORSESHOE_R, dur: ABILITY.HORSESHOE_TIME },
        }[m.kind];
        let fx = null;
        if (m.kind === 'fire' || m.kind === 'mangal') { fx = G.fx.fireZoneFx(zonePos, cfg.r); G.sfx.fireIgnite(this.volTo(zonePos)); }
        else { const col = m.kind === 'acid' ? 0xd6e84d : m.kind === 'horseshoe' ? 0xb8a06a : 0x7a9b3a; G.fx.puddle(zonePos, cfg.r, cfg.dur, col); G.sfx.puddleSplat(this.volTo(zonePos)); }
        this.zones.push({ type: m.kind, owner: m.owner, until: t + cfg.dur, pos: zonePos, r: cfg.r, fx });
        if (m.owner === G.myId) {
          G.net.send({ t: 'zone', ztype: m.kind, pos: zonePos.toArray(), r: cfg.r, dur: cfg.dur });
        }
        G.scene.remove(m.mesh);
        this.mollies.splice(i, 1);
      }
    }

    // --- зоны/дымы/метки: срок жизни ---
    for (let i = this.zones.length - 1; i >= 0; i--) {
      if (t >= this.zones[i].until) {
        const fx = this.zones[i].fx;
        fx && fx.kill && fx.kill();
        this.zones.splice(i, 1);
      }
    }
    this.smokes = this.smokes.filter(s => t < s.until);
    for (let i = this.ultMarkers.length - 1; i >= 0; i--) {
      if (t >= this.ultMarkers[i].until) {
        this.ultMarkers[i].fx.kill();
        this.ultMarkers.splice(i, 1);
      }
    }

    // --- урон/замедление от зон для МЕНЯ ---
    if (G.me.alive && G.liveish()) {
      const myPos = G.player.pos;
      let slow = 1, inMyFire = false;
      for (const z of this.zones) {
        if (z.from && t < z.from) continue;
        let inside = false;
        if (z.type === 'wall') {
          inside = distToSeg2D(myPos, z.a, z.b) < 1.25 && myPos.y < 2.5;
        } else {
          inside = Math.hypot(myPos.x - z.pos.x, myPos.z - z.pos.z) < z.r && Math.abs(myPos.y - z.pos.y) < 2.5;
        }
        if (!inside) continue;
        const enemyZone = z.owner !== G.myId && (!G.players.get(z.owner) || G.players.get(z.owner).team !== G.myTeam);
        if (z.type === 'fire' || z.type === 'wall') {
          if (enemyZone) this.addAccum('fire', ABILITY.FIRE_DPS * dt, z.owner);
          // Твист Артемия: чем ниже HP, тем сильнее лечит его огонь (камбэк-дуэлянт) — до ~2.3× на грани смерти
          if (z.owner === G.myId && this.char === 'artemiy' && G.me.hp < G.me.maxHp) this.accum.heal += ABILITY.FIRE_HEAL * dt * (1 + (1 - G.me.hp / G.me.maxHp) * 1.3);
          else if (!enemyZone && z.owner !== G.myId) inMyFire = true;
          if (Math.random() < dt * 8) G.sfx.fireCrackle(1);
        } else if (z.type === 'mangal' && enemyZone) {
          this.addAccum('fire', ABILITY.MANGAL_DPS * dt, z.owner);
          if (Math.random() < dt * 8) G.sfx.fireCrackle(1);
        } else if (z.type === 'horseshoe' && enemyZone) {
          this.addAccum('acid', ABILITY.HORSESHOE_DPS * dt, z.owner);
          slow = Math.min(slow, ABILITY.HORSESHOE_SLOW);
        } else if (z.type === 'puddle' && enemyZone) {
          this.addAccum('puddle', ABILITY.PUDDLE_DPS * dt, z.owner);
          slow = Math.min(slow, ABILITY.PUDDLE_SLOW);
        } else if (z.type === 'acid' && enemyZone) {
          this.addAccum('acid', ABILITY.ACID_DPS * dt, z.owner);
          slow = Math.min(slow, ABILITY.ACID_SLOW);
        } else if (z.type === 'orbital' && enemyZone) {
          this.addAccum('orbital', ABILITY.ORBITAL_DPS * dt, z.owner);
        }
      }
      G.slowMul = slow;

      this.accum.t += dt;
      if (this.accum.t >= 0.4) {
        this.accum.t = 0;
        for (const [cause, d] of Object.entries(this.accum.dmg)) {
          if (d.amt >= 1) {
            G.net.send({ t: 'selfDamage', dmg: Math.round(d.amt), cause, by: d.by });
            d.amt = 0;
          }
        }
        if (this.accum.heal >= 1) {
          G.net.send({ t: 'selfHeal', amt: Math.round(this.accum.heal) });
          this.accum.heal = 0;
        }
      }
    } else {
      G.slowMul = 1;
    }

    // --- сигналки (владелец следит за врагами) ---
    for (const trap of this.traps) {
      if (trap.used || trap.owner !== G.myId) continue;
      for (const [pid, r] of G.remotes) {
        const info = G.players.get(pid);
        if (!info || info.team === G.myTeam || !r.alive) continue;
        if (r.pos.distanceTo(trap.pos) < ABILITY.TRAP_R) {
          trap.used = true;
          trap.fx.kill();
          G.net.send({ t: 'ability', kind: 'trapTrig', data: { target: pid } });
          break;
        }
      }
    }
    this.traps = this.traps.filter(tr => !tr.used);

    // --- турель (владелец наводит и стреляет) ---
    const myTurret = this.turrets.get(G.myId);
    if (myTurret && G.liveish() && t >= myTurret.nextShot) {
      myTurret.nextShot = t + ABILITY.TURRET_TICK;
      let best = null, bd = ABILITY.TURRET_R;
      const tPos = myTurret.pos.clone().add(new THREE.Vector3(0, 0.5, 0));
      for (const [pid, r] of G.remotes) {
        const info = G.players.get(pid);
        if (!info || info.team === G.myTeam || !r.alive) continue;
        const d = r.pos.distanceTo(myTurret.pos);
        if (d < bd && this.losClear(tPos, r.pos.clone().add(new THREE.Vector3(0, 1.1, 0)))) {
          bd = d; best = { pid, r };
        }
      }
      if (best) {
        myTurret.fx.aimAt(best.r.pos);
        const to = best.r.pos.clone().add(new THREE.Vector3(0, 1.1, 0));
        G.net.send({ t: 'hit', target: best.pid, dmg: ABILITY.TURRET_DMG, part: 'body', weapon: 'turret' });
        G.net.send({ t: 'ability', kind: 'turretShot', data: { to: to.toArray() } });
        G.fx.tracer(tPos, to, 0xffe48a);
        G.sfx.turretShot(0.6);
      }
    }

    // ===== Ира =====
    // куриный дозор: бежит вперёд, владелец детектит врагов
    for (let i = this.scouts.length - 1; i >= 0; i--) {
      const s = this.scouts[i];
      const step = s.dir.clone().multiplyScalar(ABILITY.SCOUT_SPEED * dt);
      this.ray.set(s.pos, s.dir); this.ray.far = step.length() + 0.25;
      if (this.ray.intersectObjects(G.map.solids, false).length > 0) {
        G.fx.burst(s.pos, { n: 8, color: 0xf4f0e6, speed: 2, life: 0.4, size: 0.1 });
        s.fx.kill(); this.scouts.splice(i, 1); continue;
      }
      s.pos.add(step);
      s.fx.group.position.copy(s.pos);
      s.fx.group.rotation.y = Math.atan2(-s.dir.x, -s.dir.z);
      if (s.owner === G.myId) {
        for (const [pid, r] of G.remotes) {
          const info = G.players.get(pid);
          if (!info || info.team === G.myTeam || !r.alive) continue;
          if (r.pos.distanceTo(s.pos) < ABILITY.SCOUT_RANGE && !s.detected.has(pid)) {
            s.detected.add(pid);
            G.net.send({ t: 'ability', kind: 'scoutPing', data: { target: pid } });
          }
        }
      }
      if (t - s.born >= ABILITY.SCOUT_LIFE) { s.fx.kill(); this.scouts.splice(i, 1); }
    }

    // буфет: ведёрко летит по дуге, при падении — взрыв целебного пара
    for (let i = this.buffets.length - 1; i >= 0; i--) {
      const b = this.buffets[i];
      b.vel.y -= 14 * dt;
      const step = b.vel.clone().multiplyScalar(dt);
      let landed = false;
      this.ray.set(b.pos, step.clone().normalize()); this.ray.far = step.length() + 0.15;
      const hits = this.ray.intersectObjects(G.map.solids, false);
      if (hits.length) { b.pos.copy(hits[0].point); landed = true; }
      else { b.pos.add(step); if (b.pos.y <= 0.12) landed = true; }
      b.mesh.position.copy(b.pos);
      b.mesh.rotation.x += dt * 8; b.mesh.rotation.z += dt * 6;
      if (landed) {
        const pos = new THREE.Vector3(b.pos.x, Math.max(0, b.pos.y), b.pos.z);
        G.scene.remove(b.mesh);
        this.buffets.splice(i, 1);
        if (b.owner === G.myId) {
          G.net.send({ t: 'ability', kind: 'buffetPop', data: { pos: [pos.x, pos.y, pos.z] } });
          G.net.send({ t: 'healBurst', pos: [pos.x, pos.y, pos.z], r: ABILITY.BUFFET_R, amount: ABILITY.BUFFET_HEAL });
        }
      }
    }

    // подбор ведёрка → перезарядка E (один раз за раунд)
    for (let i = this.buffetPickups.length - 1; i >= 0; i--) {
      const pk = this.buffetPickups[i];
      pk.mesh.rotation.y += dt * 2;
      if (pk.owner === G.myId && !this.buffetReloadUsed && G.player.pos.distanceTo(pk.pos) < 1.4) {
        this.buffetReloadUsed = true;
        this.charges.E = Math.min(CHARACTERS.ira.abilities.E.charges || 1, this.charges.E + 1);
        G.scene.remove(pk.mesh);
        this.buffetPickups.splice(i, 1);
        G.hud.announce('', 'ВЕДЁРКО ПЕРЕЗАРЯЖЕНО', 1.5);
        G.sfx.buy();
      }
    }

    // сроки жизни криспи-стен и банкетов
    for (let i = this.crispyWalls.length - 1; i >= 0; i--) {
      if (t >= this.crispyWalls[i].until) { this.crispyWalls[i].fx.kill(); this.crispyWalls.splice(i, 1); }
    }
    for (let i = G.banquets.length - 1; i >= 0; i--) {
      if (t >= G.banquets[i].until) { G.banquets[i].fx && G.banquets[i].fx.kill(); G.banquets.splice(i, 1); }
    }

    // локальные эффекты движения: криспи замедляет врагов, банкет ускоряет союзников
    if (G.me.alive && G.liveish()) {
      for (const w of this.crispyWalls) {
        const enemy = w.owner !== G.myId && (!G.players.get(w.owner) || G.players.get(w.owner).team !== G.myTeam);
        if (enemy && distToSeg2D(G.player.pos, w.a, w.b) < 1.4 && G.player.pos.y < 2.6) {
          G.slowMul = Math.min(G.slowMul, ABILITY.CRISPY_SLOW);
        }
      }
      for (const bq of G.banquets) {
        if (bq.team === G.myTeam && G.player.pos.distanceTo(bq.pos) < bq.r) { G.banquetUntil = t + 0.2; break; }
      }
    }

    // Фафик: клоны бегут к точке
    for (const [owner, set] of this.cloneSets) {
      const age = t - set.born;
      for (const c of set.clones) {
        const dx = c.target.x - c.pos.x, dz = c.target.z - c.pos.z;
        const d = Math.hypot(dx, dz);
        let walking = false;
        if (d > 0.35) {
          const step = Math.min(d, ABILITY.CLONES_SPEED * dt);
          c.pos.x += dx / d * step; c.pos.z += dz / d * step;
          c.h.group.rotation.y = Math.atan2(-dx, -dz);
          walking = true;
        }
        c.h.group.position.set(c.pos.x, 0, c.pos.z);
        c.phase += dt * 11;
        const s = Math.sin(c.phase);
        const amp = walking ? 0.62 : 0;
        c.h.rig.legL.hip.rotation.x = s * amp;
        c.h.rig.legR.hip.rotation.x = -s * amp;
        c.h.rig.legL.knee.rotation.x = Math.max(0, -s) * amp * 1.5 + 0.08;
        c.h.rig.legR.knee.rotation.x = Math.max(0, s) * amp * 1.5 + 0.08;
        c.h.rig.armL.shoulder.rotation.x = -s * amp * 0.85;
        c.h.rig.armR.shoulder.rotation.x = s * amp * 0.4 - 0.5;
        c.h.rig.body.position.y = Math.abs(Math.sin(c.phase)) * 0.05 * amp;
      }
      if (age >= ABILITY.CLONES_TIME && owner === G.myId && G.cloneMode) {
        G.net.send({ t: 'ability', kind: 'fafikDeClone', data: {} });
      }
    }

    // Фафик: двойники (стоячий) и клон рокировки (бегущий)
    for (let i = this.decoys.length - 1; i >= 0; i--) {
      const dc = this.decoys[i];
      if (dc.kind === 'run') {
        const step = dc.dir.clone().multiplyScalar(ABILITY.SWAP_SPEED * dt);
        this.ray.set(dc.pos, dc.dir); this.ray.far = step.length() + 0.35;
        const hitWall = this.ray.intersectObjects(G.map.solids, false).length > 0;
        if (!hitWall && dc.traveled < ABILITY.SWAP_DECOY_RANGE) {
          dc.pos.add(step); dc.traveled += step.length();
          dc.phase += dt * 12;
          const s = Math.sin(dc.phase);
          dc.h.rig.legL.hip.rotation.x = s * 0.6; dc.h.rig.legR.hip.rotation.x = -s * 0.6;
          dc.h.rig.armL.shoulder.rotation.x = -s * 0.5; dc.h.rig.armR.shoulder.rotation.x = s * 0.3 - 0.5;
          dc.h.rig.body.position.y = Math.abs(s) * 0.05;
        }
        dc.h.group.position.set(dc.pos.x, 0, dc.pos.z);
      } else {
        dc.phase += dt;
        dc.h.rig.body.position.y = Math.sin(dc.phase * 2) * 0.012; // дышит на месте
      }
      if (now() >= dc.until) {
        if (this.swapDecoy === dc) this.swapDecoy = null;
        G.scene.remove(dc.h.group);
        this.decoys.splice(i, 1);
      }
    }

    // Денис: приманки «нюх мясника» — реветь считает сервер, тут срок жизни визуала
    for (let i = this.scents.length - 1; i >= 0; i--) {
      const sc = this.scents[i];
      sc.mesh.rotation.y += dt * 1.5;
      if (t >= sc.until) { G.scene.remove(sc.mesh); this.scents.splice(i, 1); }
    }

    // --- крюк-ульта Дениса ---
    if (this.hook) this.updateHook(dt, t);

    // --- верёвка кокона ---
    if (this.cocoonRope) {
      const a = this.posOf(this.cocoonRope.by);
      const b = this.posOf(this.cocoonRope.victim);
      if (a && b) {
        const pts = this.cocoonRope.line.geometry.attributes.position.array;
        pts[0] = a.x; pts[1] = a.y + 1.2; pts[2] = a.z;
        pts[3] = b.x; pts[4] = b.y + 1.0; pts[5] = b.z;
        this.cocoonRope.line.geometry.attributes.position.needsUpdate = true;
      }
    }
  }

  updateHook(dt, t) {
    const G = this.G;
    const h = this.hook;
    const ownerPos = (this.posOf(h.owner) || new THREE.Vector3()).add(new THREE.Vector3(0, 1.3, 0));

    if (h.state === 'fly') {
      const step = ABILITY.COCOON_SPEED * dt;
      this.ray.set(h.pos, h.dir);
      this.ray.far = step + 0.1;
      if (this.ray.intersectObjects(G.map.solids, false).length > 0) {
        h.state = 'retract';
      } else {
        h.pos.addScaledVector(h.dir, step);
        h.traveled += step;
        if (h.traveled >= ABILITY.COCOON_RANGE) h.state = 'retract';
        // детект — только хозяин крюка
        if (h.owner === G.myId) {
          for (const [pid, r] of G.remotes) {
            const info = G.players.get(pid);
            if (!info || info.team === G.myTeam || !r.alive) continue;
            if (h.pos.distanceTo(r.pos.clone().add(new THREE.Vector3(0, 1.1, 0))) < 1.0) {
              h.state = 'hit';
              h.until = t + 0.4;
              G.net.send({ t: 'ability', kind: 'cocoonHit', data: { target: pid } });
              break;
            }
          }
        }
      }
    } else if (h.state === 'retract') {
      const back = ownerPos.clone().sub(h.pos);
      const d = back.length();
      if (d < 1 || t > h.until) { this.disposeHook(); return; }
      h.pos.addScaledVector(back.normalize(), ABILITY.COCOON_SPEED * 1.4 * dt);
    } else if (h.state === 'hit') {
      if (t > h.until) { this.disposeHook(); return; }
    }
    if (t > h.until) { this.disposeHook(); return; }

    h.mesh.position.copy(h.pos);
    h.mesh.lookAt(ownerPos);
    const pts = h.rope.geometry.attributes.position.array;
    pts[0] = ownerPos.x; pts[1] = ownerPos.y; pts[2] = ownerPos.z;
    pts[3] = h.pos.x; pts[4] = h.pos.y; pts[5] = h.pos.z;
    h.rope.geometry.attributes.position.needsUpdate = true;
  }

  // данные для HUD
  hudState() {
    const G = this.G;
    const cfg = CHARACTERS[this.char];
    const ult = { label: cfg.abilities.X.name, val: `${G.me.ult}/${cfg.ultCost}`, ok: this.ultReady(), ult: true };
    const slot = (k) => ({ label: cfg.abilities[k].name, val: this.charges[k], ok: this.charges[k] > 0 });
    const st = { C: slot('C'), Q: slot('Q'), E: slot('E'), X: ult };
    if (this.char === 'max' && G.knives) st.X = { label: 'НОЖИ', val: G.knives.count, ok: true, ult: true, active: true };
    return st;
  }
}

function distToSeg2D(p, a, b) {
  const abx = b.x - a.x, abz = b.z - a.z;
  const len2 = abx * abx + abz * abz;
  let k = len2 ? ((p.x - a.x) * abx + (p.z - a.z) * abz) / len2 : 0;
  k = Math.max(0, Math.min(1, k));
  return Math.hypot(p.x - (a.x + abx * k), p.z - (a.z + abz * k));
}
