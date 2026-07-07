// GLTF-модели персонажей: настоящая скелетная анимация вместо процедурных капсул.
// Модели ОПЦИОНАЛЬНЫ и лежат в public/assets/models/characters/<agent>.glb
// (имена агентов перечисляются в manifest.json → "models": ["artemiy", ...]).
// Нет модели → RemotePlayer остаётся на процедурном человечке (buildHumanoid). Никакой регрессии.
// Всё офлайн: GLTFLoader/SkeletonUtils вендорены в ./three/, ассеты — локальные файлы.
//
// Быстрый показ «как это выглядит» без своих моделей:  в консоли  window.USE_DEMO_MODELS = true
// — тогда для всех агентов подставится CC0-модель _demo.glb (RobotExpressive, three.js, CC0).
import * as THREE from './three.module.js';
import { GLTFLoader } from './three/loaders/GLTFLoader.js';
import { clone as cloneSkinned } from './three/utils/SkeletonUtils.js';

const loader = new GLTFLoader();
const _cache = new Map();     // path -> Promise<gltf|null>
let _manifest = null;         // кэш manifest.json

async function ensureManifest() {
  if (_manifest !== null) return;
  try { _manifest = (await (await fetch('assets/manifest.json')).json()) || {}; }
  catch { _manifest = {}; }
}

function loadGltf(path) {
  if (!_cache.has(path)) {
    _cache.set(path, new Promise(res => loader.load(path, res, undefined, () => res(null))));
  }
  return _cache.get(path);
}

// Возвращает gltf для агента, либо null (тогда — процедурный человечек). Источник, по приоритету:
//   1) manifest.characterModels[агент] — файл из CC0-пака (напр. "Knight.glb")
//   2) manifest.models содержит агента — персональный <агент>.glb (свой экспорт из Mixamo)
//   3) window.USE_DEMO_MODELS — демо _demo.glb для всех
export async function getCharacterGltf(char) {
  await ensureManifest();
  const map = _manifest.characterModels || {};
  const models = Array.isArray(_manifest.models) ? _manifest.models : [];
  const file = map[char] || (models.includes(char) ? `${char}.glb` : null);
  if (file) {
    const g = await loadGltf(`assets/models/characters/${file}`);
    if (g) return g;
  }
  if (window.USE_DEMO_MODELS) {
    const d = await loadGltf('assets/models/characters/_demo.glb');
    if (d) return d;
  }
  return null;
}

// Сначала точное совпадение имени (exact), потом по подстроке (fuzzy) — под разные паки/Mixamo.
function pickClip(clips, exact, fuzzy) {
  for (const n of exact) { const c = clips.find(cl => cl.name.toLowerCase() === n.toLowerCase()); if (c) return c; }
  for (const k of fuzzy) { const c = clips.find(cl => cl.name.toLowerCase().includes(k)); if (c) return c; }
  return null;
}

// Строит готовый к использованию экземпляр модели для одного игрока.
// Возвращает { group, hitMeshes, head, setMotion, playDeath, reset, update } —
// это дроп-ин замена того, что даёт buildHumanoid (group + hitMeshes + head).
export function makeGltfCharacter(gltf, char, cfg, pid) {
  const model = cloneSkinned(gltf.scene);

  // нормализуем рост к ~1.8 юнита и ставим ступни в 0
  const box = new THREE.Box3().setFromObject(model);
  const rawH = box.max.y - box.min.y || 1.8;
  const s = 1.8 / rawH;
  model.scale.setScalar(s);
  model.position.y = -box.min.y * s;
  // процедурный человечек смотрит по -Z (спина/шип на +Z) — развернём модель так же при тесте
  model.rotation.y = Math.PI;

  // тени + лёгкий тинт под цвет агента (сохраняем командную/агентскую идентичность)
  const tint = new THREE.Color(cfg?.color || '#cccccc');
  model.traverse(o => {
    if (o.isMesh || o.isSkinnedMesh) {
      o.castShadow = true;
      o.frustumCulled = false;
      if (o.material) {
        o.material = o.material.clone();
        if (o.material.color) o.material.color.lerp(tint, 0.32);
        o.material.envMapIntensity = 0.85;
      }
    }
  });

  const group = new THREE.Group();  // внешняя обёртка: сюда игра крутит yaw и двигает позицию
  group.add(model);

  // ── анимации ──
  const mixer = new THREE.AnimationMixer(model);
  const clips = gltf.animations || [];
  const cIdle = pickClip(clips, ['Idle', 'Unarmed_Idle'], ['idle', 'survey', 'breath']) || clips[0] || null;
  const cWalk = pickClip(clips, ['Walking_A', 'Walk'], ['walk']) || cIdle;
  const cRun = pickClip(clips, ['Running_A', 'Run'], ['run']) || cWalk;
  const cDeath = pickClip(clips, ['Death_A', 'Death'], ['death', 'die', 'dead']);
  const A = {
    idle: cIdle && mixer.clipAction(cIdle),
    walk: cWalk && mixer.clipAction(cWalk),
    run: cRun && mixer.clipAction(cRun),
    death: cDeath && mixer.clipAction(cDeath),
  };
  if (A.death) { A.death.loop = THREE.LoopOnce; A.death.clampWhenFinished = true; }
  let current = null;
  const play = (act, fade = 0.2) => {
    if (!act || act === current) return;
    if (current) current.fadeOut(fade);
    act.reset().setEffectiveWeight(1).fadeIn(fade).play();
    current = act;
  };
  if (A.idle) { A.idle.play(); current = A.idle; }

  // ── невидимые стабильные хитбоксы (капсулы), привязаны к обёртке ──
  // хитрег честный и не зависит от фазы анимации; userData.part → хедшот/ноги как раньше
  const hidden = new THREE.MeshBasicMaterial({ visible: false });
  const mkHit = (w, hh, d, y, part) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, hh, d), hidden);
    m.position.y = y;
    m.userData.part = part;
    m.userData.pid = pid;
    group.add(m);
    return m;
  };
  const head = mkHit(0.36, 0.34, 0.36, 1.62, 'head');
  const torso = mkHit(0.62, 0.8, 0.44, 1.12, 'body');
  const legs = mkHit(0.5, 0.9, 0.34, 0.45, 'leg');
  const hitMeshes = [head, torso, legs];

  return {
    group, model, mixer, hitMeshes, head,
    setMotion(walking, speed) {
      if (walking) play(speed > 4.4 && A.run ? A.run : A.walk);
      else play(A.idle);
    },
    playDeath() {
      if (A.death) play(A.death, 0.12);
    },
    reset() {
      if (A.idle) { play(A.idle, 0.05); }
    },
    update(dt) { mixer.update(dt); },
  };
}
