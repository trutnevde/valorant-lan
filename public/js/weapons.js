// Оружие v2: отдача как в CS (панч камеры + подъём прицела + паттерн спрея),
// дробовики (дробины), спад урона, зум, ножи ульты Макса
import * as THREE from './three.module.js';
import { WEAPONS, ABILITY, weaponFeel } from './shared.js';

const BASE_FOV = 74;

// калибр трассера: снайперка — паровой след, винтовка — жирный, пистолет — тонкий
export function tracerStyle(w) {
  if (!w) return { r: 0.02, life: 0.07, color: 0xffe0a0 };
  switch (w.cat) {
    case 'sniper': return { r: 0.05, life: 0.26, color: 0xd8ecff };
    case 'lmg':
    case 'rifle': return { r: 0.028, life: 0.09, color: 0xffe0a0 };
    case 'shotgun': return { r: 0.013, life: 0.06, color: 0xffd9a0 };
    default: return { r: 0.02, life: 0.07, color: 0xffe0a0 };
  }
}
const now = () => performance.now() / 1000;

export class WeaponSystem {
  constructor(G) {
    this.G = G;
    this.loadout = { primary: null, sidearm: 'classic' };
    this.slot = 'sidearm';
    this.ammo = {};
    this.lastShot = 0;
    this.reloading = 0;
    this.firing = false;
    this.kick = 0;
    this.sprayIdx = 0;       // номер пули в очереди — задаёт паттерн
    this.readyAt = 0;        // оружие ещё достаётся — стрелять нельзя
    // ощущения оружия
    this.aiming = false;
    this.aimT = 0;           // 0..1 — прицеливание (оружие к лицу)
    this.swayX = 0; this.swayY = 0;         // цель отставания от мыши
    this.swayCurX = 0; this.swayCurY = 0;   // сглаженная
    this.bobPhase = 0;
    this.vkickPos = 0; this.vkickRot = 0;   // отдача вьюмодели (толчок ствола)
    this.raycaster = new THREE.Raycaster();
    this.viewmodels = {};
    this.vmRoot = new THREE.Group();
    G.camera.add(this.vmRoot);
    this.buildViewmodels();
    this.buildHands();

    window.addEventListener('mousedown', (e) => {
      if (!document.pointerLockElement) return;
      if (e.button === 0) { this.firing = true; this.tryShoot(true); }
      if (e.button === 2) this.toggleScope(true);
    });
    window.addEventListener('mouseup', (e) => {
      if (e.button === 0) this.firing = false;
      if (e.button === 2) this.toggleScope(false);
    });
    // свей: оружие отстаёт от резких поворотов мыши
    window.addEventListener('mousemove', (e) => {
      if (!document.pointerLockElement || this.G.chatOpen) return;
      const cl = (v) => Math.max(-0.05, Math.min(0.05, v));
      this.swayX = cl(this.swayX - e.movementX * 0.00009);
      this.swayY = cl(this.swayY - e.movementY * 0.00009);
    });
    window.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('keydown', (e) => {
      if (!document.pointerLockElement || this.G.chatOpen) return;
      if (e.code === 'Digit1' && this.loadout.primary) this.equip('primary');
      if (e.code === 'Digit2') this.equip('sidearm');
      if (e.code === 'Digit3') this.equip('knife');
      if (e.code === 'KeyR') this.reload();
    });
  }

  get currentId() {
    return this.slot === 'knife' ? 'knife' : this.loadout[this.slot] || 'classic';
  }
  get w() { return WEAPONS[this.currentId]; }
  get knivesActive() {
    const k = this.G.knives;
    return k && k.count > 0 && now() < k.until;
  }

  canAct() {
    const G = this.G;
    return G.me.alive && !G.freeze && !G.pulled && now() > G.stunnedUntil && !G.cloneMode &&
           !G.holdAction && !G.chatOpen && !G.buyOpen && document.pointerLockElement;
  }

  setLoadout(loadout, refill = true) {
    this.loadout = { primary: loadout.primary || null, sidearm: loadout.sidearm || 'classic' };
    if (refill) {
      for (const id of [this.loadout.primary, this.loadout.sidearm]) {
        if (id) this.ammo[id] = { mag: WEAPONS[id].mag, res: WEAPONS[id].reserve };
      }
    }
    this.equip(this.loadout.primary ? 'primary' : 'sidearm');
  }

  equip(slot) {
    if (slot === 'primary' && !this.loadout.primary) return;
    if (this.slot === slot && now() > this.readyAt) { /* уже в руках */ }
    this.slot = slot;
    this.reloading = 0;
    this.sprayIdx = 0;
    this.readyAt = now() + weaponFeel(this.currentId).equip;
    this.toggleScope(false);
    for (const [id, vm] of Object.entries(this.viewmodels)) vm.visible = id === this.currentId && !this.knivesActive;
    if (this.knivesActive) this.viewmodels.knife.visible = true;
    this.updateHud();
    this.G.sfx.click();
  }

  reload() {
    const id = this.currentId, w = this.w;
    if (w.melee || this.reloading || this.knivesActive) return;
    const a = this.ammo[id];
    if (!a || a.mag >= w.mag || a.res <= 0) return;
    this.reloading = now() + w.reload;
    this.toggleScope(false);
    this.G.sfx.reload();
  }

  // общий ADS: прицеливание любым оружием (оружие поднимается к лицу).
  // Реальный блендинг позы/FOV/G.scoped считается покадрово в update().
  toggleScope(on) {
    if (on) {
      if (!this.canAct() || this.knivesActive || this.w.melee) return;
      this.aiming = true;
    } else {
      this.aiming = false;
    }
  }

  // FOV в прицеле: снайперки — сильный зум, остальные — умеренное приближение
  adsFov() {
    const w = this.w;
    if (w.scope) return this.currentId === 'operator' ? 22 : 30;
    if (w.cat === 'pistol') return 62;
    if (w.cat === 'shotgun') return 64;
    return 55; // винтовки / ПП / пулемёты
  }

  tryShoot(isClick = false) {
    const t = now();
    if (!this.canAct() || this.reloading || t < this.readyAt) return;

    // ножи Макса перекрывают обычное оружие
    if (this.knivesActive) {
      if (!isClick && t - this.lastShot < 0.28) return;
      if (t - this.lastShot < 0.28) return;
      this.lastShot = t;
      this.throwKnife();
      return;
    }

    const w = this.w, id = this.currentId;
    if (!w.auto && !isClick) return;
    if (t - this.lastShot < 60 / w.rpm) return;

    if (!w.melee) {
      const a = this.ammo[id];
      if (!a || a.mag <= 0) {
        if (isClick) { this.G.sfx.dry(); this.reload(); }
        return;
      }
      a.mag--;
    }
    // спрей: сброс, если пауза больше 0.35 c
    if (t - this.lastShot > 0.35) this.sprayIdx = 0;
    this.lastShot = t;
    this.shoot();
    this.updateHud();
  }

  spread() {
    const G = this.G, p = G.player, w = this.w;
    let s = w.spread;
    if (p.crouch) s *= 0.65;
    const hSpeed = Math.hypot(p.vel.x, p.vel.z);
    // штраф растёт со скоростью: стоя — точно, на бегу — молоко; снайперкам хуже всех
    const movePenalty = w.cat === 'sniper' ? 5 : w.cat === 'rifle' ? 3 : 2.2;
    s *= 1 + Math.min(1, hSpeed / 6.2) * movePenalty;
    if (!p.grounded) s *= 4;
    // разгон разброса в длинной очереди
    if (w.auto && this.sprayIdx > 3) s *= 1 + Math.min(1.2, (this.sprayIdx - 3) * 0.06);
    // прицел сужает разброс (снайперки — почти в точку)
    const adsMin = w.scope ? (w.scopeSpread / w.spread) : 0.4;
    s *= (1 - this.aimT * (1 - adsMin));
    return s;
  }

  // направление с учётом панча (пули летят туда, куда реально смотрит камера)
  aimDir() {
    const p = this.G.player;
    const cy = p.yaw + p.punchYaw;
    const cp = p.pitch + p.punchPitch;
    return new THREE.Vector3(-Math.sin(cy) * Math.cos(cp), Math.sin(cp), -Math.cos(cy) * Math.cos(cp));
  }

  applyRecoil(w) {
    const p = this.G.player;
    const idx = this.sprayIdx;
    const aimReduce = 1 - this.aimT * 0.28;   // в прицеле чуть точнее
    // вертикальный подъём: первые пули мягче, потом сильнее (умеренно — без перебора)
    const kick = w.recoil * (idx < 3 ? 0.68 : 0.92) * (1 + Math.min(0.65, idx * 0.05)) * aimReduce;
    // горизонтальный дрейф после 6-й пули — синус-паттерн + шум
    const drift = (idx > 5 ? w.recoil * 0.5 * Math.sin(idx * 0.65) + (Math.random() - 0.5) * w.recoil * 0.28 : (Math.random() - 0.5) * w.recoil * 0.13) * aimReduce;
    p.punchPitch += kick;
    p.punchYaw += drift;
    // часть отдачи оседает в прицеле — её «тянут вниз», как в CS
    p.pitch = Math.min(1.55, p.pitch + kick * 0.26);
    // сочный толчок ствола (продаёт мощь, не швыряя прицел)
    this.vkickPos += 0.018 + w.recoil * 2.2;
    this.vkickRot += 0.03 + w.recoil * 3.4;
    this.sprayIdx++;
  }

  falloffMult(w, dist) {
    if (!w.falloffStart || dist <= w.falloffStart) return 1;
    const k = Math.min(1, (dist - w.falloffStart) / 25);
    return 1 - k * (1 - (w.falloffMin !== undefined ? w.falloffMin : 0.8));
  }

  // цели для луча: стены + живые враги (+ союзник в коконе — его спасают выстрелом) + железки
  targets() {
    const G = this.G;
    const list = [...G.map.solids];
    for (const [pid, r] of G.remotes) {
      if (!r.alive) continue;
      const info = G.players.get(pid);
      if (!info) continue;
      if (info.team !== G.myTeam || G.cocoonedId === pid) list.push(...r.hitMeshes);
    }
    for (const s of G.shootables) list.push(s.mesh);
    return list;
  }

  resolveHit(hit, dmgFor, weaponId) {
    const G = this.G;
    const pid = hit.object.userData.pid;
    const shootId = hit.object.userData.shootId;
    if (pid !== undefined) {
      const r = G.remotes.get(pid);
      let part = hit.object.userData.part || 'body';
      if (part === 'body' && r && hit.point.y < r.group.position.y + 0.75) part = 'leg';
      const dmg = Math.round(dmgFor(part));
      if (dmg > 0) {
        G.net.send({ t: 'hit', target: pid, dmg, part, weapon: weaponId });
        G.fx.blood(hit.point);
        G.hud.hitmarker(part === 'head');
        part === 'head' ? G.sfx.headshot() : G.sfx.hitmarker();
      }
      return true;
    }
    if (shootId !== undefined) {
      G.abilities.onShootableHit(shootId, Math.round(dmgFor('body')));
      G.fx.impact(hit.point);
      G.hud.hitmarker(false);
      G.sfx.hitmarker();
      return true;
    }
    G.fx.impact(hit.point);
    return false;
  }

  shoot() {
    const G = this.G, w = this.w, id = this.currentId;
    const eye = G.player.eyePos();
    const baseDir = this.aimDir();
    const pellets = w.pellets || 1;
    const targets = this.targets();

    for (let i = 0; i < pellets; i++) {
      const dir = baseDir.clone();
      const s = this.spread();
      if (s > 0) {
        const right = new THREE.Vector3().crossVectors(dir, new THREE.Vector3(0, 1, 0)).normalize();
        const up = new THREE.Vector3().crossVectors(right, dir).normalize();
        const a = Math.random() * Math.PI * 2, r = Math.sqrt(Math.random()) * s;
        dir.addScaledVector(right, Math.cos(a) * r).addScaledVector(up, Math.sin(a) * r).normalize();
      }
      this.raycaster.set(eye, dir);
      this.raycaster.far = w.melee ? w.range : 300;
      const hits = this.raycaster.intersectObjects(targets, false);
      const hit = hits[0];
      let end = eye.clone().addScaledVector(dir, w.melee ? w.range : 120);
      if (hit) {
        end = hit.point;
        const dist = hit.distance;
        this.resolveHit(hit, (part) => {
          const base = part === 'head' ? w.head : part === 'leg' ? w.leg : w.dmg;
          return base * this.falloffMult(w, dist);
        }, id);
      }
      if (!w.melee && (pellets === 1 || i % 2 === 0)) {
        const ts = tracerStyle(w);
        G.fx.tracer(this.muzzleWorld(), end, ts.color, ts.r, ts.life);
      }
    }

    if (!w.melee) {
      const mp = this.muzzleWorld();
      G.fx.muzzle(mp, baseDir);
      // гильза вправо + дымок из ствола
      const right = new THREE.Vector3().crossVectors(baseDir, new THREE.Vector3(0, 1, 0)).normalize();
      G.fx.casing(mp.clone().addScaledVector(baseDir, -0.25).addScaledVector(right, 0.06), right);
      if (this.sprayIdx % 2 === 0) G.fx.smokePuff(mp);
      this.applyRecoil(w);
      this.kick = 1;
    } else {
      this.kick = 1;
    }
    G.sfx.shot(id, w.silenced ? 0.45 : 1);
    G.net.send({ t: 'shoot', o: [eye.x, eye.y, eye.z], d: [baseDir.x, baseDir.y, baseDir.z], w: id });
  }

  throwKnife() {
    const G = this.G;
    const k = G.knives;
    if (!k || k.count <= 0) return;
    k.count--;
    const eye = G.player.eyePos();
    const dir = this.aimDir();
    this.raycaster.set(eye, dir);
    this.raycaster.far = 60;
    const hits = this.raycaster.intersectObjects(this.targets(), false);
    const hit = hits[0];
    let end = eye.clone().addScaledVector(dir, 60);
    if (hit) {
      end = hit.point;
      this.resolveHit(hit, (part) => part === 'head' ? ABILITY.KNIFE_HEAD : ABILITY.KNIFE_DMG, 'knives');
    }
    G.fx.tracer(this.muzzleWorld(), end, 0xd0f0ff);
    G.player.punchPitch += 0.012;
    this.kick = 1;
    G.sfx.knifeThrow();
    G.net.send({ t: 'shoot', o: [eye.x, eye.y, eye.z], d: [dir.x, dir.y, dir.z], w: 'knife' });
    this.updateHud();
    if (k.count <= 0) this.endKnives();
  }

  startKnives() {
    this.G.knives = { count: ABILITY.KNIVES_COUNT, until: now() + ABILITY.KNIVES_TIME };
    this.equip('knife');
    this.updateHud();
  }
  endKnives() {
    this.G.knives = null;
    this.equip(this.loadout.primary ? 'primary' : 'sidearm');
  }

  muzzleWorld() {
    const vm = this.viewmodels[this.currentId];
    const tip = vm && vm.userData.tip;
    if (tip) {
      const v = new THREE.Vector3();
      tip.getWorldPosition(v);
      return v;
    }
    return this.G.player.eyePos();
  }

  update(dt) {
    const t = now();
    if (this.reloading && t >= this.reloading) {
      const id = this.currentId, w = this.w, a = this.ammo[id];
      if (a) {
        const need = w.mag - a.mag;
        const take = Math.min(need, a.res);
        a.mag += take; a.res -= take;
      }
      this.reloading = 0;
      this.updateHud();
    }
    if (this.firing && (this.w.auto || this.knivesActive)) this.tryShoot(false);
    if (this.G.knives && t > this.G.knives.until) this.endKnives();
    // спрей затухает без стрельбы
    if (t - this.lastShot > 0.35 && this.sprayIdx > 0) this.sprayIdx = 0;

    const G = this.G, p = G.player;

    // мёртв — оружие спрятано, ощущения не считаем
    if (!G.me.alive) {
      this.aiming = false; this.aimT = 0; G.aimT = 0;
      this.vmRoot.visible = false;
      if (G.scoped) { G.scoped = false; G.camera.fov = BASE_FOV; G.camera.updateProjectionMatrix(); }
      return;
    }

    // ===== прицеливание (ADS) =====
    const canAim = this.aiming && !this.knivesActive && !this.w.melee && G.me.alive && now() > this.readyAt;
    this.aimT += ((canAim ? 1 : 0) - this.aimT) * Math.min(1, dt * 13);
    G.aimT = this.aimT;
    const sniperScoped = this.w.scope && this.aimT > 0.55;
    G.scoped = sniperScoped;

    // ===== динамический FOV: бег чуть расширяет, прицел сужает =====
    const spd = Math.hypot(p.vel.x, p.vel.z);
    const runKick = Math.min(3.5, (spd / 6.2) * 3.5) * (1 - this.aimT);
    const targetFov = (BASE_FOV + runKick) * (1 - this.aimT) + this.adsFov() * this.aimT;
    if (Math.abs(G.camera.fov - targetFov) > 0.02) { G.camera.fov = targetFov; G.camera.updateProjectionMatrix(); }

    // прицел-крестик: прячем при снайп-зуме, приглушаем при ADS
    const ch = document.getElementById('crosshair');
    ch.classList.toggle('scoped', sniperScoped);
    ch.style.opacity = sniperScoped ? '0' : String(1 - this.aimT * 0.55);
    // отрисованный снайперский прицел
    const scope = document.getElementById('scope');
    if (scope) scope.classList.toggle('hidden', !sniperScoped);

    // ===== восстановление толчка ствола (пружина) =====
    this.vkickPos *= Math.exp(-dt * 12);
    this.vkickRot *= Math.exp(-dt * 10);

    // ===== свей от мыши (затухает и рецентрируется) =====
    this.swayX *= Math.exp(-dt * 9);
    this.swayY *= Math.exp(-dt * 9);
    this.swayCurX += (this.swayX - this.swayCurX) * Math.min(1, dt * 12);
    this.swayCurY += (this.swayY - this.swayCurY) * Math.min(1, dt * 12);
    const swayMul = 1 - this.aimT * 0.72;

    // ===== боб оружия при ходьбе (вес в движении) =====
    const moving = p.grounded && spd > 0.6;
    if (moving) this.bobPhase += dt * (6.5 + (spd / 6.2) * 4.5);
    else this.bobPhase += dt * 1.6; // лёгкое дыхание в покое
    const bobAmt = (moving ? Math.min(1.1, spd / 6.2) : 0) * (p.crouch ? 0.5 : 1) * (p.walk ? 0.5 : 1) * (1 - this.aimT * 0.8);
    const idleBob = moving ? 0 : Math.sin(this.bobPhase) * 0.004;
    const bobX = Math.sin(this.bobPhase) * 0.015 * bobAmt;
    const bobY = -Math.abs(Math.sin(this.bobPhase)) * 0.013 * bobAmt + idleBob;

    // ===== анимация доставания: ствол поднимается снизу =====
    const feel = weaponFeel(this.currentId);
    const eq = Math.max(0, Math.min(1, (this.readyAt - now()) / feel.equip));

    // ===== динамический прицел-блум: раскрывается от реального разброса =====
    const bloomSpread = this.w.melee ? 0 : this.spread();
    G.hud.setCrosshairGap(Math.min(30, bloomSpread * 950));

    // ===== поза прицеливания: оружие к центру и ближе к лицу =====
    const a = this.aimT;
    const aimX = -0.28 * a, aimY = 0.088 * a - eq * 0.24, aimZ = 0.14 * a;

    // ===== применяем всё к vmRoot (оружие + руки едины) =====
    this.vmRoot.visible = !sniperScoped;
    this.vmRoot.position.set(
      aimX + bobX + this.swayCurX * swayMul * 0.7,
      aimY + bobY + this.swayCurY * swayMul * 0.7 - (p.landBob || 0) * 0.35,
      aimZ + this.vkickPos
    );
    this.vmRoot.rotation.set(
      this.swayCurY * swayMul * 3 - this.vkickRot - eq * 0.7 + (moving ? Math.sin(this.bobPhase) * 0.012 * bobAmt : 0),
      -this.swayCurX * swayMul * 3.5,
      this.swayCurX * swayMul * 2.2 + (moving ? Math.sin(this.bobPhase * 0.5) * 0.02 * bobAmt : 0)
    );

    // наклон текущего ствола при перезарядке
    this.kick = Math.max(0, this.kick - dt * 9);
    const vmId = this.knivesActive ? 'knife' : this.currentId;
    const vm = this.viewmodels[vmId];
    if (vm) vm.rotation.x = (this.reloading ? 0.65 : 0);
  }

  updateHud() {
    if (this.knivesActive) {
      this.G.hud.setWeapon('СТАЛЬНЫЕ ПЕРЬЯ', this.G.knives.count, '∞');
      return;
    }
    const w = this.w, a = this.ammo[this.currentId];
    this.G.hud.setWeapon(w.name, w.melee ? '—' : (a ? a.mag : 0), w.melee ? '' : (a ? a.res : 0));
  }

  buildViewmodels() {
    const mk = (id) => {
      const g = new THREE.Group();
      const w = WEAPONS[id];
      const dark = new THREE.MeshLambertMaterial({ color: '#2b2f36' });
      const accent = new THREE.MeshLambertMaterial({ color: '#5c6672' });
      const add = (geo, mat, x, y, z) => {
        const m = new THREE.Mesh(geo, mat);
        m.position.set(x, y, z);
        g.add(m);
        return m;
      };
      const tip = new THREE.Object3D();
      if (id === 'knife') {
        add(new THREE.BoxGeometry(0.02, 0.1, 0.28), new THREE.MeshLambertMaterial({ color: '#cfd6dd' }), 0, 0.02, -0.1);
        add(new THREE.BoxGeometry(0.035, 0.05, 0.12), dark, 0, -0.03, 0.08);
        tip.position.set(0, 0, -0.25);
      } else if (w.cat === 'pistol') {
        const L = id === 'sheriff' ? 0.24 : 0.18;
        const col = id === 'ghost' ? '#3d4650' : '#2b2f36';
        add(new THREE.BoxGeometry(0.05, 0.09, L), new THREE.MeshLambertMaterial({ color: col }), 0, 0, -L / 2);
        add(new THREE.BoxGeometry(0.045, 0.1, 0.06), accent, 0, -0.07, 0.03);
        if (id === 'ghost') add(new THREE.CylinderGeometry(0.02, 0.02, 0.1, 8), dark, 0, 0.01, -L - 0.04).rotation.x = Math.PI / 2;
        tip.position.set(0, 0.01, -L - (id === 'ghost' ? 0.1 : 0));
      } else if (w.cat === 'shotgun') {
        const L = 0.55;
        add(new THREE.BoxGeometry(0.06, 0.09, L), new THREE.MeshLambertMaterial({ color: '#6b4a35' }), 0, 0, -L / 2 + 0.05);
        add(new THREE.CylinderGeometry(0.028, 0.028, L * 0.7, 8), dark, 0, 0.05, -L * 0.55).rotation.x = Math.PI / 2;
        add(new THREE.BoxGeometry(0.05, 0.11, 0.08), dark, 0, -0.08, 0.06);
        tip.position.set(0, 0.03, -L);
      } else if (w.cat === 'sniper') {
        const L = id === 'operator' ? 0.85 : 0.7;
        const col = id === 'operator' ? '#274156' : '#4a4438';
        add(new THREE.BoxGeometry(0.06, 0.09, L), new THREE.MeshLambertMaterial({ color: col }), 0, 0, -0.32);
        add(new THREE.CylinderGeometry(0.035, 0.035, 0.22, 8), dark, 0, 0.08, -0.15).rotation.x = Math.PI / 2;
        add(new THREE.BoxGeometry(0.05, 0.12, 0.1), dark, 0, -0.08, 0.05);
        tip.position.set(0, 0.01, -L + 0.1);
      } else if (w.cat === 'lmg') {
        const L = 0.65;
        add(new THREE.BoxGeometry(0.08, 0.12, L), new THREE.MeshLambertMaterial({ color: '#3c4433' }), 0, 0, -L / 2 + 0.05);
        add(new THREE.BoxGeometry(0.06, 0.14, 0.1), dark, 0, -0.1, 0.02);
        add(new THREE.BoxGeometry(0.04, 0.05, 0.2), dark, 0, -0.03, -L * 0.4);
        tip.position.set(0, 0.01, -L + 0.02);
      } else {
        // smg / rifle
        const L = w.cat === 'smg' ? 0.45 : 0.6;
        const col = id === 'vandal' ? '#5a3f35' : id === 'phantom' ? '#37474f' : id === 'bulldog' ? '#41503c' : id === 'guardian' ? '#4e4638' : '#3a4148';
        add(new THREE.BoxGeometry(0.055, 0.1, L), new THREE.MeshLambertMaterial({ color: col }), 0, 0, -L / 2 + 0.05);
        add(new THREE.BoxGeometry(0.05, 0.11, 0.08), dark, 0, -0.08, 0.06);
        add(new THREE.BoxGeometry(0.04, 0.05, 0.14), dark, 0, -0.05, -L * 0.35);
        tip.position.set(0, 0.01, -L + 0.02);
      }
      g.add(tip);
      g.userData.tip = tip;
      g.position.set(0.28, -0.26, -0.5);
      g.rotation.y = -0.06;
      g.visible = false;
      this.vmRoot.add(g);
      return g;
    };
    for (const id of Object.keys(WEAPONS)) this.viewmodels[id] = mk(id);
  }

  // руки от первого лица (рукав в цвет агента + кисть)
  buildHands() {
    const G = this.G;
    const col = (G.me && G.me.char && CHAR_COLORS[G.me.char]) || '#c85a3a';
    const sleeve = new THREE.MeshStandardMaterial({ color: col, roughness: 0.7 });
    const skin = new THREE.MeshStandardMaterial({ color: '#e0b48c', roughness: 0.75 });
    const hands = new THREE.Group();
    // правая рука — на рукояти
    const rArm = new THREE.Mesh(new THREE.CapsuleGeometry(0.055, 0.26, 4, 8), sleeve);
    rArm.position.set(0.3, -0.42, -0.28);
    rArm.rotation.set(-0.9, 0.1, 0.2);
    hands.add(rArm);
    const rHand = new THREE.Mesh(new THREE.SphereGeometry(0.06, 8, 8), skin);
    rHand.position.set(0.28, -0.29, -0.46);
    hands.add(rHand);
    // левая рука — поддержка ствола
    const lArm = new THREE.Mesh(new THREE.CapsuleGeometry(0.05, 0.28, 4, 8), sleeve);
    lArm.position.set(0.12, -0.4, -0.5);
    lArm.rotation.set(-1.15, -0.2, -0.35);
    hands.add(lArm);
    const lHand = new THREE.Mesh(new THREE.SphereGeometry(0.055, 8, 8), skin);
    lHand.position.set(0.2, -0.26, -0.66);
    hands.add(lHand);
    this.handsGroup = hands;
    this.vmRoot.add(hands);
  }
}

// цвета агентов для рукавов (дублируем, чтобы не тянуть весь CHARACTERS в раннем конструкторе)
const CHAR_COLORS = {
  artemiy: '#ff6b35', max: '#7ec8e3', vova: '#8f7ad1', sanek: '#e8c14d', denis: '#7a9b4e', ira: '#e8302c',
  fafik: '#3f5c8c', koniliy: '#8a5a2b',
};
