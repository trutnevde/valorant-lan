// Постройка карты из конфига MAPS[id] + AABB для коллизий и стрельбы
import * as THREE from './three.module.js';
import { expandStairs, mapAabbs } from './shared.js';

// градиентное небо как текстура-фон
function makeSky(def) {
  const cv = document.createElement('canvas');
  cv.width = 16; cv.height = 256;
  const c = cv.getContext('2d');
  const g = c.createLinearGradient(0, 0, 0, 256);
  if (def.id === 'height') {
    g.addColorStop(0, '#e8c78f'); g.addColorStop(0.5, '#c8a374'); g.addColorStop(1, '#9c8468');
  } else {
    g.addColorStop(0, '#bcd4e6'); g.addColorStop(0.55, '#9db6c6'); g.addColorStop(1, '#7d94a6');
  }
  c.fillStyle = g;
  c.fillRect(0, 0, 16, 256);
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
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

export function buildMap(scene, def) {
  const group = new THREE.Group();
  const solids = [];
  const aabbs = mapAabbs(def);

  // пол и земля
  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(def.SIZE.w + 2, def.SIZE.d + 2),
    new THREE.MeshStandardMaterial({ color: def.id === 'height' ? '#cbbf9e' : '#c8ccc4', roughness: 0.95, metalness: 0 })
  );
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  group.add(floor);
  solids.push(floor);
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(400, 400),
    new THREE.MeshStandardMaterial({ color: '#5a6b5e', roughness: 1 })
  );
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -0.02;
  ground.receiveShadow = true;
  group.add(ground);

  const grid = new THREE.GridHelper(def.SIZE.w, Math.round(def.SIZE.w / 2), 0xaaaaaa, 0xb5bab2);
  grid.position.y = 0.01;
  grid.material.transparent = true;
  grid.material.opacity = 0.25;
  group.add(grid);

  // стены, ящики, лестницы
  const addBox = ([cx, cz, w, d, h, ci, yBase]) => {
    const y0 = yBase || 0;
    const mesh = new THREE.Mesh(
      new THREE.BoxGeometry(w, h, d),
      new THREE.MeshStandardMaterial({ color: def.COLORS[ci] || '#cccccc', roughness: 0.85, metalness: 0.04 })
    );
    mesh.position.set(cx, y0 + h / 2, cz);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
    solids.push(mesh);
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(mesh.geometry),
      new THREE.LineBasicMaterial({ color: 0x2a3340, transparent: true, opacity: 0.35 })
    );
    edges.position.copy(mesh.position);
    group.add(edges);
  };
  def.walls.forEach(addBox);
  def.crates.forEach(addBox);
  expandStairs(def).forEach(addBox);

  // сайты
  for (const [key, s] of Object.entries(def.sites)) {
    const y = (s.yMin || 0) + 0.03;
    const zone = new THREE.Mesh(
      new THREE.PlaneGeometry(s.w, s.d),
      new THREE.MeshBasicMaterial({ color: '#ff4655', transparent: true, opacity: 0.10, depthWrite: false })
    );
    zone.rotation.x = -Math.PI / 2;
    zone.position.set(s.x, y + (s.yMin ? 2.4 - s.yMin + 0.03 : 0), s.z);
    // для платформ рисуем на их поверхности
    if (s.yMin) zone.position.y = 2.43;
    group.add(zone);
    const letter = textPlane(key, '#ff4655', 6);
    letter.position.set(s.x, zone.position.y + 0.01, s.z);
    group.add(letter);
  }

  // спавны
  for (const [role, sp] of Object.entries(def.spawns)) {
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(1.1, 1.4, 32),
      new THREE.MeshBasicMaterial({ color: role === 'attack' ? '#ff4655' : '#0ac8b9', transparent: true, opacity: 0.5, depthWrite: false })
    );
    ring.rotation.x = -Math.PI / 2;
    ring.position.set(sp.pts[0][0], 0.02, sp.pts[0][2]);
    group.add(ring);
  }

  // свет и атмосфера (в group — чтобы смена карты убрала и свет)
  scene.background = makeSky(def);
  scene.fog = new THREE.Fog(new THREE.Color(def.id === 'height' ? '#c4a988' : '#9db6c6').getHex(), 65, 175);
  group.add(new THREE.HemisphereLight('#dbe8f2', '#3a4640', 0.5));
  group.add(new THREE.AmbientLight('#ffffff', 0.08));
  const sun = new THREE.DirectionalLight('#fff2d0', 2.6);
  sun.position.set(-30, 55, 28);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  const S = Math.max(def.SIZE.w, def.SIZE.d) * 0.62;
  sun.shadow.camera.left = -S; sun.shadow.camera.right = S;
  sun.shadow.camera.top = S; sun.shadow.camera.bottom = -S;
  sun.shadow.camera.near = 1; sun.shadow.camera.far = 160;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.03;
  group.add(sun);
  group.add(sun.target);

  scene.add(group);
  return { group, aabbs, solids, def };
}
