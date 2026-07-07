// Постройка карты из конфига MAPS[id] + AABB для коллизий и стрельбы.
// v3: процедурные текстуры (бетон/дерево/плитка), тени от солнца, небо-купол.
import * as THREE from './three.module.js';
import { expandStairs, mapAabbs } from './shared.js';

// ===== настоящие PBR-текстуры (Poly Haven CC0), если скачаны в public/assets/ =====
// Если ассетов нет — тихо остаёмся на процедурных текстурах ниже. Всё офлайн.
let _manifestPromise;
function loadManifest() {
  if (!_manifestPromise) {
    _manifestPromise = fetch('assets/manifest.json')
      .then(r => (r.ok ? r.json() : null)).catch(() => null);
  }
  return _manifestPromise;
}
async function applyPbr(targets, renderer) {
  const manifest = await loadManifest();
  if (!manifest || !manifest.textures) return;
  const tl = new THREE.TextureLoader();
  const load = (url) => url ? new Promise(res => tl.load(url, res, undefined, () => res(null))) : Promise.resolve(null);
  const aniso = renderer ? renderer.capabilities.getMaxAnisotropy() : 8;
  const cfg = (t, srgb) => {
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
    t.anisotropy = aniso; t.needsUpdate = true; return t;
  };
  for (const kind of Object.keys(targets)) {
    if (!targets[kind].length) continue;
    const set = manifest.textures[kind];
    if (!set) continue;
    const [dif, nor, arm] = await Promise.all([load(set.diffuse), load(set.normal), load(set.arm)]);
    if (!dif) continue;
    cfg(dif, true); if (nor) cfg(nor, false); if (arm) cfg(arm, false);
    // одна текстура на весь тип поверхности (тайлинг запечён в UV) — память минимальна
    for (const { material, tint } of targets[kind]) {
      material.map = dif;
      if (nor) { material.normalMap = nor; material.normalScale.set(0.8, 0.8); }
      if (arm) { material.roughnessMap = arm; material.metalness = 0; }
      if (tint) material.color.lerp(new THREE.Color(0xffffff), 0.4); // приглушить оттенок, но не выбеливать
      else material.color.set(0xffffff);
      material.needsUpdate = true;
    }
  }
}

// ===== процедурные текстуры (без единого файла) =====
function canvasTex(draw, w = 256, h = 256) {
  const cv = document.createElement('canvas');
  cv.width = w; cv.height = h;
  draw(cv.getContext('2d'), w, h);
  const tex = new THREE.CanvasTexture(cv);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function noise(c, w, h, n, alpha, light = false) {
  for (let i = 0; i < n; i++) {
    c.fillStyle = light
      ? `rgba(255,255,255,${Math.random() * alpha})`
      : `rgba(0,0,0,${Math.random() * alpha})`;
    c.fillRect(Math.random() * w, Math.random() * h, 1 + Math.random() * 2, 1 + Math.random() * 2);
  }
}

// бетон: панельные швы + шум + потёртости
function concreteTex() {
  return canvasTex((c, w, h) => {
    c.fillStyle = '#ffffff';
    c.fillRect(0, 0, w, h);
    noise(c, w, h, 1600, 0.06);
    noise(c, w, h, 800, 0.05, true);
    // горизонтальные швы панелей
    c.strokeStyle = 'rgba(0,0,0,0.22)';
    c.lineWidth = 2;
    for (let y = 64; y < h; y += 64) {
      c.beginPath(); c.moveTo(0, y); c.lineTo(w, y); c.stroke();
      c.strokeStyle = 'rgba(255,255,255,0.10)';
      c.beginPath(); c.moveTo(0, y + 2); c.lineTo(w, y + 2); c.stroke();
      c.strokeStyle = 'rgba(0,0,0,0.22)';
    }
    // вертикальные швы реже
    for (let x = 128; x < w; x += 128) {
      c.beginPath(); c.moveTo(x, 0); c.lineTo(x, h); c.stroke();
    }
    // тёмный низ (грязь у земли)
    const g = c.createLinearGradient(0, h - 46, 0, h);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(1, 'rgba(0,0,0,0.28)');
    c.fillStyle = g;
    c.fillRect(0, h - 46, w, 46);
  });
}

// дерево: доски с волокнами
function woodTex() {
  return canvasTex((c, w, h) => {
    c.fillStyle = '#ffffff';
    c.fillRect(0, 0, w, h);
    const plank = 42;
    for (let y = 0; y < h; y += plank) {
      // тон доски слегка гуляет
      c.fillStyle = `rgba(0,0,0,${0.03 + Math.random() * 0.08})`;
      c.fillRect(0, y, w, plank);
      // волокна
      for (let i = 0; i < 22; i++) {
        c.strokeStyle = `rgba(0,0,0,${0.04 + Math.random() * 0.06})`;
        c.lineWidth = 1;
        const gy = y + 4 + Math.random() * (plank - 8);
        c.beginPath();
        c.moveTo(0, gy);
        c.bezierCurveTo(w * 0.3, gy + (Math.random() - 0.5) * 6, w * 0.7, gy + (Math.random() - 0.5) * 6, w, gy);
        c.stroke();
      }
      // шов между досками
      c.strokeStyle = 'rgba(0,0,0,0.4)';
      c.lineWidth = 2;
      c.beginPath(); c.moveTo(0, y); c.lineTo(w, y); c.stroke();
      // гвозди
      c.fillStyle = 'rgba(0,0,0,0.35)';
      c.beginPath(); c.arc(10, y + plank / 2, 2, 0, 7); c.fill();
      c.beginPath(); c.arc(w - 10, y + plank / 2, 2, 0, 7); c.fill();
    }
    noise(c, w, h, 700, 0.05);
  });
}

// плитка пола: крупные плиты + затирка + пятна
function floorTex() {
  return canvasTex((c, w, h) => {
    c.fillStyle = '#ffffff';
    c.fillRect(0, 0, w, h);
    noise(c, w, h, 1800, 0.05);
    noise(c, w, h, 600, 0.04, true);
    const tile = 128;
    c.strokeStyle = 'rgba(0,0,0,0.26)';
    c.lineWidth = 3;
    for (let y = 0; y <= h; y += tile) { c.beginPath(); c.moveTo(0, y); c.lineTo(w, y); c.stroke(); }
    for (let x = 0; x <= w; x += tile) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, h); c.stroke(); }
    // случайные пятна/потёртости
    for (let i = 0; i < 7; i++) {
      c.fillStyle = `rgba(0,0,0,${0.03 + Math.random() * 0.05})`;
      c.beginPath();
      c.ellipse(Math.random() * w, Math.random() * h, 18 + Math.random() * 36, 12 + Math.random() * 26, Math.random() * 3, 0, 7);
      c.fill();
    }
  }, 512, 512);
}

// небо: градиент зенит → горизонт
function skyTex(top, horizon) {
  return canvasTex((c, w, h) => {
    const g = c.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, top);
    g.addColorStop(0.62, horizon);
    g.addColorStop(1, horizon);
    c.fillStyle = g;
    c.fillRect(0, 0, w, h);
  }, 16, 256);
}

function textPlane(text, color, size) {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 256;
  const c = cv.getContext('2d');
  c.font = '900 200px Arial';
  c.textAlign = 'center'; c.textBaseline = 'middle';
  c.fillStyle = color;
  c.fillText(text, 128, 140);
  const tex = new THREE.CanvasTexture(cv);
  const m = new THREE.Mesh(
    new THREE.PlaneGeometry(size, size),
    new THREE.MeshBasicMaterial({ map: tex, transparent: true, opacity: 0.4, depthWrite: false })
  );
  m.rotation.x = -Math.PI / 2;
  return m;
}

export function buildMap(scene, def, renderer) {
  const group = new THREE.Group();
  const solids = [];
  const aabbs = mapAabbs(def);
  const isHeight = def.id === 'height';

  // процедурные текстуры — мгновенный фолбэк; PBR подменит их когда/если скачаны
  const T = { concrete: concreteTex(), wood: woodTex(), floor: floorTex(), ground: concreteTex() };
  Object.values(T).forEach(t => { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(1, 1); });
  // цели для подмены на настоящие PBR-текстуры, сгруппированы по типу поверхности
  const pbr = { floor: [], ground: [], wall: [], wood: [] };
  // тайлинг «запекаем» в UV, а не в texture.repeat — так все меши делят ОДНУ текстуру (память ↓)
  const bakeUv = (geo, rx, ry) => {
    const uv = geo.attributes.uv;
    for (let i = 0; i < uv.count; i++) {
      uv.setXY(i, uv.getX(i) * Math.max(0.5, rx), uv.getY(i) * Math.max(0.5, ry));
    }
    uv.needsUpdate = true;
  };

  // ===== пол и земля =====
  const floorColor = def.id === 'bastion' ? '#b3aca0' : isHeight ? '#c2b494' : '#b9bdb4';
  const floorGeo = new THREE.PlaneGeometry(def.SIZE.w + 2, def.SIZE.d + 2);
  bakeUv(floorGeo, (def.SIZE.w + 2) / 8, (def.SIZE.d + 2) / 8);
  const floorMat = new THREE.MeshStandardMaterial({ color: floorColor, map: T.floor, roughness: 0.92 });
  const floor = new THREE.Mesh(floorGeo, floorMat);
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  group.add(floor);
  solids.push(floor);
  pbr.floor.push({ material: floorMat, tint: false });
  const groundGeo = new THREE.PlaneGeometry(500, 500);
  bakeUv(groundGeo, 50, 50);
  const groundMat = new THREE.MeshStandardMaterial({ color: '#5a6a5a', map: T.ground, roughness: 1 });
  const ground = new THREE.Mesh(groundGeo, groundMat);
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -0.02;
  ground.receiveShadow = true;
  group.add(ground);
  pbr.ground.push({ material: groundMat, tint: false });

  // ===== стены, ящики, лестницы =====
  const addBox = ([cx, cz, w, d, h, ci, yBase], kind) => {
    const y0 = yBase || 0;
    const crate = kind === 'crate' && h <= 2.6 && w <= 4; // маленькие — деревянные ящики
    const base = crate ? T.wood : T.concrete;
    const geo = new THREE.BoxGeometry(w, h, d);
    bakeUv(geo, Math.max(w, d) / (crate ? 1.6 : 3.2), h / (crate ? 1.6 : 3.2));
    const mat = new THREE.MeshStandardMaterial({
      color: def.COLORS[ci] || '#cccccc',
      map: base,
      roughness: crate ? 0.85 : 0.94,
    });
    (crate ? pbr.wood : pbr.wall).push({ material: mat, tint: true });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.set(cx, y0 + h / 2, cz);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
    solids.push(mesh);
    // тонкая тёмная грань для читаемости силуэтов
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(mesh.geometry),
      new THREE.LineBasicMaterial({ color: 0x1d242e, transparent: true, opacity: 0.16 })
    );
    edges.position.copy(mesh.position);
    group.add(edges);
  };
  def.walls.forEach(b => addBox(b, 'wall'));
  def.crates.forEach(b => addBox(b, 'crate'));
  expandStairs(def).forEach(b => addBox(b, 'stair'));

  // ===== сайты =====
  for (const [key, s] of Object.entries(def.sites)) {
    const zone = new THREE.Mesh(
      new THREE.PlaneGeometry(s.w, s.d),
      new THREE.MeshBasicMaterial({ color: '#ff4655', transparent: true, opacity: 0.10, depthWrite: false })
    );
    zone.rotation.x = -Math.PI / 2;
    zone.position.set(s.x, (s.yMin ? 2.43 : 0.03), s.z);
    group.add(zone);
    const letter = textPlane(key, '#ff4655', 6);
    letter.position.set(s.x, zone.position.y + 0.01, s.z);
    group.add(letter);
  }

  // ===== спавны =====
  for (const [role, sp] of Object.entries(def.spawns)) {
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(1.1, 1.4, 32),
      new THREE.MeshBasicMaterial({ color: role === 'attack' ? '#ff4655' : '#0ac8b9', transparent: true, opacity: 0.5, depthWrite: false })
    );
    ring.rotation.x = -Math.PI / 2;
    ring.position.set(sp.pts[0][0], 0.02, sp.pts[0][2]);
    group.add(ring);
  }

  // ===== небо-купол и атмосфера =====
  const skyTop = def.id === 'bastion' ? '#6a7fa0' : isHeight ? '#7d97b8' : '#5f83a8';
  const skyHor = def.id === 'bastion' ? '#d8cdb8' : isHeight ? '#e0c9a2' : '#c3cfd6';
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(340, 24, 12),
    new THREE.MeshBasicMaterial({ map: skyTex(skyTop, skyHor), side: THREE.BackSide, fog: false, depthWrite: false })
  );
  sky.name = 'proceduralSky'; // прячется, когда загрузится HDRI-небо
  group.add(sky);
  scene.background = new THREE.Color(skyHor);
  scene.fog = new THREE.Fog(new THREE.Color(skyHor).getHex(), 65, 190);

  // ===== свет: солнце с настоящими тенями =====
  group.add(new THREE.HemisphereLight('#cfe0ec', '#55604f', 0.75));
  const sun = new THREE.DirectionalLight('#fff2dd', 1.35);
  sun.position.set(30, 52, 20);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  const half = Math.max(def.SIZE.w, def.SIZE.d) / 2 + 6;
  sun.shadow.camera.left = -half;
  sun.shadow.camera.right = half;
  sun.shadow.camera.top = half;
  sun.shadow.camera.bottom = -half;
  sun.shadow.camera.near = 5;
  sun.shadow.camera.far = 140;
  sun.shadow.bias = -0.0006;
  group.add(sun);
  group.add(sun.target);
  // мягкий контровой, чтобы теневые стороны не были чёрными
  const fill = new THREE.DirectionalLight('#bcd0e8', 0.28);
  fill.position.set(-24, 30, -18);
  group.add(fill);

  // подменяем процедурные текстуры на настоящие PBR (CC0), если скачаны — иначе остаёмся на процедурных
  applyPbr(pbr, renderer).catch(() => {});

  scene.add(group);
  return { group, aabbs, solids, def };
}
