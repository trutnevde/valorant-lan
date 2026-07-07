// Визуальные эффекты: трассеры, вспышки, партиклы, огонь, шип, взрыв, KFC-хилки
import * as THREE from './three.module.js';

const std = (color, opts = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.7, metalness: 0.05, ...opts });

const STAMPEDE_WIDTH_VIS = 5;

// призрачный конь для табуна Конилия
function makeHorse() {
  const g = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({ color: 0xdcc9a0, emissive: 0x6a5a2a, emissiveIntensity: 0.4, transparent: true, opacity: 0.78, roughness: 0.6 });
  const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.32, 0.9, 5, 10), mat);
  body.rotation.x = Math.PI / 2;
  body.position.y = 1.0;
  g.add(body);
  const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.22, 0.6, 8), mat);
  neck.position.set(0, 1.35, -0.6);
  neck.rotation.x = -0.7;
  g.add(neck);
  const head = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.24, 0.5), mat);
  head.position.set(0, 1.6, -0.95);
  g.add(head);
  const legs = [];
  for (const lx of [-0.18, 0.18]) for (const lz of [-0.45, 0.45]) {
    const leg = new THREE.Mesh(new THREE.CapsuleGeometry(0.07, 0.7, 3, 6), mat);
    leg.position.set(lx, 0.55, lz);
    g.add(leg);
    legs.push(leg);
  }
  // хвост
  const tail = new THREE.Mesh(new THREE.ConeGeometry(0.12, 0.6, 6), mat);
  tail.position.set(0, 1.1, 0.7);
  tail.rotation.x = 0.8;
  g.add(tail);
  return { group: g, legs };
}

function makeSoftTexture(inner, outer) {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 64;
  const c = cv.getContext('2d');
  const g = c.createRadialGradient(32, 32, 2, 32, 32, 30);
  g.addColorStop(0, inner);
  g.addColorStop(0.4, outer);
  g.addColorStop(1, 'rgba(0,0,0,0)');
  c.fillStyle = g;
  c.fillRect(0, 0, 64, 64);
  return new THREE.CanvasTexture(cv);
}

function makeStarTexture() {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 64;
  const c = cv.getContext('2d');
  c.translate(32, 32);
  const g = c.createRadialGradient(0, 0, 1, 0, 0, 16);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.5, 'rgba(255,225,140,0.9)');
  g.addColorStop(1, 'rgba(255,150,40,0)');
  c.fillStyle = g;
  c.beginPath();
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    const r = i % 2 === 0 ? 30 : 11;
    c.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  c.closePath();
  c.fill();
  return new THREE.CanvasTexture(cv);
}

export class Effects {
  constructor(scene) {
    this.scene = scene;
    this.items = []; // { update(dt)=>bool, dispose() }
    this.sparkTex = makeSoftTexture('rgba(255,255,255,1)', 'rgba(255,220,150,0.6)');
    this.flameTex = makeSoftTexture('rgba(255,240,180,1)', 'rgba(255,110,30,0.7)');
    this.rotTex = makeSoftTexture('rgba(190,255,140,0.9)', 'rgba(80,140,40,0.5)');
    this.steamTex = makeSoftTexture('rgba(255,255,255,0.95)', 'rgba(210,255,220,0.4)');
    this.muzzleTex = makeStarTexture();
    this.bloodTex = makeSoftTexture('rgba(220,40,40,1)', 'rgba(120,10,10,0.6)');
  }

  add(item) { this.items.push(item); return item; }

  update(dt) {
    for (let i = this.items.length - 1; i >= 0; i--) {
      if (!this.items[i].update(dt)) {
        this.items[i].dispose();
        this.items.splice(i, 1);
      }
    }
  }

  // ===== базовые =====
  // светящийся «шнур»; r/life задают калибр (снайперка — толстый паровой след)
  tracer(from, to, color = 0xffe0a0, r = 0.018, lifeMax = 0.07) {
    const dir = to.clone().sub(from);
    const len = dir.length();
    if (len < 0.05) return;
    const geo = new THREE.CylinderGeometry(r, r, len, 5, 1, true);
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.copy(from).addScaledVector(dir, 0.5);
    mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.clone().normalize());
    this.scene.add(mesh);
    let life = lifeMax;
    this.add({
      update: (dt) => { life -= dt; mat.opacity = Math.max(0, life / lifeMax) * 0.9; return life > 0; },
      dispose: () => { this.scene.remove(mesh); geo.dispose(); mat.dispose(); },
    });
  }

  // гильза: вылетает вправо-вверх, крутится, падает
  casing(pos, rightDir) {
    if (!this._casingGeo) {
      this._casingGeo = new THREE.BoxGeometry(0.016, 0.016, 0.042);
      this._casingMat = new THREE.MeshStandardMaterial({ color: 0xc9a544, metalness: 0.65, roughness: 0.35 });
    }
    const m = new THREE.Mesh(this._casingGeo, this._casingMat);
    m.position.copy(pos);
    this.scene.add(m);
    const vel = rightDir.clone().multiplyScalar(1.4 + Math.random() * 0.8);
    vel.y = 1.6 + Math.random() * 0.7;
    const ang = new THREE.Vector3(Math.random() * 14, Math.random() * 14, Math.random() * 14);
    let life = 0.9;
    this.add({
      update: (dt) => {
        life -= dt;
        vel.y -= 9.8 * dt;
        m.position.addScaledVector(vel, dt);
        m.rotation.x += ang.x * dt; m.rotation.y += ang.y * dt; m.rotation.z += ang.z * dt;
        return life > 0;
      },
      dispose: () => this.scene.remove(m),
    });
  }

  // дымок из ствола после выстрела
  smokePuff(pos) {
    const spr = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.steamTex, color: 0xb8b8b8, transparent: true, opacity: 0.32, depthWrite: false }));
    spr.position.copy(pos);
    spr.scale.setScalar(0.14);
    this.scene.add(spr);
    let t = 0.5;
    this.add({
      update: (dt) => {
        t -= dt;
        spr.position.y += dt * 0.5;
        spr.scale.multiplyScalar(1 + dt * 2.6);
        spr.material.opacity = Math.max(0, t / 0.5) * 0.32;
        return t > 0;
      },
      dispose: () => this.scene.remove(spr),
    });
  }

  light(pos, color, intensity, dist, life) {
    const l = new THREE.PointLight(color, intensity, dist);
    l.position.copy(pos);
    this.scene.add(l);
    let t = life;
    this.add({
      update: (dt) => { t -= dt; l.intensity = intensity * Math.max(0, t / life); return t > 0; },
      dispose: () => this.scene.remove(l),
    });
  }

  // яркий дульный сполох
  muzzle(pos, dir) {
    this.light(pos, 0xffcc66, 4, 7, 0.06);
    const spr = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.muzzleTex, color: 0xfff0c0, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
    spr.position.copy(pos);
    spr.scale.setScalar(0.55 + Math.random() * 0.2);
    spr.material.rotation = Math.random() * Math.PI;
    this.scene.add(spr);
    let t = 0.06;
    this.add({
      update: (dt) => { t -= dt; spr.material.opacity = Math.max(0, t / 0.06); spr.scale.multiplyScalar(1 + dt * 3); return t > 0; },
      dispose: () => this.scene.remove(spr),
    });
    if (dir) this.burst(pos.clone().addScaledVector(dir, 0.3), { n: 3, color: 0xffcc77, speed: 2, life: 0.2, size: 0.06, gravity: 2 });
  }

  burst(pos, { n = 10, color = 0xffffff, speed = 4, life = 0.4, size = 0.12, gravity = 8, tex = null } = {}) {
    const positions = new Float32Array(n * 3);
    const vels = [];
    for (let i = 0; i < n; i++) {
      positions[i * 3] = pos.x; positions[i * 3 + 1] = pos.y; positions[i * 3 + 2] = pos.z;
      const a = Math.random() * Math.PI * 2, b = Math.random() * Math.PI - Math.PI / 2;
      const s = speed * (0.4 + Math.random() * 0.6);
      vels.push(new THREE.Vector3(Math.cos(a) * Math.cos(b) * s, Math.sin(b) * s + speed * 0.4, Math.sin(a) * Math.cos(b) * s));
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const mat = new THREE.PointsMaterial({
      color, size, map: tex || this.sparkTex, transparent: true,
      depthWrite: false, blending: THREE.AdditiveBlending,
    });
    const pts = new THREE.Points(geo, mat);
    this.scene.add(pts);
    let t = life;
    this.add({
      update: (dt) => {
        t -= dt;
        const arr = geo.attributes.position.array;
        for (let i = 0; i < n; i++) {
          vels[i].y -= gravity * dt;
          arr[i * 3] += vels[i].x * dt;
          arr[i * 3 + 1] += vels[i].y * dt;
          arr[i * 3 + 2] += vels[i].z * dt;
        }
        geo.attributes.position.needsUpdate = true;
        mat.opacity = Math.max(0, t / life);
        return t > 0;
      },
      dispose: () => { this.scene.remove(pts); geo.dispose(); mat.dispose(); },
    });
  }

  impact(pos, normal) {
    this.burst(pos, { n: 7, color: 0xffddaa, speed: 3.5, life: 0.28, size: 0.07 });
    this.burst(pos, { n: 4, color: 0x888888, speed: 0.8, life: 0.5, size: 0.14, gravity: -1 }); // пыль
    // выщербина
    const dec = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.sparkTex, color: 0x222222, transparent: true, opacity: 0.5, depthWrite: false }));
    dec.position.copy(pos);
    dec.scale.setScalar(0.12);
    this.scene.add(dec);
    let t = 0.9;
    this.add({ update: (dt) => { t -= dt; dec.material.opacity = Math.min(0.5, t); return t > 0; }, dispose: () => this.scene.remove(dec) });
  }
  blood(pos) {
    this.burst(pos, { n: 16, color: 0xcc1122, speed: 3, life: 0.5, size: 0.15, gravity: 12, tex: this.bloodTex });
    this.burst(pos, { n: 6, color: 0x8a0d18, speed: 1.2, life: 0.7, size: 0.2, gravity: 8, tex: this.bloodTex });
  }

  // ===== огонь (зоны Артемия) =====
  fire(getPoints, radius = 0.9) {
    // getPoints() -> массив Vector3 — очаги пламени
    const sprites = [];
    const group = new THREE.Group();
    for (const p of getPoints()) {
      const spr = new THREE.Sprite(new THREE.SpriteMaterial({
        map: this.flameTex, color: 0xff8833, transparent: true,
        depthWrite: false, blending: THREE.AdditiveBlending,
      }));
      spr.position.copy(p).add(new THREE.Vector3(0, 0.5, 0));
      spr.scale.setScalar(radius * (1.3 + Math.random() * 0.8));
      spr.userData.base = spr.scale.x;
      spr.userData.ph = Math.random() * 10;
      group.add(spr);
      sprites.push(spr);
    }
    const light = new THREE.PointLight(0xff7722, 2.5, 12);
    const center = getPoints()[Math.floor(getPoints().length / 2)] || new THREE.Vector3();
    light.position.copy(center).add(new THREE.Vector3(0, 1, 0));
    group.add(light);
    this.scene.add(group);
    let alive = true, t = 0;
    const handle = {
      update: (dt) => {
        t += dt;
        for (const s of sprites) {
          const f = 1 + 0.25 * Math.sin(t * 13 + s.userData.ph);
          s.scale.setScalar(s.userData.base * f);
          s.position.y = 0.5 + 0.15 * Math.sin(t * 9 + s.userData.ph * 2);
        }
        light.intensity = 2.2 + Math.sin(t * 17) * 0.6;
        return alive;
      },
      dispose: () => this.scene.remove(group),
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }

  fireZoneFx(pos, r) {
    const pts = [new THREE.Vector3(pos.x, 0, pos.z)];
    const n = 9;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2;
      pts.push(new THREE.Vector3(pos.x + Math.cos(a) * r * 0.7, 0, pos.z + Math.sin(a) * r * 0.7));
    }
    return this.fire(() => pts, 1.1);
  }

  fireWallFx(a, b) {
    const pts = [];
    const len = a.distanceTo(b);
    const n = Math.max(4, Math.round(len / 1.1));
    for (let i = 0; i <= n; i++) pts.push(a.clone().lerp(b, i / n));
    return this.fire(() => pts, 1.0);
  }

  // ===== разное =====
  glowOrb(color = 0xffffff, size = 0.3) {
    const spr = new THREE.Sprite(new THREE.SpriteMaterial({
      map: this.sparkTex, color, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    }));
    spr.scale.setScalar(size * 3);
    this.scene.add(spr);
    return spr;
  }

  ring(pos, color = 0xffffff, maxR = 3) {
    const geo = new THREE.RingGeometry(0.1, 0.25, 32);
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, side: THREE.DoubleSide, depthWrite: false });
    const m = new THREE.Mesh(geo, mat);
    m.rotation.x = -Math.PI / 2;
    m.position.copy(pos).setY(0.05);
    this.scene.add(m);
    let t = 0.35;
    this.add({
      update: (dt) => {
        t -= dt;
        const k = 1 - t / 0.35;
        m.scale.setScalar(1 + k * maxR * 3);
        mat.opacity = Math.max(0, t / 0.35);
        return t > 0;
      },
      dispose: () => { this.scene.remove(m); geo.dispose(); mat.dispose(); },
    });
  }

  // Шип: чёрный металл, пульсирующее энерго-ядро, вращающиеся кольца, три плавника.
  // variant: 'planted' — стоит и заряжается; 'dropped' — лежит на боку, тускло тлеет
  spikeMesh(pos, variant = 'planted') {
    const g = new THREE.Group();
    const metal = new THREE.MeshStandardMaterial({ color: 0x23272f, metalness: 0.75, roughness: 0.35 });
    const finMat = new THREE.MeshStandardMaterial({ color: 0x3c4454, metalness: 0.6, roughness: 0.4 });

    // основание-опора
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.4, 0.14, 8), metal);
    base.position.y = 0.07;
    base.castShadow = true;
    g.add(base);
    // восьмигранный корпус
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.24, 0.5, 8), metal);
    body.position.y = 0.4;
    body.castShadow = true;
    g.add(body);
    // три плавника
    for (let i = 0; i < 3; i++) {
      const fin = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.55, 0.18), finMat);
      const a = (i / 3) * Math.PI * 2;
      fin.position.set(Math.cos(a) * 0.24, 0.35, Math.sin(a) * 0.24);
      fin.rotation.y = -a;
      fin.rotation.z = 0.16;
      fin.castShadow = true;
      g.add(fin);
    }
    // энерго-ядро
    const coreMat = new THREE.MeshStandardMaterial({ color: 0xff3344, emissive: 0xff1133, emissiveIntensity: 2, roughness: 0.25 });
    const core = new THREE.Mesh(new THREE.SphereGeometry(0.11, 14, 12), coreMat);
    core.position.y = 0.72;
    g.add(core);
    // ореол вокруг ядра
    const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.sparkTex, color: 0xff3344, transparent: true, opacity: 0.5, depthWrite: false, blending: THREE.AdditiveBlending }));
    halo.position.y = 0.72;
    halo.scale.setScalar(0.55);
    g.add(halo);
    // два вращающихся кольца
    const ringMat = new THREE.MeshStandardMaterial({ color: 0x8a93a6, metalness: 0.7, roughness: 0.3, emissive: 0xff2233, emissiveIntensity: 0.25 });
    const ring1 = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.02, 8, 28), ringMat);
    ring1.position.y = 0.72;
    g.add(ring1);
    const ring2 = new THREE.Mesh(new THREE.TorusGeometry(0.22, 0.016, 8, 24), ringMat);
    ring2.position.y = 0.72;
    g.add(ring2);
    const light = new THREE.PointLight(0xff2233, 0.5, 9);
    light.position.y = 0.9;
    g.add(light);

    g.position.copy(pos);
    if (variant === 'dropped') {
      g.rotation.z = 1.25; // лежит на боку
      g.position.y += 0.18;
    }
    this.scene.add(g);

    let t = 0, alive = true;
    const handle = {
      blinkRate: 1,
      update: (dt) => {
        t += dt;
        if (variant === 'dropped') {
          // тлеет медленно, ждёт подбора
          const p = 0.5 + 0.3 * Math.sin(t * 3);
          coreMat.emissiveIntensity = p * 1.2;
          halo.material.opacity = p * 0.35;
          light.intensity = p * 0.8;
        } else {
          ring1.rotation.x += dt * 1.6;
          ring1.rotation.y += dt * 0.9;
          ring2.rotation.y -= dt * 2.2;
          ring2.rotation.z += dt * 1.2;
          const on = (t % handle.blinkRate) < handle.blinkRate * 0.35;
          coreMat.emissiveIntensity = on ? 3.2 : 0.7;
          halo.material.opacity = on ? 0.75 : 0.2;
          halo.scale.setScalar(on ? 0.8 : 0.5);
          light.intensity = on ? 2.5 : 0.4;
          core.scale.setScalar(1 + (on ? 0.12 : 0));
          // редкие искры при быстром бипе (последние секунды)
          if (on && handle.blinkRate < 0.3 && Math.random() < dt * 20) {
            this.burst(g.position.clone().add(new THREE.Vector3(0, 0.75, 0)), { n: 4, color: 0xff4455, speed: 1.5, life: 0.3, size: 0.08 });
          }
        }
        return alive;
      },
      dispose: () => this.scene.remove(g),
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }

  explosion(pos) {
    this.burst(pos, { n: 60, color: 0xff8833, speed: 14, life: 0.9, size: 0.5, gravity: 6, tex: this.flameTex });
    this.burst(pos, { n: 30, color: 0xffffff, speed: 20, life: 0.5, size: 0.25 });
    this.light(pos.clone().add(new THREE.Vector3(0, 1, 0)), 0xffaa55, 30, 60, 0.8);
    this.ring(pos, 0xffaa55, 10);
  }

  ultMarkerFx(pos) {
    const geo = new THREE.CylinderGeometry(0.5, 0.5, 3, 16, 1, true);
    const mat = new THREE.MeshBasicMaterial({
      color: 0xff7722, transparent: true, opacity: 0.4,
      side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending,
    });
    const m = new THREE.Mesh(geo, mat);
    m.position.set(pos.x, 1.5, pos.z);
    this.scene.add(m);
    let alive = true, t = 0;
    const handle = {
      update: (dt) => {
        t += dt;
        mat.opacity = 0.3 + 0.15 * Math.sin(t * 6);
        m.rotation.y += dt * 2;
        return alive;
      },
      dispose: () => { this.scene.remove(m); geo.dispose(); mat.dispose(); },
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }

  // ===== дым (обычный серый или зелёная вонючка Дениса) =====
  smoke(pos, r, dur, stink = false) {
    const mat = new THREE.MeshLambertMaterial({
      color: stink ? 0x6d8f4a : 0x9fb0bd, transparent: true, opacity: 0,
    });
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, 20, 16), mat);
    m.position.set(pos.x, Math.max(pos.y, 0) + r * 0.55, pos.z);
    this.scene.add(m);
    let t = 0;
    this.add({
      update: (dt) => {
        t += dt;
        if (t < 0.4) mat.opacity = (t / 0.4) * 0.96;
        else if (t > dur - 0.8) mat.opacity = Math.max(0, (dur - t) / 0.8) * 0.96;
        else mat.opacity = 0.96;
        m.rotation.y += dt * 0.2;
        return t < dur;
      },
      dispose: () => { this.scene.remove(m); mat.dispose(); },
    });
    return m;
  }

  // ===== орбитальный удар Вовы =====
  orbital(pos, delay, dur, r) {
    // предупреждающее кольцо, затем столб огня
    const ringGeo = new THREE.RingGeometry(r - 0.3, r, 40);
    const ringMat = new THREE.MeshBasicMaterial({ color: 0xff3322, transparent: true, side: THREE.DoubleSide, depthWrite: false });
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.set(pos.x, 0.05, pos.z);
    this.scene.add(ring);

    const beamMat = new THREE.MeshBasicMaterial({
      color: 0xff6633, transparent: true, opacity: 0,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
    });
    const beam = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.9, r, 60, 24, 1, true), beamMat);
    beam.position.set(pos.x, 30, pos.z);
    this.scene.add(beam);
    const light = new THREE.PointLight(0xff5522, 0, 40);
    light.position.set(pos.x, 3, pos.z);
    this.scene.add(light);

    let t = 0;
    this.add({
      update: (dt) => {
        t += dt;
        if (t < delay) {
          ringMat.opacity = 0.4 + 0.4 * Math.sin(t * 18);
        } else if (t < delay + dur) {
          ringMat.opacity = 0.9;
          beamMat.opacity = 0.55 + 0.2 * Math.sin(t * 30);
          light.intensity = 12 + Math.sin(t * 25) * 4;
          if (Math.random() < dt * 30) {
            this.burst(new THREE.Vector3(pos.x + (Math.random() - 0.5) * r * 1.5, 0.5, pos.z + (Math.random() - 0.5) * r * 1.5),
              { n: 6, color: 0xff8844, speed: 6, life: 0.4, size: 0.3, tex: this.flameTex });
          }
        } else return false;
        return true;
      },
      dispose: () => {
        this.scene.remove(ring); this.scene.remove(beam); this.scene.remove(light);
        ringGeo.dispose(); ringMat.dispose(); beamMat.dispose();
      },
    });
  }

  // ===== турель Санька =====
  turret(pos) {
    const g = new THREE.Group();
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.4, 0.35, 8), new THREE.MeshLambertMaterial({ color: '#8a8455' }));
    base.position.y = 0.18;
    g.add(base);
    const headM = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.25, 0.5), new THREE.MeshLambertMaterial({ color: '#e8c14d' }));
    headM.position.y = 0.5;
    g.add(headM);
    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.45, 6), new THREE.MeshLambertMaterial({ color: '#2b2f36' }));
    barrel.rotation.x = Math.PI / 2;
    barrel.position.set(0, 0.5, 0.35);
    g.add(barrel);
    const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.05), new THREE.MeshBasicMaterial({ color: 0x33ff66 }));
    lamp.position.set(0, 0.68, 0);
    g.add(lamp);
    g.position.copy(pos);
    this.scene.add(g);
    let alive = true, t = 0;
    const handle = {
      group: g,
      head: headM,
      update: (dt) => { t += dt; lamp.material.color.setHex((t % 1) < 0.5 ? 0x33ff66 : 0x116622); return alive; },
      dispose: () => this.scene.remove(g),
      kill: () => { alive = false; },
      aimAt: (target) => {
        headM.lookAt(new THREE.Vector3(target.x, g.position.y + 0.5, target.z).sub(g.position).add(g.position));
      },
    };
    this.add(handle);
    return handle;
  }

  // ===== сигналка =====
  trap(pos, color = 0xffd24d) {
    const geo = new THREE.RingGeometry(0.2, 0.35, 24);
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.7, side: THREE.DoubleSide, depthWrite: false });
    const m = new THREE.Mesh(geo, mat);
    m.rotation.x = -Math.PI / 2;
    m.position.set(pos.x, 0.06, pos.z);
    this.scene.add(m);
    let alive = true, t = 0;
    const handle = {
      update: (dt) => { t += dt; mat.opacity = 0.4 + 0.3 * Math.sin(t * 4); m.scale.setScalar(1 + 0.15 * Math.sin(t * 4)); return alive; },
      dispose: () => { this.scene.remove(m); geo.dispose(); mat.dispose(); },
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }

  // ===== лужа (кислота Санька / тухлятина Дениса) =====
  puddle(pos, r, dur, color = 0x88cc33) {
    const geo = new THREE.CircleGeometry(r, 28);
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.45, depthWrite: false });
    const m = new THREE.Mesh(geo, mat);
    m.rotation.x = -Math.PI / 2;
    m.position.set(pos.x, 0.04, pos.z);
    this.scene.add(m);
    let t = 0;
    const handle = {
      update: (dt) => {
        t += dt;
        mat.opacity = 0.35 + 0.12 * Math.sin(t * 6);
        if (Math.random() < dt * 6) {
          this.burst(new THREE.Vector3(pos.x + (Math.random() - 0.5) * r, 0.15, pos.z + (Math.random() - 0.5) * r),
            { n: 3, color, speed: 1, life: 0.5, size: 0.12, gravity: -1 });
        }
        return t < dur;
      },
      dispose: () => { this.scene.remove(m); geo.dispose(); mat.dispose(); },
    };
    this.add(handle);
    return handle;
  }

  // ===== KFC-эффекты Иры =====
  // поднимающийся целебный пар
  steam(getPos, r, dur, color = 0xd8ffe0) {
    const group = new THREE.Group();
    const sprites = [];
    for (let i = 0; i < 14; i++) {
      const spr = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.steamTex, color, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending }));
      spr.userData = { ang: Math.random() * Math.PI * 2, rad: Math.random() * r * 0.8, y: Math.random() * 1.5, sp: 0.4 + Math.random() * 0.5, ph: Math.random() * 6 };
      spr.scale.setScalar(0.6 + Math.random() * 0.6);
      group.add(spr); sprites.push(spr);
    }
    this.scene.add(group);
    let t = 0, alive = true;
    const handle = {
      update: (dt) => {
        t += dt;
        const p = getPos();
        for (const s of sprites) {
          s.userData.y += dt * s.userData.sp;
          if (s.userData.y > 2.2) s.userData.y = 0;
          const wob = Math.sin(t * 2 + s.userData.ph) * 0.3;
          s.position.set(p.x + Math.cos(s.userData.ang) * (s.userData.rad + wob), s.userData.y, p.z + Math.sin(s.userData.ang) * (s.userData.rad + wob));
          const fade = t < dur - 1 ? 1 : Math.max(0, (dur - t));
          s.material.opacity = 0.5 * (1 - s.userData.y / 2.4) * fade;
        }
        return alive && t < dur;
      },
      dispose: () => this.scene.remove(group),
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }

  // всплеск лечения (зелёные искры + крестик)
  healBurst(pos) {
    this.burst(pos, { n: 18, color: 0x66ff99, speed: 3, life: 0.6, size: 0.14, gravity: -3, tex: this.steamTex });
    this.ring(pos, 0x66ff99, 4);
    this.light(pos.clone().add(new THREE.Vector3(0, 1, 0)), 0x66ff88, 3, 12, 0.4);
  }

  // криспи-стена из панировки: полупрозрачная золотистая панель с «крошкой»
  crispyWall(a, b, height = 2.6) {
    const group = new THREE.Group();
    const mid = a.clone().lerp(b, 0.5);
    const len = a.distanceTo(b);
    const panel = new THREE.Mesh(
      new THREE.BoxGeometry(len, height, 0.25),
      new THREE.MeshStandardMaterial({ color: 0xd89a3c, roughness: 0.9, transparent: true, opacity: 0.62, emissive: 0x6b4a10, emissiveIntensity: 0.25 })
    );
    panel.position.set(mid.x, height / 2, mid.z);
    panel.lookAt(new THREE.Vector3(b.x, height / 2, b.z));
    panel.rotation.y += Math.PI / 2;
    group.add(panel);
    // крошки-выступы
    for (let i = 0; i < Math.round(len * 3); i++) {
      const crumb = new THREE.Mesh(new THREE.DodecahedronGeometry(0.06 + Math.random() * 0.05), new THREE.MeshStandardMaterial({ color: 0xe8b24a, roughness: 1 }));
      const p = a.clone().lerp(b, Math.random());
      crumb.position.set(p.x, 0.2 + Math.random() * (height - 0.3), p.z);
      group.add(crumb);
    }
    this.scene.add(group);
    let alive = true, t = 0;
    const handle = {
      update: (dt) => { t += dt; panel.material.opacity = 0.55 + 0.08 * Math.sin(t * 3); return alive; },
      dispose: () => this.scene.remove(group),
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }

  // цыплёнок-разведчик (механический)
  chickenScout() {
    const g = new THREE.Group();
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.16, 12, 10), std('#f4f0e6'));
    body.scale.set(1, 0.9, 1.1);
    body.castShadow = true;
    g.add(body);
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.1, 10, 8), std('#f4f0e6'));
    head.position.set(0, 0.16, -0.12);
    g.add(head);
    const comb = new THREE.Mesh(new THREE.SphereGeometry(0.05, 8, 6), std('#e8302c'));
    comb.position.set(0, 0.26, -0.12);
    g.add(comb);
    const beak = new THREE.Mesh(new THREE.ConeGeometry(0.03, 0.08, 4), std('#ffcf3f'));
    beak.position.set(0, 0.15, -0.22); beak.rotation.x = -Math.PI / 2;
    g.add(beak);
    for (const s of [-1, 1]) {
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.14, 5), std('#ffcf3f'));
      leg.position.set(s * 0.06, -0.14, 0);
      g.add(leg);
    }
    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.03, 8, 8), new THREE.MeshStandardMaterial({ color: 0x33ff66, emissive: 0x22cc44, emissiveIntensity: 0.9 }));
    eye.position.set(0.05, 0.18, -0.19);
    g.add(eye);
    this.scene.add(g);
    let alive = true, t = 0;
    const handle = {
      group: g, legL: g.children[5], legR: g.children[6],
      update: (dt) => {
        t += dt;
        // семенит ножками + подпрыгивает
        g.children[5].rotation.x = Math.sin(t * 22) * 0.6;
        g.children[6].rotation.x = -Math.sin(t * 22) * 0.6;
        g.position.y = g.userData.baseY || 0;
        return alive;
      },
      dispose: () => this.scene.remove(g),
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }

  // табун призрачных коней — ульта Конилия
  stampede(from, to) {
    const dir = to.clone().sub(from); dir.y = 0;
    const len = dir.length() || 1;
    dir.normalize();
    const perp = new THREE.Vector3(-dir.z, 0, dir.x);
    const yaw = Math.atan2(-dir.x, -dir.z);
    const horses = [];
    const N = 7;
    for (let i = 0; i < N; i++) {
      const h = makeHorse();
      const lane = (i - (N - 1) / 2) * (STAMPEDE_WIDTH_VIS / N);
      const lead = -Math.random() * 3;
      h.group.position.copy(from).addScaledVector(perp, lane).addScaledVector(dir, lead);
      h.group.rotation.y = yaw;
      this.scene.add(h.group);
      horses.push({ h, lane, prog: lead, ph: Math.random() * 6 });
    }
    const dust = new THREE.PointLight(0xd9b06a, 0, 20);
    dust.position.copy(from).add(new THREE.Vector3(0, 1, 0));
    this.scene.add(dust);
    let t = 0;
    const speed = 26;
    const total = len + 4;
    this.add({
      update: (dt) => {
        t += dt;
        let anyOn = false;
        for (const ho of horses) {
          ho.prog += speed * dt;
          ho.ph += dt * 18;
          if (ho.prog < 0 || ho.prog > total) { ho.h.group.visible = false; continue; }
          anyOn = true;
          ho.h.group.visible = true;
          ho.h.group.position.copy(from).addScaledVector(perp, ho.lane).addScaledVector(dir, ho.prog);
          ho.h.group.position.y = Math.abs(Math.sin(ho.ph)) * 0.25;
          // ноги-галоп
          ho.h.legs.forEach((lg, k) => { lg.rotation.x = Math.sin(ho.ph + k * 1.5) * 0.9; });
          if (Math.random() < dt * 20) this.burst(ho.h.group.position.clone(), { n: 2, color: 0xcaa870, speed: 1.5, life: 0.5, size: 0.14, gravity: 1 });
        }
        dust.position.copy(from).addScaledVector(dir, Math.min(total, t * speed));
        dust.intensity = anyOn ? 2 : 0;
        return anyOn && t < 4;
      },
      dispose: () => { for (const ho of horses) this.scene.remove(ho.h.group); this.scene.remove(dust); },
    });
  }

  // гигантское ведро KFC — ульта «Финальный банкет»
  banquetBucket(pos, r) {
    const g = new THREE.Group();
    const bucketMat = new THREE.MeshStandardMaterial({ color: 0xe8302c, roughness: 0.6, transparent: true, opacity: 0.32, side: THREE.DoubleSide, emissive: 0x551008, emissiveIntensity: 0.3 });
    const bucket = new THREE.Mesh(new THREE.CylinderGeometry(r, r * 0.82, 4.2, 28, 1, true), bucketMat);
    bucket.position.y = 2.1;
    g.add(bucket);
    // белые полосы
    for (let i = 0; i < 10; i++) {
      const stripe = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.99, r * 0.82 * 0.99, 4.2, 3, 1, true, (i / 10) * Math.PI * 2, Math.PI / 10),
        new THREE.MeshStandardMaterial({ color: 0xf4f0e6, side: THREE.DoubleSide, transparent: true, opacity: 0.3 }));
      stripe.position.y = 2.1;
      g.add(stripe);
    }
    // ободок и логотип
    const rim = new THREE.Mesh(new THREE.TorusGeometry(r, 0.12, 8, 28), std('#f4f0e6', { transparent: true, opacity: 0.6 }));
    rim.position.y = 4.2; rim.rotation.x = Math.PI / 2;
    g.add(rim);
    const base = new THREE.Mesh(new THREE.RingGeometry(0.2, r, 32), new THREE.MeshBasicMaterial({ color: 0xe8302c, transparent: true, opacity: 0.18, side: THREE.DoubleSide, depthWrite: false }));
    base.rotation.x = -Math.PI / 2; base.position.y = 0.05;
    g.add(base);
    const light = new THREE.PointLight(0xffd24d, 1.5, r * 3);
    light.position.y = 2.5;
    g.add(light);
    g.position.set(pos.x, 0, pos.z);
    this.scene.add(g);
    // пар внутри
    const steam = this.steam(() => new THREE.Vector3(pos.x, 0, pos.z), r * 0.7, 999, 0xfff0d0);
    let alive = true, t = 0;
    const handle = {
      update: (dt) => { t += dt; bucket.rotation.y += dt * 0.15; light.intensity = 1.3 + Math.sin(t * 4) * 0.3; return alive; },
      dispose: () => { this.scene.remove(g); steam.kill(); },
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }

  rotAuraFx(getPos, radius) {
    const spr = new THREE.Sprite(new THREE.SpriteMaterial({
      map: this.rotTex, color: 0x88cc44, transparent: true, opacity: 0.35,
      depthWrite: false, blending: THREE.AdditiveBlending,
    }));
    spr.scale.setScalar(radius * 2.2);
    this.scene.add(spr);
    let alive = true, t = 0;
    const handle = {
      update: (dt) => {
        t += dt;
        const p = getPos();
        spr.position.set(p.x, p.y + 1, p.z);
        spr.material.opacity = 0.3 + 0.1 * Math.sin(t * 5);
        return alive;
      },
      dispose: () => this.scene.remove(spr),
      kill: () => { alive = false; },
    };
    this.add(handle);
    return handle;
  }
}
