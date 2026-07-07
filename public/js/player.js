// Локальный игрок: движение с коллизиями, лестницы, камера с панчем отдачи
import * as THREE from './three.module.js';
import { MOVE, CHARACTERS } from './shared.js';

export class LocalPlayer {
  constructor(G) {
    this.G = G;
    this.pos = new THREE.Vector3(0, 0, 19);
    this.vel = new THREE.Vector3();
    this.yaw = 0;
    this.pitch = 0;
    this.crouch = false;
    this.walk = false;
    this.grounded = true;
    this.height = MOVE.HEIGHT;
    this.keys = {};
    this.sens = 0.0022;
    this.stepDist = 0;
    this.landBob = 0;
    // отдача: панч камеры (пружиной возвращается) + чуть уходит сам прицел
    this.punchPitch = 0;
    this.punchYaw = 0;

    window.addEventListener('keydown', (e) => { this.keys[e.code] = true; });
    window.addEventListener('keyup', (e) => { this.keys[e.code] = false; });
    window.addEventListener('blur', () => { this.keys = {}; });
    document.addEventListener('mousemove', (e) => {
      if (document.pointerLockElement && !G.chatOpen) {
        const sensMul = 1 - (G.aimT || 0) * 0.5;   // в прицеле чувствительность ниже
        this.yaw -= e.movementX * this.sens * sensMul;
        this.pitch -= e.movementY * this.sens * sensMul;
        this.pitch = Math.max(-1.55, Math.min(1.55, this.pitch));
      }
    });
    // ощущения камеры (вес)
    this.bobPhase = 0;
    this.rollZ = 0;
    this.camDip = 0;
  }

  teleport(pos, yaw) {
    this.pos.set(pos[0], pos[1] || 0, pos[2]);
    this.vel.set(0, 0, 0);
    if (yaw !== undefined) this.yaw = yaw;
    this.pitch = 0;
    this.punchPitch = 0; this.punchYaw = 0;
  }

  eyeY() { return this.pos.y + this.height - MOVE.EYE; }
  eyePos() { return new THREE.Vector3(this.pos.x, this.eyeY(), this.pos.z); }

  get speedFactor() {
    const G = this.G;
    const cs = CHARACTERS[G.me.char] || { speedMul: 1 };
    const t = performance.now() / 1000;
    let f = cs.speedMul * G.slowMul;
    if (t < G.boostUntil) f *= 1.4;          // Порыв Макса
    if (t < G.gallopUntil) f *= 1.5;         // Галоп Конилия
    if (t < G.banquetUntil) f *= 1.15;       // Финальный банкет Иры
    return f;
  }

  canControl() {
    const G = this.G;
    const t = performance.now() / 1000;
    return G.me.alive && !G.freeze && !G.pulled && t > G.stunnedUntil && !G.holdAction && !G.chatOpen;
  }

  // рывок Макса: свип с коллизиями
  dash(dist) {
    const dir = new THREE.Vector3();
    // в направлении движения; стоим — вперёд по взгляду
    let fx = 0, fz = 0;
    if (this.keys['KeyW']) fz -= 1;
    if (this.keys['KeyS']) fz += 1;
    if (this.keys['KeyA']) fx -= 1;
    if (this.keys['KeyD']) fx += 1;
    if (fx || fz) {
      dir.set(fx, 0, fz).normalize().applyAxisAngle(new THREE.Vector3(0, 1, 0), this.yaw);
    } else {
      dir.set(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
    }
    const steps = 10;
    for (let i = 0; i < steps; i++) {
      this.pos.x += dir.x * dist / steps;
      this.resolveAxis('x', MOVE.RADIUS);
      this.pos.z += dir.z * dist / steps;
      this.resolveAxis('z', MOVE.RADIUS);
    }
    this.vel.x = dir.x * 4; this.vel.z = dir.z * 4;
  }

  launch(v) {
    this.vel.y = v;
    this.grounded = false;
  }

  update(dt) {
    const G = this.G;

    // кокон/крюк: тянет к Денису
    if (G.pulled) {
      if (G.pulled.follow) {
        // кокон: постоянно ползём к текущей позиции Дениса
        const target = G.pulled.follow();
        const d = new THREE.Vector3(target.x - this.pos.x, 0, target.z - this.pos.z);
        const dist = d.length();
        if (dist > 1.6) {
          d.normalize();
          this.pos.addScaledVector(d, Math.min(dist - 1.5, 9 * dt));
        }
      } else {
        G.pulled.t += dt / G.pulled.dur;
        if (G.pulled.t >= 1) {
          this.pos.copy(G.pulled.to);
          G.pulled = null;
        } else {
          this.pos.lerpVectors(G.pulled.from, G.pulled.to, G.pulled.t);
        }
      }
      this.vel.set(0, 0, 0);
      this.applyCamera(dt);
      return;
    }

    this.crouch = !!this.keys['ControlLeft'] || !!this.keys['ControlRight'];
    this.walk = !!this.keys['ShiftLeft'];
    const targetH = this.crouch ? MOVE.CROUCH_HEIGHT : MOVE.HEIGHT;
    this.height += (targetH - this.height) * Math.min(1, dt * 12);

    const control = this.canControl();

    let fx = 0, fz = 0;
    if (control) {
      if (this.keys['KeyW']) fz -= 1;
      if (this.keys['KeyS']) fz += 1;
      if (this.keys['KeyA']) fx -= 1;
      if (this.keys['KeyD']) fx += 1;
    }
    const wish = new THREE.Vector3(fx, 0, fz);
    if (wish.lengthSq() > 0) {
      wish.normalize().applyAxisAngle(new THREE.Vector3(0, 1, 0), this.yaw);
    }
    let maxSpeed = this.crouch ? MOVE.CROUCH_SPEED : this.walk ? MOVE.WALK_SPEED : MOVE.RUN_SPEED;
    maxSpeed *= this.speedFactor;
    maxSpeed *= (1 - (G.aimT || 0) * 0.42);   // прицеливание замедляет

    const accel = this.grounded ? MOVE.ACCEL : MOVE.AIR_ACCEL;
    const targetV = wish.multiplyScalar(maxSpeed);
    this.vel.x += (targetV.x - this.vel.x) * Math.min(1, accel * dt);
    this.vel.z += (targetV.z - this.vel.z) * Math.min(1, accel * dt);

    if (control && this.keys['Space'] && this.grounded) {
      this.vel.y = MOVE.JUMP_VEL;
      this.grounded = false;
    }
    this.vel.y -= MOVE.GRAVITY * dt;

    this.moveCollide(dt);

    // шаги
    if (this.grounded && !this.walk && !this.crouch) {
      const hSpeed = Math.hypot(this.vel.x, this.vel.z);
      if (hSpeed > 3) {
        this.stepDist += hSpeed * dt;
        if (this.stepDist > 2.7) {
          this.stepDist = 0;
          G.sfx.footstep(0.4);
        }
      }
    }

    this.applyCamera(dt);
  }

  moveCollide(dt) {
    const aabbs = this.G.map.aabbs;
    const R = MOVE.RADIUS;

    const wasAir = !this.grounded;
    const fell = Math.max(0, -this.vel.y);   // скорость падения до приземления
    this.pos.y += this.vel.y * dt;
    this.grounded = false;
    if (this.pos.y <= 0) {
      this.pos.y = 0;
      if (this.vel.y < 0) { this.vel.y = 0; this.grounded = true; }
    }
    for (const b of aabbs) {
      if (this.pos.x + R > b.minX && this.pos.x - R < b.maxX &&
          this.pos.z + R > b.minZ && this.pos.z - R < b.maxZ) {
        if (this.vel.y <= 0 && this.pos.y < b.maxY && this.pos.y > b.maxY - 1.2) {
          this.pos.y = b.maxY;
          this.vel.y = 0;
          this.grounded = true;
        } else if (this.vel.y > 0 && this.pos.y + this.height > b.minY && this.pos.y < b.minY) {
          this.pos.y = b.minY - this.height;
          this.vel.y = 0;
        }
      }
    }
    if (wasAir && this.grounded) {
      // дип камеры по силе приземления + отдача в оружие
      this.landBob = Math.min(0.3, 0.05 + fell * 0.022);
      this.camDip = Math.max(this.camDip, this.landBob);
      this.G.sfx.footstep(Math.min(1, 0.5 + fell * 0.05));
    }

    this.pos.x += this.vel.x * dt;
    this.resolveAxis('x', R);
    this.pos.z += this.vel.z * dt;
    this.resolveAxis('z', R);

    const half = this.G.map.def.SIZE;
    this.pos.x = Math.max(-half.w / 2 + 1, Math.min(half.w / 2 - 1, this.pos.x));
    this.pos.z = Math.max(-half.d / 2 + 1, Math.min(half.d / 2 - 1, this.pos.z));
  }

  overlaps(b, R) {
    return this.pos.x + R > b.minX && this.pos.x - R < b.maxX &&
           this.pos.z + R > b.minZ && this.pos.z - R < b.maxZ &&
           this.pos.y + this.height > b.minY + 0.05 && this.pos.y < b.maxY - 0.05;
  }

  // есть ли место встать на высоте y
  headroomAt(y, R) {
    for (const b of this.G.map.aabbs) {
      if (this.pos.x + R > b.minX && this.pos.x - R < b.maxX &&
          this.pos.z + R > b.minZ && this.pos.z - R < b.maxZ &&
          y + this.height > b.minY + 0.05 && y < b.maxY - 0.05) return false;
    }
    return true;
  }

  resolveAxis(axis, R) {
    for (const b of this.G.map.aabbs) {
      if (!this.overlaps(b, R)) continue;
      // авто-подъём на низкие ступени
      const stepH = b.maxY - this.pos.y;
      if (this.grounded && stepH > 0 && stepH <= MOVE.STEP_UP && this.headroomAt(b.maxY, R)) {
        this.pos.y = b.maxY;
        continue;
      }
      if (axis === 'x') {
        const c = (b.minX + b.maxX) / 2;
        this.pos.x = this.pos.x < c ? b.minX - R : b.maxX + R;
        this.vel.x = 0;
      } else {
        const c = (b.minZ + b.maxZ) / 2;
        this.pos.z = this.pos.z < c ? b.minZ - R : b.maxZ + R;
        this.vel.z = 0;
      }
    }
  }

  applyCamera(dt) {
    const G = this.G;
    const cam = G.camera;
    const aimT = G.aimT || 0;

    // панч отдачи пружиной уходит в ноль
    const rec = Math.exp(-dt * 9);
    this.punchPitch *= rec;
    this.punchYaw *= rec;
    // дипы приземления восстанавливаются
    this.landBob = Math.max(0, this.landBob - dt * 0.9);
    this.camDip += (0 - this.camDip) * Math.min(1, dt * 8);

    const hSpeed = Math.hypot(this.vel.x, this.vel.z);
    const speedK = Math.min(1, hSpeed / MOVE.RUN_SPEED);

    // ===== боб головы при ходьбе (ощущение веса) =====
    const moving = this.grounded && hSpeed > 0.6;
    if (moving) this.bobPhase += dt * (6.2 + speedK * 4.2);
    const bobScale = (moving ? speedK : 0) * (this.crouch ? 0.5 : 1) * (this.walk ? 0.55 : 1) * (1 - aimT * 0.75);
    const bobY = Math.abs(Math.sin(this.bobPhase)) * 0.05 * bobScale;
    const bobSide = Math.sin(this.bobPhase) * 0.035 * bobScale;
    // дыхание в покое
    const idle = !moving && this.grounded ? Math.sin(performance.now() / 1000 * 1.8) * 0.006 : 0;

    // ===== крен камеры на стрейфе =====
    let strafeKey = 0;
    if (this.keys['KeyA']) strafeKey -= 1;
    if (this.keys['KeyD']) strafeKey += 1;
    const rollTarget = (-strafeKey * 0.022 * speedK + Math.sin(this.bobPhase) * 0.006 * bobScale) * (1 - aimT * 0.7);
    this.rollZ += (rollTarget - this.rollZ) * Math.min(1, dt * 7);

    // тряска (взрыв/оглушение)
    let sx = 0, sy = 0, sr = 0;
    if (G.shake > 0) {
      G.shake = Math.max(0, G.shake - dt * 2);
      sx = (Math.random() - 0.5) * G.shake * 0.05;
      sy = (Math.random() - 0.5) * G.shake * 0.05;
      sr = (Math.random() - 0.5) * G.shake * 0.01;
    }

    // боковой боб — вдоль оси «вправо» камеры
    const right = new THREE.Vector3(Math.cos(this.yaw), 0, -Math.sin(this.yaw));
    const px = this.pos.x + sx + right.x * bobSide;
    const pz = this.pos.z + right.z * bobSide;
    const py = this.eyeY() - this.landBob - this.camDip + bobY + idle + sy;

    cam.position.set(px, py, pz);
    cam.rotation.order = 'YXZ';
    cam.rotation.y = this.yaw + this.punchYaw;
    cam.rotation.x = this.pitch + this.punchPitch;
    cam.rotation.z = this.rollZ + sr;
  }
}
