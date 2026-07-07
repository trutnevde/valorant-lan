// Другие игроки: анимированный человечек с рига́ми (ходьба, руки, голова),
// костюмы под каждого агента, тени, хитбоксы, подсветка, кокон.
import * as THREE from './three.module.js';
import { CHARACTERS, MOVE, WEAPONS } from './shared.js';
import { tracerStyle } from './weapons.js';

function nameSprite(text, color, occlude) {
  const cv = document.createElement('canvas');
  cv.width = 256; cv.height = 64;
  const c = cv.getContext('2d');
  c.font = '700 34px Arial';
  c.textAlign = 'center';
  c.fillStyle = 'rgba(0,0,0,0.5)';
  c.fillRect(0, 8, 256, 48);
  c.fillStyle = color;
  c.fillText(text, 128, 44);
  // occlude=true → стены перекрывают ник (враги не светятся сквозь стены)
  const spr = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(cv), transparent: true, depthWrite: false, depthTest: !!occlude }));
  spr.renderOrder = occlude ? 1 : 990;
  spr.scale.set(1.7, 0.42, 1);
  return spr;
}

function labelTexture(text, bg, fg) {
  const cv = document.createElement('canvas');
  cv.width = 128; cv.height = 64;
  const c = cv.getContext('2d');
  c.fillStyle = bg; c.fillRect(0, 0, 128, 64);
  c.fillStyle = fg;
  c.font = '900 20px Arial'; c.textAlign = 'center'; c.textBaseline = 'middle';
  c.fillText(text, 64, 32);
  return new THREE.CanvasTexture(cv);
}

const std = (color, opts = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.72, metalness: 0.06, ...opts });

// Строит человекоподобную модель с рига́ми под конкретного агента.
// Возвращает { group, rig, hitMeshes, head }.
export function buildHumanoid(char, forLocalHands = false) {
  const cfg = CHARACTERS[char];
  const fat = char === 'denis';
  const skin = std('#e0b48c');
  const suit = std(cfg.color);
  const dark = std(cfg.darkColor);
  const boot = std('#20242b');

  const group = new THREE.Group();
  const body = new THREE.Group();       // анимируемый корпус (боб, присед, смерть)
  group.add(body);

  const hipsY = fat ? 0.86 : 0.9;
  const hips = new THREE.Group();
  hips.position.y = hipsY;
  body.add(hips);

  const mk = (geo, mat, x, y, z, part, pid) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z);
    m.castShadow = true;
    if (part) m.userData.part = part;
    m.geometry.computeBoundingSphere();
    return m;
  };

  // --- торс ---
  const torso = mk(new THREE.CapsuleGeometry(fat ? 0.34 : 0.26, fat ? 0.32 : 0.42, 5, 12), suit, 0, 0.28, 0, 'body');
  hips.add(torso);
  const chest = mk(new THREE.BoxGeometry(fat ? 0.66 : 0.52, 0.34, fat ? 0.5 : 0.34), suit, 0, 0.42, 0, 'body');
  hips.add(chest);
  // живот Дениса
  let belly = null;
  if (fat) {
    belly = mk(new THREE.SphereGeometry(0.4, 14, 12), suit, 0, 0.2, 0.14, 'body');
    hips.add(belly);
  }

  // --- голова ---
  const neck = mk(new THREE.CylinderGeometry(0.08, 0.1, 0.12, 8), skin, 0, 0.62, 0, 'head');
  hips.add(neck);
  const headPivot = new THREE.Group();
  headPivot.position.y = 0.7;
  hips.add(headPivot);
  const head = mk(new THREE.SphereGeometry(0.21, 16, 14), skin, 0, 0.12, 0, 'head');
  headPivot.add(head);
  // затылок/причёска — тёмная шапочка
  const hair = mk(new THREE.SphereGeometry(0.215, 14, 12, 0, Math.PI * 2, 0, Math.PI * 0.6), dark, 0, 0.13, 0.02, 'head');
  headPivot.add(hair);

  // --- руки ---
  const makeArm = (side) => {
    const shoulder = new THREE.Group();
    shoulder.position.set(side * (fat ? 0.42 : 0.32), 0.5, 0);
    hips.add(shoulder);
    const upper = mk(new THREE.CapsuleGeometry(0.075, 0.26, 4, 8), suit, 0, -0.14, 0, 'body');
    shoulder.add(upper);
    const elbow = new THREE.Group();
    elbow.position.y = -0.3;
    shoulder.add(elbow);
    const lower = mk(new THREE.CapsuleGeometry(0.07, 0.24, 4, 8), skin, 0, -0.13, 0, 'body');
    elbow.add(lower);
    const hand = mk(new THREE.SphereGeometry(0.08, 8, 8), skin, 0, -0.27, 0.02, 'body');
    elbow.add(hand);
    return { shoulder, elbow, hand };
  };
  const armL = makeArm(-1);
  const armR = makeArm(1);

  // --- ноги ---
  const makeLeg = (side) => {
    const hip = new THREE.Group();
    hip.position.set(side * 0.14, 0, 0);
    hips.add(hip);
    const upper = mk(new THREE.CapsuleGeometry(0.11, 0.34, 4, 8), dark, 0, -0.26, 0, 'body');
    hip.add(upper);
    const knee = new THREE.Group();
    knee.position.y = -0.46;
    hip.add(knee);
    const lower = mk(new THREE.CapsuleGeometry(0.095, 0.3, 4, 8), dark, 0, -0.2, 0, 'body');
    knee.add(lower);
    const foot = mk(new THREE.BoxGeometry(0.16, 0.1, 0.3), boot, 0, -0.4, 0.06, 'body');
    knee.add(foot);
    return { hip, knee };
  };
  const legL = makeLeg(-1);
  const legR = makeLeg(1);

  // «оружие» в правой руке (у чужих моделей — обозначение)
  const gun = mk(new THREE.BoxGeometry(0.08, 0.1, 0.55), std('#1b1e24'), 0, -0.24, -0.28, null);
  armR.elbow.add(gun);

  // ===== костюмы =====
  addCostume(char, cfg, { hips, headPivot, head, chest, armL, armR, group, std });

  const hitMeshes = [head, hair, neck, torso, chest, armL.hand, armR.hand];
  if (belly) hitMeshes.push(belly);
  // ноги как хитбоксы
  legL.hip.children.forEach(c => c.userData.part && hitMeshes.push(c));
  legR.hip.children.forEach(c => c.userData.part && hitMeshes.push(c));

  const rig = {
    body, hips, headPivot, armL, armR, legL, legR, torso, chest, gun,
    hipsY,
  };
  return { group, rig, hitMeshes, head };
}

function addCostume(char, cfg, ctx) {
  const { hips, headPivot, chest, armL, armR, group } = ctx;
  const S = (color, o) => std(color, o);

  if (char === 'artemiy') {
    // огненные полосы
    for (const s of [-1, 1]) {
      const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.5, 0.34), new THREE.MeshStandardMaterial({ color: 0xffaa33, emissive: 0xff5500, emissiveIntensity: 0.6, roughness: 0.4 }));
      stripe.position.set(s * 0.2, 0.4, -0.16);
      hips.add(stripe);
    }
    const crest = new THREE.Mesh(new THREE.ConeGeometry(0.1, 0.3, 6), new THREE.MeshStandardMaterial({ color: 0xff6622, emissive: 0xff3300, emissiveIntensity: 0.5 }));
    crest.position.set(0, 0.32, -0.02);
    headPivot.add(crest);
  } else if (char === 'max') {
    // визор + плавники за спиной
    const visor = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.08, 0.05), new THREE.MeshStandardMaterial({ color: 0x0af0ff, emissive: 0x00aaff, emissiveIntensity: 0.7, roughness: 0.2 }));
    visor.position.set(0, 0.12, -0.19);
    headPivot.add(visor);
    for (const s of [-1, 1]) {
      const fin = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.4, 0.18), S('#2aa8c8'));
      fin.position.set(s * 0.22, 0.42, 0.2);
      fin.rotation.x = -0.3;
      hips.add(fin);
    }
  } else if (char === 'vova') {
    // капюшон
    const hood = new THREE.Mesh(new THREE.SphereGeometry(0.28, 14, 12, 0, Math.PI * 2, 0, Math.PI * 0.62), S('#5a4a86'));
    hood.position.set(0, 0.14, 0.03);
    headPivot.add(hood);
    const orb = new THREE.Mesh(new THREE.SphereGeometry(0.08, 12, 12), new THREE.MeshStandardMaterial({ color: 0xb090ff, emissive: 0x8060ff, emissiveIntensity: 0.8 }));
    orb.position.set(0, 0.45, -0.12);
    hips.add(orb);
  } else if (char === 'sanek') {
    // каска + визор
    const helmet = new THREE.Mesh(new THREE.SphereGeometry(0.24, 14, 12, 0, Math.PI * 2, 0, Math.PI * 0.55), S('#f0c020', { metalness: 0.3 }));
    helmet.position.set(0, 0.16, 0);
    headPivot.add(helmet);
    const visor = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.1, 0.06), new THREE.MeshStandardMaterial({ color: 0x44ff88, emissive: 0x22aa44, emissiveIntensity: 0.6 }));
    visor.position.set(0, 0.1, -0.18);
    headPivot.add(visor);
    // ранец с инструментами
    const pack = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.34, 0.14), S('#6b5518'));
    pack.position.set(0, 0.4, 0.22);
    hips.add(pack);
  } else if (char === 'denis') {
    // мясницкий фартук + тесак
    const apron = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.5, 0.06), S('#8a2020'));
    apron.position.set(0, 0.25, -0.32);
    hips.add(apron);
    const cleaver = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.22, 0.16), S('#cfd6dd', { metalness: 0.6, roughness: 0.3 }));
    cleaver.position.set(0, -0.24, -0.1);
    armR.elbow.add(cleaver);
  } else if (char === 'ira') {
    // ===== KFC-костюм =====
    // красная куртка с белыми полосками
    for (const zoff of [0.1, -0.1]) {
      const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.06, 0.02), S('#f4f0e6'));
      stripe.position.set(0, 0.42, -(zoff + 0.17));
      hips.add(stripe);
    }
    const collar = new THREE.Mesh(new THREE.TorusGeometry(0.16, 0.04, 8, 16), S('#f4f0e6'));
    collar.position.set(0, 0.58, 0);
    collar.rotation.x = Math.PI / 2;
    hips.add(collar);
    // шлем-гребешок (куриный гребень из красных сегментов)
    const helmet = new THREE.Mesh(new THREE.SphereGeometry(0.235, 14, 12, 0, Math.PI * 2, 0, Math.PI * 0.6), S('#e8302c'));
    helmet.position.set(0, 0.15, 0);
    headPivot.add(helmet);
    for (let i = 0; i < 4; i++) {
      const seg = new THREE.Mesh(new THREE.SphereGeometry(0.06 - i * 0.008, 10, 8), new THREE.MeshStandardMaterial({ color: 0xff3b36, roughness: 0.5 }));
      seg.position.set(0, 0.34 - i * 0.01, -0.12 + i * 0.075);
      headPivot.add(seg);
    }
    // жёлтый клюв-козырёк
    const beak = new THREE.Mesh(new THREE.ConeGeometry(0.06, 0.14, 4), S('#ffcf3f'));
    beak.position.set(0, 0.08, -0.22);
    beak.rotation.x = Math.PI / 2;
    headPivot.add(beak);
    // перчатки-когти
    for (const arm of [armL, armR]) {
      const glove = new THREE.Mesh(new THREE.SphereGeometry(0.1, 10, 8), S('#e8302c'));
      glove.position.set(0, -0.27, 0.02);
      arm.elbow.add(glove);
      for (let c = -1; c <= 1; c++) {
        const claw = new THREE.Mesh(new THREE.ConeGeometry(0.02, 0.1, 4), S('#ffcf3f'));
        claw.position.set(c * 0.05, -0.34, -0.05);
        claw.rotation.x = -0.5;
        arm.elbow.add(claw);
      }
    }
    // рюкзак IRAFRIED
    const pack = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.4, 0.16), S('#e8302c'));
    pack.position.set(0, 0.4, 0.24);
    hips.add(pack);
    const logo = new THREE.Mesh(
      new THREE.PlaneGeometry(0.32, 0.16),
      new THREE.MeshBasicMaterial({ map: labelTexture('IRAFRIED', '#f4f0e6', '#e8302c') })
    );
    logo.position.set(0, 0.44, 0.325);
    hips.add(logo);
    // белый пояс
    const belt = new THREE.Mesh(new THREE.BoxGeometry(0.56, 0.08, 0.42), S('#f4f0e6'));
    belt.position.set(0, 0.06, 0);
    hips.add(belt);
  } else if (char === 'fafik') {
    // ===== батя в трениках =====
    // три белых лампаса на руках
    for (const arm of [armL, armR]) {
      for (let i = 0; i < 3; i++) {
        const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.24, 0.02), S('#e6e6e6'));
        stripe.position.set((i - 1) * 0.05, -0.14, -0.08);
        arm.shoulder.add(stripe);
      }
    }
    // лампасы на груди
    const zip = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.5, 0.03), S('#e6e6e6'));
    zip.position.set(0, 0.35, -0.18);
    hips.add(zip);
    // кепка
    const cap = new THREE.Mesh(new THREE.SphereGeometry(0.22, 12, 10, 0, Math.PI * 2, 0, Math.PI * 0.5), S('#22304d'));
    cap.position.set(0, 0.17, 0);
    headPivot.add(cap);
    const brim = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.03, 0.16), S('#22304d'));
    brim.position.set(0, 0.16, -0.18);
    headPivot.add(brim);
    // усы
    const mus = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.03, 0.04), S('#4a3a2a'));
    mus.position.set(0, 0.03, -0.2);
    headPivot.add(mus);
    // барсетка
    const bag = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.12, 0.05), S('#3a2a1a'));
    bag.position.set(0.22, 0.2, -0.12);
    hips.add(bag);
  } else if (char === 'koniliy') {
    // ===== наездник =====
    // ковбойская шляпа
    const hatTop = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.17, 0.2, 12), S('#4d3117'));
    hatTop.position.set(0, 0.24, 0);
    headPivot.add(hatTop);
    const hatBrim = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.34, 0.03, 16), S('#4d3117'));
    hatBrim.position.set(0, 0.15, 0);
    headPivot.add(hatBrim);
    // подкова на груди
    const shoe = new THREE.Mesh(new THREE.TorusGeometry(0.1, 0.03, 8, 16, Math.PI * 1.3), S('#d9b06a', { metalness: 0.5, roughness: 0.4 }));
    shoe.position.set(0, 0.4, -0.19);
    shoe.rotation.z = Math.PI;
    hips.add(shoe);
    // шейный платок
    const scarf = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.2, 4), S('#a83232'));
    scarf.position.set(0, 0.5, -0.1);
    scarf.rotation.x = -0.3;
    hips.add(scarf);
    // лассо на поясе
    const lasso = new THREE.Mesh(new THREE.TorusGeometry(0.08, 0.02, 6, 14), S('#8a6a3a'));
    lasso.position.set(0.24, 0.12, -0.05);
    lasso.rotation.x = Math.PI / 2;
    hips.add(lasso);
  }
}

export class RemotePlayer {
  constructor(G, pid, info) {
    this.G = G;
    this.pid = pid;
    this.char = info.char;
    this.name = info.name;
    this.ally = info.team === G.myTeam;
    this.buffer = [];
    this.alive = true;
    this.deadT = 0;
    this.lastPos = new THREE.Vector3();
    this.stepDist = 0;
    this.animPhase = 0;
    this.speedSmoothed = 0;
    this.revealedUntil = 0;
    this.fireKick = 0;
    this.hurtK = 0;
    this.build();
  }

  build() {
    const cfg = CHARACTERS[this.char];
    const { group, rig, hitMeshes, head } = buildHumanoid(this.char);
    for (const m of hitMeshes) m.userData.pid = this.pid;
    this.group = group;
    this.rig = rig;
    this.hitMeshes = hitMeshes;
    this.head = head;

    // ник врага перекрывается стенами (occlude) и виден только когда враг реально на виду
    const tag = nameSprite(this.name, this.ally ? '#0ac8b9' : '#ff4655', !this.ally);
    tag.position.y = 2.15;
    group.add(tag);
    this.tag = tag;

    // подсветка сквозь стены
    const hl = new THREE.Mesh(
      new THREE.BoxGeometry(0.9, 1.9, 0.7),
      new THREE.MeshBasicMaterial({ color: 0xffd24d, transparent: true, opacity: 0.4, depthTest: false, depthWrite: false, side: THREE.BackSide })
    );
    hl.position.y = 1.0;
    hl.visible = false;
    hl.renderOrder = 999;
    group.add(hl);
    this.highlight = hl;

    // кокон
    const cocoon = new THREE.Mesh(
      new THREE.SphereGeometry(0.85, 12, 10),
      std('#5a4632', { transparent: true, opacity: 0.85 })
    );
    cocoon.scale.y = 1.4;
    cocoon.position.y = 1.0;
    cocoon.visible = false;
    group.add(cocoon);
    this.cocoonMesh = cocoon;

    // шип за спиной у носителя (виден всем)
    const spikePack = new THREE.Group();
    const spBody = new THREE.Mesh(
      new THREE.CylinderGeometry(0.09, 0.13, 0.34, 8),
      std('#23272f', { metalness: 0.7, roughness: 0.35 })
    );
    spikePack.add(spBody);
    const spCoreMat = new THREE.MeshStandardMaterial({ color: 0xff3344, emissive: 0xff1133, emissiveIntensity: 1.6 });
    const spCore = new THREE.Mesh(new THREE.SphereGeometry(0.06, 10, 8), spCoreMat);
    spCore.position.y = 0.2;
    spikePack.add(spCore);
    spikePack.position.set(0, 1.3, 0.42); // спина (+Z)
    spikePack.rotation.x = 0.2;
    spikePack.visible = false;
    group.add(spikePack);
    this.spikePack = spikePack;
    this.spikeCoreMat = spCoreMat;

    this.G.scene.add(group);
  }

  onState(msg) {
    this.buffer.push({ rt: performance.now() / 1000, p: msg.p, yaw: msg.yaw, pitch: msg.pitch || 0, crouch: msg.crouch });
    if (this.buffer.length > 40) this.buffer.shift();
  }

  get pos() { return this.group.position; }
  eyePos() {
    return this.group.position.clone().add(new THREE.Vector3(0, (this.crouchK ? 1.2 : MOVE.HEIGHT) - MOVE.EYE, 0));
  }

  die() {
    this.alive = false;
    this.deadT = 0;
    this.cocoonMesh.visible = false;
    this.G.fx.blood(this.pos.clone().add(new THREE.Vector3(0, 1.2, 0)));
  }
  revive(pos) {
    this.alive = true;
    this.group.rotation.z = 0; this.group.rotation.x = 0;
    this.group.visible = true;
    if (pos) this.group.position.set(pos[0], pos[1] || 0, pos[2]);
    this.buffer = [];
  }
  resetRound(pos, yaw) {
    this.alive = true;
    this.group.rotation.z = 0; this.group.rotation.x = 0;
    this.group.visible = true;
    this.group.position.set(pos[0], pos[1] || 0, pos[2]);
    this.group.rotation.y = yaw || 0;
    this.buffer = [];
    this.cocoonMesh.visible = false;
    this.revealedUntil = 0;
  }
  dispose() { this.G.scene.remove(this.group); }

  update(dt) {
    const t = performance.now() / 1000;
    if (!this.alive) {
      this.deadT += dt;
      this.group.rotation.z = Math.min(Math.PI / 2, this.deadT * 4);
      this.group.position.y = Math.max(this.group.position.y - dt * 0.3, this.pos.y - 0.2);
      if (this.deadT > 3) this.group.visible = false;
      return;
    }
    const rt = t - 0.12;
    const buf = this.buffer;
    if (buf.length === 0) return;
    let a = buf[0], b = buf[buf.length - 1];
    for (let i = 0; i < buf.length - 1; i++) {
      if (buf[i].rt <= rt && buf[i + 1].rt >= rt) { a = buf[i]; b = buf[i + 1]; break; }
    }
    const span = Math.max(0.001, b.rt - a.rt);
    const k = Math.max(0, Math.min(1, (rt - a.rt) / span));
    const nx = a.p[0] + (b.p[0] - a.p[0]) * k;
    const ny = a.p[1] + (b.p[1] - a.p[1]) * k;
    const nz = a.p[2] + (b.p[2] - a.p[2]) * k;
    this.group.position.set(nx, ny, nz);

    let dy = b.yaw - a.yaw;
    while (dy > Math.PI) dy -= Math.PI * 2;
    while (dy < -Math.PI) dy += Math.PI * 2;
    this.group.rotation.y = a.yaw + dy * k;
    const pitch = a.pitch + (b.pitch - a.pitch) * k;
    this.rig.headPivot.rotation.x = -pitch * 0.55;

    // присед
    this.crouchK = b.crouch;
    const targetScale = b.crouch ? 0.72 : 1;
    this.rig.body.scale.y += (targetScale - this.rig.body.scale.y) * Math.min(1, dt * 10);

    // ходьба
    const moved = this.group.position.distanceTo(this.lastPos);
    const inst = moved / Math.max(dt, 0.001);
    this.speedSmoothed += (inst - this.speedSmoothed) * Math.min(1, dt * 10);
    this.lastPos.copy(this.group.position);
    const rig = this.rig;
    const walking = this.speedSmoothed > 0.6 && moved < 1;
    if (walking) {
      const spd = Math.min(this.speedSmoothed, 7);
      this.animPhase += dt * (6 + spd * 1.35);
      const amp = Math.min(1.05, 0.28 + spd * 0.115);
      const s = Math.sin(this.animPhase);
      const s2 = Math.sin(this.animPhase * 2);
      // ноги: мах бедра + сгиб колена (нога сгибается на заднем взмахе)
      rig.legL.hip.rotation.x = s * amp;
      rig.legR.hip.rotation.x = -s * amp;
      rig.legL.knee.rotation.x = Math.max(0, -s) * amp * 1.7 + 0.08;
      rig.legR.knee.rotation.x = Math.max(0, s) * amp * 1.7 + 0.08;
      // руки: левая машет широко, правая придерживает оружие
      rig.armL.shoulder.rotation.x = -s * amp * 0.95;
      rig.armL.shoulder.rotation.z = 0.1;
      rig.armR.shoulder.rotation.x = s * amp * 0.4 - 0.5;
      // корпус: подскок, боковое качание, скрутка, наклон вперёд на бегу
      rig.body.position.y = Math.abs(s2) * 0.055 * amp;
      rig.body.rotation.z = -s * 0.06;
      rig.body.rotation.y = -s * 0.09;
      rig.hips.rotation.x = 0.05 + spd * 0.013;
      rig.headPivot.rotation.z = s * 0.035;
    } else {
      // возврат к стойке + дыхание
      const damp = Math.min(1, dt * 8);
      for (const r of [rig.legL.hip, rig.legR.hip, rig.legL.knee, rig.legR.knee, rig.armL.shoulder]) r.rotation.x *= (1 - damp);
      rig.armL.shoulder.rotation.z *= (1 - damp);
      rig.armR.shoulder.rotation.x += (-0.5 - rig.armR.shoulder.rotation.x) * damp;
      rig.body.rotation.z *= (1 - damp);
      rig.body.rotation.y *= (1 - damp);
      rig.hips.rotation.x += (0 - rig.hips.rotation.x) * damp;
      rig.headPivot.rotation.z *= (1 - damp);
      const breathe = Math.sin(t * 2.2) * 0.013;
      rig.body.position.y += (breathe - rig.body.position.y) * damp;
    }

    // вздрагивание от попадания
    if (this.hurtK > 0) {
      this.hurtK = Math.max(0, this.hurtK - dt * 5);
      rig.body.rotation.x -= this.hurtK * 0.09;
      rig.headPivot.rotation.z += this.hurtK * 0.12 * Math.sin(t * 40);
      rig.armL.shoulder.rotation.x -= this.hurtK * 0.25;
    }

    // отдача при стрельбе — руки/корпус дёргаются
    if (this.fireKick > 0) {
      this.fireKick = Math.max(0, this.fireKick - dt * 6);
      rig.armR.shoulder.rotation.x -= this.fireKick * 0.5;
      rig.armL.shoulder.rotation.x -= this.fireKick * 0.3;
      rig.body.rotation.x = -this.fireKick * 0.05;
    } else {
      rig.body.rotation.x += (0 - rig.body.rotation.x) * Math.min(1, dt * 8);
    }

    // шаги (звук)
    this.stepDist += walking ? moved : 0;
    if (this.stepDist > 2.4) {
      this.stepDist = 0;
      if (!b.crouch) {
        const d = this.G.player.pos.distanceTo(this.pos);
        if (d < 30) this.G.sfx.footstep(Math.max(0.1, 1 - d / 30));
      }
    }

    // ник: союзник — всегда рядом; враг — только когда реально виден (не сквозь стены)
    const near = this.G.player.pos.distanceTo(this.pos) < 42;
    if (this.G.clonedIds && this.G.clonedIds.has(this.pid)) {
      this.tag.visible = false;
    } else if (this.ally) {
      this.tag.visible = near;
    } else {
      const spotted = t < (this.G.spottedUntil.get(this.pid) || 0) || t < this.G.xrayUntil || t < (this.G.revealed.get(this.pid) || 0) || t < this.revealedUntil;
      // дым перекрывает ник (спрайты не пишут depth — проверяем вручную)
      let smokeBlocked = false;
      if (spotted && near) {
        const cam = this.G.camera.position, ex = this.pos.x, ey = this.pos.y + 1.6, ez = this.pos.z;
        for (const sm of this.G.abilities.smokes) {
          if (t >= sm.until) continue;
          // отрезок камера→враг против сферы дыма
          const ax = cam.x, ay = cam.y, az = cam.z;
          const bx = ex - ax, by = ey - ay, bz = ez - az;
          const cx = sm.pos.x - ax, cy = sm.pos.y - ay, cz = sm.pos.z - az;
          const len2 = bx * bx + by * by + bz * bz || 1;
          let k = (cx * bx + cy * by + cz * bz) / len2; k = Math.max(0, Math.min(1, k));
          const px = ax + bx * k - sm.pos.x, py = ay + by * k - sm.pos.y, pz = az + bz * k - sm.pos.z;
          if (px * px + py * py + pz * pz <= sm.r * sm.r) { smokeBlocked = true; break; }
        }
      }
      this.tag.visible = near && spotted && !smokeBlocked;
    }

    // подсветка (рентген/сигналка/дозор), но банкет скрывает союзника противника
    let show = false;
    if (!this.ally) {
      const revealed = t < this.G.xrayUntil || t < this.revealedUntil;
      if (revealed && !this.hiddenByBanquet(t)) show = true;
    }
    this.highlight.visible = show;

    this.cocoonMesh.visible = this.G.cocoonedId === this.pid;
    if (this.cocoonMesh.visible) this.cocoonMesh.rotation.y += dt * 3;

    // шип за спиной у текущего носителя
    this.spikePack.visible = this.G.spikeCarrier === this.pid;
    if (this.spikePack.visible) this.spikeCoreMat.emissiveIntensity = 1.2 + Math.sin(t * 4) * 0.6;
  }

  // враг внутри своего командного банкета не подсвечивается детектом
  hiddenByBanquet(t) {
    for (const bq of this.G.banquets) {
      if (t < bq.until && bq.team !== this.G.myTeam && this.pos.distanceTo(bq.pos) < bq.r) return true;
    }
    return false;
  }

  flinch() { this.hurtK = 1; }

  onShoot(msg) {
    this.fireKick = 1; // дёрнуть руки модели
    const o = new THREE.Vector3(...msg.o);
    const d = new THREE.Vector3(...msg.d);
    const ray = new THREE.Raycaster(o, d, 0, 200);
    const hits = ray.intersectObjects(this.G.map.solids, false);
    const end = hits[0] ? hits[0].point : o.clone().addScaledVector(d, 120);
    const ts = tracerStyle(WEAPONS[msg.w]);
    this.G.fx.tracer(o, end, this.ally ? 0xb0ffe0 : ts.color, ts.r, ts.life);
    const mp = o.clone().addScaledVector(d, 0.5);
    this.G.fx.muzzle(mp, d);
    const right = new THREE.Vector3().crossVectors(d, new THREE.Vector3(0, 1, 0)).normalize();
    this.G.fx.casing(mp, right);
    const dist = this.G.player.pos.distanceTo(o);
    const w = msg.w === 'knife' ? 'knife' : msg.w;
    this.G.sfx.shot(w, Math.max(0.12, 1 - dist / 55));
    if (!this.ally) this.G.spottedUntil.set(this.pid, performance.now() / 1000 + 1.5);
  }
}
