// Звук: реальные CC0-сэмплы (выстрелы/шаги/перезарядка/взрыв) + синтез для всего остального.
// Всё локально/офлайн. Позиционный 3D: мировые звуки идут через PannerNode (HRTF) → слышно направление/дистанцию.

// CC0-сэмплы (OpenGameArt, public domain), лежат локально в assets/sfx/.
// Нет файла или ещё не догрузился → тихий фолбэк на синтез (ничего не ломается).
const SAMPLES = {
  gun_pistol: 'assets/sfx/gun_pistol.wav',
  gun_magnum: 'assets/sfx/gun_magnum.wav',
  gun_heavy: 'assets/sfx/gun_heavy.wav',
  gun_rifle: 'assets/sfx/gun_rifle.wav',
  reload1: 'assets/sfx/reload1.wav',
  reload2: 'assets/sfx/reload2.wav',
  step1: 'assets/sfx/step1.ogg', step2: 'assets/sfx/step2.ogg', step3: 'assets/sfx/step3.ogg',
  step4: 'assets/sfx/step4.ogg', step5: 'assets/sfx/step5.ogg', step6: 'assets/sfx/step6.ogg',
  explosion: 'assets/sfx/explosion.ogg',
  // фидбек/скиллы/шип/UI — реальные записи вместо синтезированных «пик»
  whoosh: 'assets/sfx/whoosh.ogg', whoosh2: 'assets/sfx/whoosh2.ogg',
  hit: 'assets/sfx/hit.ogg', ting: 'assets/sfx/ting.ogg', hurt: 'assets/sfx/hurt.ogg',
  slam: 'assets/sfx/slam.ogg', pop: 'assets/sfx/pop.ogg', buff: 'assets/sfx/buff.ogg',
  confirm: 'assets/sfx/confirm.ogg', fail: 'assets/sfx/fail.ogg',
  energy: 'assets/sfx/energy.ogg', zap: 'assets/sfx/zap.ogg',
  beep: 'assets/sfx/beep.ogg', clunk: 'assets/sfx/clunk.ogg', boom: 'assets/sfx/boom.ogg',
  ui_click: 'assets/sfx/ui_click.wav', ui_confirm: 'assets/sfx/ui_confirm.wav',
};
// какой ствол каким сэмплом звучит (нож — остаётся синтезом)
const SHOT_SAMPLE = {
  classic: 'gun_pistol', ghost: 'gun_pistol', frenzy: 'gun_pistol',
  stinger: 'gun_pistol', spectre: 'gun_pistol',
  sheriff: 'gun_magnum', guardian: 'gun_magnum', marshal: 'gun_magnum',
  bucky: 'gun_heavy', judge: 'gun_heavy', shorty: 'gun_heavy', operator: 'gun_heavy', outlaw: 'gun_heavy',
  ares: 'gun_rifle', odin: 'gun_rifle', bulldog: 'gun_rifle', phantom: 'gun_rifle', vandal: 'gun_rifle',
};
const SHOT_VOL = { gun_pistol: 0.5, gun_magnum: 0.62, gun_heavy: 0.72, gun_rifle: 0.55 };
// длина проигрываемого окна выстрела (сек): у записей длинный хвост/очередь — режем, чтобы автоогонь был чётким
const SHOT_DUR = { gun_pistol: 0.42, gun_magnum: 0.6, gun_heavy: 0.9, gun_rifle: 0.3 };

export class Sfx {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.rotNode = null;
    this._dest = null;   // текущий выход для tone/noise (панер при spatial, иначе master)
  }
  init() {
    if (!this.ctx) {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.master = this.ctx.createGain();
      this.master.gain.value = 0.5;
      // мягкий лимитер, чтобы залпы не клиппили
      const comp = this.ctx.createDynamicsCompressor();
      comp.threshold.value = -10; comp.knee.value = 20; comp.ratio.value = 4; comp.attack.value = 0.003; comp.release.value = 0.2;
      this.master.connect(comp); comp.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
    this._loadSamples();
  }
  get t0() { return this.ctx ? this.ctx.currentTime : 0; }
  get dest() { return this._dest || this.master; }

  // асинхронно грузим и декодируем CC0-сэмплы (один раз). Пока не готовы — синтез-фолбэк.
  _loadSamples() {
    if (this._samplesStarted || !this.ctx) return;
    this._samplesStarted = true;
    this.buffers = {};
    for (const [name, url] of Object.entries(SAMPLES)) {
      fetch(url)
        .then(r => (r.ok ? r.arrayBuffer() : Promise.reject(new Error('404'))))
        .then(ab => this.ctx.decodeAudioData(ab))
        .then(buf => { this.buffers[name] = buf; })
        .catch(() => { /* нет файла — останется синтез */ });
    }
  }
  // проиграть загруженный сэмпл через текущий выход (this.dest — 3D-панер при spatial). false = не готов.
  // maxDur>0 — обрезать до этого окна с быстрым фейдом (для крупных записей выстрела).
  playBuf(name, { vol = 1, rate = 1, delay = 0, maxDur = 0 } = {}) {
    if (!this.ctx || !this.buffers || !this.buffers[name]) return false;
    const t = this.t0 + delay;
    const src = this.ctx.createBufferSource();
    src.buffer = this.buffers[name];
    src.playbackRate.value = rate;
    const g = this.ctx.createGain();
    g.gain.value = vol;
    src.connect(g); g.connect(this.dest);
    src.start(t);
    if (maxDur > 0) {
      g.gain.setValueAtTime(vol, t + maxDur);
      g.gain.linearRampToValueAtTime(0.0001, t + maxDur + 0.05);
      src.stop(t + maxDur + 0.07);
    }
    return true;
  }

  // позиция/ориентация слушателя = камера (вызывать каждый кадр)
  setListener(cam) {
    if (!this.ctx) return;
    cam.updateMatrixWorld();
    const L = this.ctx.listener;
    const p = cam.position;
    // направление камеры из мировой матрицы
    const m = cam.matrixWorld.elements;
    const fx = -m[8], fy = -m[9], fz = -m[10];
    const ux = m[4], uy = m[5], uz = m[6];
    if (L.positionX) {
      const t = this.ctx.currentTime, k = 0.02;
      L.positionX.linearRampToValueAtTime(p.x, t + k);
      L.positionY.linearRampToValueAtTime(p.y, t + k);
      L.positionZ.linearRampToValueAtTime(p.z, t + k);
      L.forwardX.value = fx; L.forwardY.value = fy; L.forwardZ.value = fz;
      L.upX.value = ux; L.upY.value = uy; L.upZ.value = uz;
    } else if (L.setPosition) {
      L.setPosition(p.x, p.y, p.z);
      L.setOrientation(fx, fy, fz, ux, uy, uz);
    }
  }

  // выполнить fn() так, чтобы её звуки шли из точки pos (мировой 3D)
  spatial(pos, fn) {
    if (!this.ctx) { return; }
    const g = this.ctx.createGain();
    const pan = this.ctx.createPanner();
    pan.panningModel = 'HRTF'; pan.distanceModel = 'inverse';
    pan.refDistance = 5; pan.maxDistance = 70; pan.rolloffFactor = 1.3;
    const x = pos[0] || 0, y = (pos[1] != null ? pos[1] : 1.2), z = pos[2] || 0;
    if (pan.positionX) { pan.positionX.value = x; pan.positionY.value = y; pan.positionZ.value = z; }
    else pan.setPosition(x, y, z);
    g.connect(pan); pan.connect(this.master);
    const prev = this._dest;
    this._dest = g;
    try { fn(); } finally { this._dest = prev; }
  }

  tone({ f = 440, f2 = 0, type = 'square', dur = 0.1, vol = 0.25, delay = 0 }) {
    if (!this.ctx) return;
    const t = this.t0 + delay;
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(f, t);
    if (f2) o.frequency.exponentialRampToValueAtTime(Math.max(1, f2), t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g); g.connect(this.dest);
    o.start(t); o.stop(t + dur + 0.02);
  }
  noise({ dur = 0.1, vol = 0.25, fc = 1200, q = 1, type = 'lowpass', fc2 = 0, delay = 0 }) {
    if (!this.ctx) return;
    const t = this.t0 + delay;
    const len = Math.max(1, Math.floor(this.ctx.sampleRate * dur));
    const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const flt = this.ctx.createBiquadFilter();
    flt.type = type; flt.frequency.setValueAtTime(fc, t); flt.Q.value = q;
    if (fc2) flt.frequency.exponentialRampToValueAtTime(Math.max(10, fc2), t + dur);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(flt); flt.connect(g); g.connect(this.dest);
    src.start(t);
  }

  // ===== богатые примитивы для оружия =====
  // резкий транзиент-щелчок (порох)
  crack({ vol = 0.5, fc = 2500, dur = 0.03, delay = 0, drive = 8 }) {
    if (!this.ctx) return;
    const t = this.t0 + delay;
    const len = Math.max(1, Math.floor(this.ctx.sampleRate * dur));
    const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) { const e = 1 - i / len; d[i] = Math.tanh((Math.random() * 2 - 1) * drive) * e * e; }
    const src = this.ctx.createBufferSource(); src.buffer = buf;
    const flt = this.ctx.createBiquadFilter(); flt.type = 'highpass'; flt.frequency.value = fc; flt.Q.value = 0.6;
    const g = this.ctx.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(flt); flt.connect(g); g.connect(this.dest); src.start(t);
  }
  // низкочастотное «тело» выстрела с искажением
  body({ f = 140, f2 = 45, vol = 0.35, dur = 0.1, delay = 0, type = 'sawtooth' }) {
    if (!this.ctx) return;
    const t = this.t0 + delay;
    const o = this.ctx.createOscillator(); o.type = type;
    o.frequency.setValueAtTime(f, t); o.frequency.exponentialRampToValueAtTime(Math.max(1, f2), t + dur);
    const ws = this.ctx.createWaveShaper(); const c = new Float32Array(256);
    for (let i = 0; i < 256; i++) { const x = i / 128 - 1; c[i] = Math.tanh(x * 3); } ws.curve = c;
    const g = this.ctx.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(ws); ws.connect(g); g.connect(this.dest); o.start(t); o.stop(t + dur + 0.02);
  }
  // ===== оружие: транзиент + тело + хвост, всё с джиттером =====
  shot(w, vol = 1) {
    // сначала — настоящая запись выстрела (нож остаётся синтезом)
    if (w !== 'knife') {
      const name = SHOT_SAMPLE[w] || 'gun_rifle';
      if (this.playBuf(name, { vol: (SHOT_VOL[name] || 0.55) * vol, rate: 0.92 + Math.random() * 0.16, maxDur: SHOT_DUR[name] || 0.35 })) return;
    }
    const j = 0.9 + Math.random() * 0.2;   // джиттер тона на каждый выстрел (фолбэк-синтез)
    switch (w) {
      case 'knife':
        this.crack({ vol: 0.16 * vol, fc: 3500 * j, dur: 0.05, drive: 3 });
        this.tone({ f: 700 * j, f2: 300, dur: 0.05, vol: 0.08 * vol, type: 'triangle' });
        break;
      case 'classic':
        this.crack({ vol: 0.4 * vol, fc: 2400 * j, dur: 0.03 });
        this.body({ f: 170 * j, f2: 55, dur: 0.06, vol: 0.22 * vol });
        this.noise({ dur: 0.08, vol: 0.18 * vol, fc: 1800 * j, fc2: 350 });
        break;
      case 'ghost':
        this.crack({ vol: 0.22 * vol, fc: 3200 * j, dur: 0.02, drive: 4 }); // с глушителем — «пфф»
        this.noise({ dur: 0.09, vol: 0.22 * vol, fc: 900 * j, fc2: 200, type: 'bandpass' });
        this.body({ f: 130, f2: 60, dur: 0.05, vol: 0.1 * vol });
        break;
      case 'sheriff':
        this.crack({ vol: 0.6 * vol, fc: 1900 * j, dur: 0.04, drive: 12 });
        this.body({ f: 110 * j, f2: 35, dur: 0.16, vol: 0.45 * vol });
        this.noise({ dur: 0.22, vol: 0.28 * vol, fc: 1200, fc2: 90 }); // хвост
        break;
      case 'stinger':
        this.crack({ vol: 0.32 * vol, fc: 3000 * j, dur: 0.02 });
        this.body({ f: 220 * j, f2: 110, dur: 0.04, vol: 0.13 * vol, type: 'square' });
        break;
      case 'spectre':
        this.crack({ vol: 0.26 * vol, fc: 2600 * j, dur: 0.025, drive: 4 });
        this.noise({ dur: 0.06, vol: 0.16 * vol, fc: 1400 * j, fc2: 400, type: 'bandpass' });
        break;
      case 'ares':
        this.crack({ vol: 0.42 * vol, fc: 2100 * j, dur: 0.03, drive: 10 });
        this.body({ f: 130 * j, f2: 55, dur: 0.08, vol: 0.3 * vol });
        this.noise({ dur: 0.1, vol: 0.2 * vol, fc: 1600, fc2: 260 });
        break;
      case 'bucky': case 'judge':
        this.crack({ vol: 0.55 * vol, fc: 1400 * j, dur: 0.05, drive: 14 });
        this.body({ f: 90 * j, f2: 30, dur: 0.18, vol: 0.4 * vol });
        this.noise({ dur: 0.26, vol: 0.3 * vol, fc: 900, fc2: 70 }); // раскатистый хвост
        break;
      case 'bulldog': case 'guardian':
        this.crack({ vol: 0.5 * vol, fc: 2000 * j, dur: 0.035, drive: 11 });
        this.body({ f: 145 * j, f2: 48, dur: 0.1, vol: 0.34 * vol });
        this.noise({ dur: 0.14, vol: 0.2 * vol, fc: 1700, fc2: 220 });
        break;
      case 'phantom':
        this.crack({ vol: 0.34 * vol, fc: 2600 * j, dur: 0.025, drive: 5 }); // глушитель — суше
        this.body({ f: 150 * j, f2: 60, dur: 0.07, vol: 0.24 * vol });
        this.noise({ dur: 0.08, vol: 0.14 * vol, fc: 1300, fc2: 400, type: 'bandpass' });
        break;
      case 'marshal':
        this.crack({ vol: 0.7 * vol, fc: 1700 * j, dur: 0.05, drive: 16 });
        this.body({ f: 95 * j, f2: 32, dur: 0.24, vol: 0.5 * vol });
        this.noise({ dur: 0.4, vol: 0.32 * vol, fc: 1100, fc2: 70 });
        break;
      case 'operator':
        this.crack({ vol: 0.85 * vol, fc: 1500 * j, dur: 0.06, drive: 20 });
        this.body({ f: 80 * j, f2: 26, dur: 0.32, vol: 0.6 * vol });
        this.noise({ dur: 0.5, vol: 0.4 * vol, fc: 900, fc2: 55 }); // долгий раскат
        this.tone({ f: 55, f2: 30, dur: 0.4, vol: 0.25 * vol, type: 'sine', delay: 0.02 });
        break;
      default: // vandal и прочие винтовки
        this.crack({ vol: 0.5 * vol, fc: 2200 * j, dur: 0.03, drive: 12 });
        this.body({ f: 155 * j, f2: 52, dur: 0.09, vol: 0.32 * vol });
        this.noise({ dur: 0.12, vol: 0.2 * vol, fc: 1800, fc2: 240 });
    }
  }
  dry() { if (this.playBuf('ui_click', { vol: 0.3, rate: 0.75 })) return; this.crack({ vol: 0.1, fc: 4000, dur: 0.02, drive: 2 }); this.tone({ f: 1100, dur: 0.02, vol: 0.08, type: 'square' }); }
  reload() {
    if (this.playBuf(Math.random() < 0.5 ? 'reload1' : 'reload2', { vol: 0.85 })) return;
    // фолбэк-синтез: защёлка магазина — три разных клика с разным тембром
    this.crack({ vol: 0.18, fc: 3200, dur: 0.03, drive: 3 });
    this.tone({ f: 380, f2: 260, dur: 0.04, vol: 0.12, type: 'square', delay: 0.05 });
    this.crack({ vol: 0.22, fc: 2600, dur: 0.04, drive: 4, delay: 0.4 });
    this.tone({ f: 520, f2: 700, dur: 0.05, vol: 0.13, type: 'square', delay: 0.7 });
    this.crack({ vol: 0.14, fc: 4000, dur: 0.02, delay: 0.75 });
  }
  footstep(vol = 0.5, surface = 0) {
    if (this.playBuf('step' + (1 + Math.floor(Math.random() * 6)), { vol: 0.95 * vol, rate: 0.9 + Math.random() * 0.2 })) return;
    // фолбэк-синтез: поверхности + рандом высоты + два слоя (пятка/носок)
    const base = 300 + Math.random() * 260 + surface * 200;
    this.noise({ dur: 0.05, vol: 0.16 * vol, fc: base, q: 2.2 });
    this.noise({ dur: 0.035, vol: 0.09 * vol, fc: base * 2.4, q: 1.5, type: 'bandpass', delay: 0.02 });
  }

  // ===== фидбек =====
  hitmarker() { if (this.playBuf('hit', { vol: 0.5, rate: 0.95 + Math.random() * 0.1 })) return; this.tone({ f: 1400, f2: 900, dur: 0.05, vol: 0.2, type: 'square' }); }
  headshot() { if (this.playBuf('ting', { vol: 0.6 })) return; this.tone({ f: 1800, f2: 2400, dur: 0.09, vol: 0.3, type: 'square' }); }
  hurt() { if (this.playBuf('hurt', { vol: 0.7 })) return; this.tone({ f: 220, f2: 110, dur: 0.12, vol: 0.3, type: 'sawtooth' }); this.noise({ dur: 0.08, vol: 0.2, fc: 800 }); }
  kill() { if (this.playBuf('confirm', { vol: 0.5 })) return; this.tone({ f: 600, dur: 0.08, vol: 0.25 }); this.tone({ f: 900, dur: 0.1, vol: 0.25, delay: 0.08 }); }
  buy() { if (this.playBuf('ui_confirm', { vol: 0.6 })) return; this.tone({ f: 800, f2: 1200, dur: 0.08, vol: 0.2, type: 'triangle' }); }
  error() { if (this.playBuf('clunk', { vol: 0.5, rate: 0.8 })) return; this.tone({ f: 200, dur: 0.12, vol: 0.2, type: 'square' }); }
  click() { if (this.playBuf('ui_click', { vol: 0.4 })) return; this.tone({ f: 600, dur: 0.03, vol: 0.1 }); }

  // ===== способности =====
  flashThrow() { if (this.playBuf('whoosh', { vol: 0.4, rate: 1.2 })) return; this.noise({ dur: 0.15, vol: 0.2, fc: 2000, fc2: 3500, type: 'bandpass' }); }
  flashPop(vol = 1) { if (this.playBuf('energy', { vol: 0.5 * vol })) return; this.tone({ f: 2500, f2: 4500, dur: 0.4, vol: 0.4 * vol, type: 'sine' }); this.noise({ dur: 0.15, vol: 0.3 * vol, fc: 4000, type: 'highpass' }); }
  fireIgnite(vol = 1) { this.noise({ dur: 0.5, vol: 0.35 * vol, fc: 900, fc2: 300 }); this.tone({ f: 90, f2: 50, dur: 0.4, vol: 0.2 * vol, type: 'sawtooth' }); }
  fireCrackle(vol = 1) { this.noise({ dur: 0.08, vol: 0.06 * vol, fc: 1200 + Math.random() * 1500, q: 3, type: 'bandpass' }); }
  hookThrow() { if (this.playBuf('whoosh', { vol: 0.55 })) return; this.noise({ dur: 0.25, vol: 0.3, fc: 1500, fc2: 400, type: 'bandpass' }); this.tone({ f: 300, f2: 150, dur: 0.2, vol: 0.15, type: 'triangle' }); }
  hookHit() { if (this.playBuf('slam', { vol: 0.75 })) return; this.tone({ f: 150, f2: 60, dur: 0.25, vol: 0.5, type: 'sawtooth' }); this.noise({ dur: 0.15, vol: 0.4, fc: 600 }); }
  rotStart() {
    if (!this.ctx || this.rotNode) return;
    const len = this.ctx.sampleRate;
    const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    const src = this.ctx.createBufferSource();
    src.buffer = buf; src.loop = true;
    const flt = this.ctx.createBiquadFilter();
    flt.type = 'lowpass'; flt.frequency.value = 300; flt.Q.value = 4;
    const g = this.ctx.createGain(); g.gain.value = 0.14;
    src.connect(flt); flt.connect(g); g.connect(this.dest);
    src.start();
    this.rotNode = { src, g };
  }
  rotStop() {
    if (this.rotNode) { try { this.rotNode.src.stop(); } catch {} this.rotNode = null; }
  }
  feast(vol = 1) {
    // чавканье-пожирание: низкое влажное + глоток
    this.noise({ dur: 0.18, vol: 0.28 * vol, fc: 500, fc2: 140 });
    this.body({ f: 120, f2: 70, dur: 0.2, vol: 0.22 * vol, type: 'sawtooth' });
    this.tone({ f: 260, f2: 500, dur: 0.14, vol: 0.16 * vol, type: 'sine', delay: 0.14 });
  }
  growl(vol = 1) {
    // утробное рычание-нюх
    this.body({ f: 90, f2: 55, dur: 0.35, vol: 0.3 * vol, type: 'sawtooth' });
    this.noise({ dur: 0.3, vol: 0.14 * vol, fc: 600, fc2: 250, type: 'bandpass' });
  }
  dismember() {
    this.tone({ f: 100, f2: 45, dur: 0.6, vol: 0.4, type: 'sawtooth' });
    for (let i = 0; i < 6; i++) this.noise({ dur: 0.1, vol: 0.3, fc: 500 + Math.random() * 400, delay: i * 0.4 });
  }
  phoenixUlt() { if (this.playBuf('energy', { vol: 0.6 })) return; this.tone({ f: 300, f2: 900, dur: 0.5, vol: 0.3, type: 'sawtooth' }); this.noise({ dur: 0.5, vol: 0.25, fc: 600, fc2: 2000 }); }

  // ===== новые способности v2 =====
  smokePop(stink = false) {
    if (this.playBuf('pop', { vol: stink ? 0.5 : 0.4, rate: stink ? 0.8 : 1.05 })) return;
    this.noise({ dur: 0.6, vol: 0.3, fc: stink ? 500 : 900, fc2: 150 });
    if (stink) this.tone({ f: 90, f2: 60, dur: 0.5, vol: 0.15, type: 'sawtooth' });
  }
  orbitalWarn() {
    if (this.buffers && this.buffers.beep) {
      [0, 0.35, 0.7].forEach((d) => this.playBuf('beep', { vol: 0.45, rate: 1.25, delay: d }));
      this.playBuf('boom', { vol: 0.7, delay: 1.35 });
      return;
    }
    [0, 0.18, 0.36].forEach((d) => this.tone({ f: 880, dur: 0.12, vol: 0.3, type: 'square', delay: d }));
    this.noise({ dur: 2.5, vol: 0.35, fc: 300, fc2: 2000, delay: 1.2 });
    this.tone({ f: 60, f2: 45, dur: 2.5, vol: 0.3, type: 'sawtooth', delay: 1.4 });
  }
  dash(vol = 1) { if (this.playBuf('whoosh2', { vol: 0.5 * vol })) return; this.noise({ dur: 0.22, vol: 0.3 * vol, fc: 1800, fc2: 400, type: 'bandpass' }); }
  knivesUlt() { if (this.playBuf('energy', { vol: 0.5, rate: 1.1 })) return; [600, 900, 1300].forEach((f, i) => this.tone({ f, dur: 0.12, vol: 0.25, type: 'triangle', delay: i * 0.09 })); }
  knifeThrow() { if (this.playBuf('whoosh', { vol: 0.35, rate: 1.4 })) return; this.noise({ dur: 0.12, vol: 0.25, fc: 3500, fc2: 1500, type: 'bandpass' }); }
  trapPing() { if (this.playBuf('ting', { vol: 0.35 })) return; this.tone({ f: 1500, f2: 2200, dur: 0.2, vol: 0.3, type: 'sine' }); }
  turretPlace() { if (this.playBuf('clunk', { vol: 0.55 })) return; this.tone({ f: 400, f2: 700, dur: 0.15, vol: 0.25, type: 'square' }); this.noise({ dur: 0.1, vol: 0.2, fc: 2000, delay: 0.12 }); }
  turretShot(vol = 1) { this.noise({ dur: 0.05, vol: 0.3 * vol, fc: 2600, fc2: 800 }); }
  xray() { if (this.playBuf('energy', { vol: 0.55, rate: 0.85 })) return; this.tone({ f: 300, f2: 1600, dur: 0.6, vol: 0.3, type: 'sine' }); this.tone({ f: 450, f2: 2400, dur: 0.6, vol: 0.2, type: 'sine', delay: 0.1 }); }
  puddleSplat(vol = 1) { this.noise({ dur: 0.25, vol: 0.35 * vol, fc: 600, fc2: 150 }); }

  // ===== Ира (KFC) =====
  throwLight() { this.noise({ dur: 0.12, vol: 0.2, fc: 2500, fc2: 900, type: 'bandpass' }); }
  crispyPlace(vol = 1) { this.noise({ dur: 0.35, vol: 0.35 * vol, fc: 3000, q: 0.6, type: 'highpass' }); this.tone({ f: 300, f2: 500, dur: 0.15, vol: 0.15 * vol, type: 'triangle' }); }
  buffetPop(vol = 1) { this.tone({ f: 500, f2: 900, dur: 0.25, vol: 0.3 * vol, type: 'sine' }); this.noise({ dur: 0.4, vol: 0.25 * vol, fc: 800, fc2: 2000 }); }
  banquetSummon() { [330, 440, 550, 660].forEach((f, i) => this.tone({ f, dur: 0.25, vol: 0.28, type: 'triangle', delay: i * 0.1 })); this.noise({ dur: 0.6, vol: 0.2, fc: 500, fc2: 1500, delay: 0.2 }); }
  chickenSpawn() { this.tone({ f: 600, f2: 900, dur: 0.1, vol: 0.2, type: 'square' }); this.chickenCluck(0.7); }
  chickenCluck(vol = 1) {
    // «ко-ко-ко-кудах!»
    for (let i = 0; i < 3; i++) this.tone({ f: 700 + Math.random() * 100, f2: 500, dur: 0.06, vol: 0.18 * vol, type: 'square', delay: i * 0.09 });
    this.tone({ f: 900, f2: 1500, dur: 0.18, vol: 0.25 * vol, type: 'square', delay: 0.3 });
    this.tone({ f: 1500, f2: 700, dur: 0.15, vol: 0.2 * vol, type: 'square', delay: 0.45 });
  }

  // ===== Конилий (кони) =====
  neigh(vol = 1) {
    // ржание: скользящий тон вверх-вниз + шум
    this.tone({ f: 400, f2: 900, dur: 0.18, vol: 0.3 * vol, type: 'sawtooth' });
    this.tone({ f: 900, f2: 350, dur: 0.3, vol: 0.28 * vol, type: 'sawtooth', delay: 0.16 });
    this.noise({ dur: 0.4, vol: 0.15 * vol, fc: 1200, fc2: 400, type: 'bandpass', delay: 0.1 });
  }
  gallop(vol = 1) {
    for (let i = 0; i < 6; i++) this.noise({ dur: 0.06, vol: 0.2 * vol, fc: 200 + Math.random() * 100, q: 3, delay: i * 0.12 });
  }
  stampede() {
    this.neigh(1);
    // топот копыт нарастающей толпой
    for (let i = 0; i < 24; i++) this.noise({ dur: 0.05, vol: 0.18 + i * 0.004, fc: 160 + Math.random() * 120, q: 4, delay: i * 0.07 });
    this.tone({ f: 70, f2: 45, dur: 1.6, vol: 0.35, type: 'sawtooth' });
  }

  // ===== Фафик (бати) =====
  dadClones() { if (this.playBuf('energy', { vol: 0.5, rate: 0.9 })) return; [440, 440, 440, 550].forEach((f, i) => this.tone({ f, dur: 0.12, vol: 0.22, type: 'square', delay: i * 0.11 })); this.noise({ dur: 0.3, vol: 0.15, fc: 1000, fc2: 3000, delay: 0.3 }); }
  dadDeClone() { if (this.playBuf('whoosh', { vol: 0.5, rate: 0.9 })) return; this.noise({ dur: 0.3, vol: 0.2, fc: 3000, fc2: 400 }); this.tone({ f: 600, f2: 200, dur: 0.2, vol: 0.2, type: 'triangle' }); }
  // клон лопнул + станящий шоквейв
  clonePop(vol = 1) {
    if (this.buffers && this.buffers.slam) { this.playBuf('slam', { vol: 0.55 * vol }); this.playBuf('zap', { vol: 0.4 * vol, delay: 0.02 }); return; }
    this.crack({ vol: 0.4 * vol, fc: 2200, dur: 0.05, drive: 8 });
    this.noise({ dur: 0.35, vol: 0.35 * vol, fc: 2600, fc2: 300, type: 'bandpass' }); // выброс
    this.body({ f: 150, f2: 45, dur: 0.3, vol: 0.35 * vol, type: 'sine' });           // гулкий бас-удар
    this.tone({ f: 1200, f2: 400, dur: 0.25, vol: 0.14 * vol, type: 'sine', delay: 0.03 }); // «звон» стана
  }

  // ===== Ира (KFC-поддержка) =====
  throwLight() { if (this.playBuf('whoosh', { vol: 0.4, rate: 1.3 })) return; this.noise({ dur: 0.12, vol: 0.2, fc: 2500, fc2: 800, type: 'bandpass' }); }
  chickenSpawn() { if (this.buffers && this.buffers.pop) { this.playBuf('pop', { vol: 0.3, rate: 1.2 }); this.chickenCluck(0.6); return; } this.tone({ f: 500, f2: 900, dur: 0.12, vol: 0.2, type: 'square' }); this.chickenCluck(0.6); }
  // «кудах-тах-тах» — восходяще-нисходящие писки
  chickenCluck(vol = 1) {
    const seq = [900, 1300, 1100, 1500, 800];
    seq.forEach((f, i) => this.tone({ f, f2: f * 0.7, dur: 0.07, vol: 0.22 * vol, type: 'square', delay: i * 0.08 }));
    this.noise({ dur: 0.05, vol: 0.1 * vol, fc: 3000, type: 'highpass', delay: 0.1 });
  }
  crispyPlace(vol = 1) {
    // хруст панировки
    for (let i = 0; i < 5; i++) this.noise({ dur: 0.06, vol: 0.18 * vol, fc: 2500 + Math.random() * 2000, q: 4, type: 'bandpass', delay: i * 0.04 });
    this.tone({ f: 300, f2: 200, dur: 0.2, vol: 0.15 * vol, type: 'triangle' });
  }
  buffetPop(vol = 1) {
    if (this.playBuf('buff', { vol: 0.6 * vol })) return;
    this.tone({ f: 400, f2: 800, dur: 0.25, vol: 0.3 * vol, type: 'sine' });
    this.noise({ dur: 0.4, vol: 0.25 * vol, fc: 1200, fc2: 3000, type: 'bandpass' }); // шипение пара
    [660, 880, 1046].forEach((f, i) => this.tone({ f, dur: 0.15, vol: 0.15 * vol, type: 'triangle', delay: 0.1 + i * 0.08 }));
  }
  banquetSummon() {
    if (this.buffers && this.buffers.buff) { this.playBuf('buff', { vol: 0.75 }); this.playBuf('confirm', { vol: 0.4, delay: 0.22 }); this.chickenCluck(1); return; }
    // фанфары + гулкий бас-«шлепок» гигантского ведра
    [523, 659, 784, 1046].forEach((f, i) => this.tone({ f, dur: 0.22, vol: 0.28, type: 'triangle', delay: i * 0.12 }));
    this.tone({ f: 90, f2: 50, dur: 0.6, vol: 0.4, type: 'sine', delay: 0.5 });
    this.chickenCluck(1);
  }

  // ===== шип =====
  spikeBeep(fast = false) {
    if (this.playBuf('beep', { vol: 0.3, rate: fast ? 1.35 : 1.0 })) return;
    this.tone({ f: fast ? 2300 : 1850, dur: 0.05, vol: 0.24, type: 'square' });
    this.tone({ f: fast ? 3200 : 2600, dur: 0.03, vol: 0.1, type: 'sine', delay: 0.01 });
  }
  plantTick() { if (this.playBuf('ui_click', { vol: 0.3, rate: 1.2 })) return; this.crack({ vol: 0.1, fc: 3500, dur: 0.02, drive: 2 }); this.tone({ f: 900, dur: 0.03, vol: 0.12, type: 'square' }); }
  // ЕДИНЫЙ тик разминирования — звучит одинаково всегда (для фейков нет «прогресса» на слух)
  defuseTick() { if (this.playBuf('ui_click', { vol: 0.28, rate: 1.5 })) return; this.tone({ f: 1400, dur: 0.05, vol: 0.16, type: 'sine' }); this.crack({ vol: 0.06, fc: 5000, dur: 0.015 }); }
  planted() {
    if (this.buffers && this.buffers.slam) { this.playBuf('slam', { vol: 0.6 }); this.playBuf('beep', { vol: 0.4, rate: 0.8, delay: 0.28 }); return; }
    this.tone({ f: 700, dur: 0.15, vol: 0.3 }); this.tone({ f: 500, dur: 0.25, vol: 0.3, delay: 0.15 }); this.body({ f: 90, f2: 60, dur: 0.4, vol: 0.25, delay: 0.05, type: 'sine' });
  }
  defused() { if (this.playBuf('confirm', { vol: 0.75 })) return; this.tone({ f: 700, f2: 1200, dur: 0.18, vol: 0.28, type: 'sine' }); this.tone({ f: 1000, f2: 1500, dur: 0.25, vol: 0.24, type: 'triangle', delay: 0.14 }); }
  explosion() {
    if (this.playBuf('explosion', { vol: 1.0, rate: 0.92 + Math.random() * 0.12 })) return;
    // фолбэк-синтез
    this.noise({ dur: 1.2, vol: 1.0, fc: 400, fc2: 40 });
    this.tone({ f: 60, f2: 25, dur: 1.0, vol: 0.7, type: 'sawtooth' });
  }

  // ===== раунды =====
  roundStart() { if (this.playBuf('whoosh', { vol: 0.5 })) return; this.tone({ f: 440, dur: 0.1, vol: 0.2 }); this.tone({ f: 660, dur: 0.15, vol: 0.2, delay: 0.12 }); }
  roundWin() { if (this.playBuf('confirm', { vol: 0.7 })) return; [523, 659, 784].forEach((f, i) => this.tone({ f, dur: 0.18, vol: 0.25, type: 'triangle', delay: i * 0.13 })); }
  roundLose() { if (this.playBuf('fail', { vol: 0.6 })) return; [392, 330, 262].forEach((f, i) => this.tone({ f, dur: 0.2, vol: 0.25, type: 'triangle', delay: i * 0.15 })); }
  matchWin() { if (this.buffers && this.buffers.confirm) { this.playBuf('confirm', { vol: 0.8 }); this.playBuf('buff', { vol: 0.5, delay: 0.25 }); return; } [523, 659, 784, 1046].forEach((f, i) => this.tone({ f, dur: 0.3, vol: 0.3, type: 'triangle', delay: i * 0.16 })); }
  matchLose() { if (this.playBuf('fail', { vol: 0.7, rate: 0.9 })) return; [330, 294, 262, 196].forEach((f, i) => this.tone({ f, dur: 0.3, vol: 0.3, type: 'triangle', delay: i * 0.18 })); }
}
