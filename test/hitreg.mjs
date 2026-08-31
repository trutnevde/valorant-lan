// HITREG-санити (headless-прокси клиентского рейкаста weapons.js):
// строим капсульный стек хитбоксов человечка на фикс. позиции и стреляем детерминированными
// лучами из глаза. Ловит сбитый прицел (сломанную конвенцию направления луча) и сломанные
// хитбоксы (позиции/части голова/тело/ноги). Полный клиентский хитрег требует браузера —
// это его геометрический headless-эквивалент на том же движке (three).
import * as THREE from '../public/js/three.module.js';

function makeDummy(x, z) {
  const g = new THREE.Group();
  const add = (geo, y, part) => { const m = new THREE.Mesh(geo); m.position.set(0, y, 0); m.userData.part = part; g.add(m); };
  add(new THREE.SphereGeometry(0.2, 12, 10), 1.68, 'head');       // голова
  add(new THREE.CapsuleGeometry(0.26, 0.55, 6, 10), 1.12, 'body'); // корпус
  add(new THREE.CapsuleGeometry(0.11, 0.55, 6, 10), 0.45, 'leg');  // ноги
  g.position.set(x, 0, z);
  g.updateMatrixWorld(true);
  const meshes = [];
  g.traverse(o => { if (o.isMesh) meshes.push(o); });
  return meshes;
}

const dummy = makeDummy(10, 0);
const eye = new THREE.Vector3(0, 1.6, 0);
const cast = (target) => {
  const dir = target.clone().sub(eye).normalize();
  const rc = new THREE.Raycaster(eye, dir);
  const hits = rc.intersectObjects(dummy, false);
  return hits[0] ? (hits[0].object.userData.part || 'body') : null;
};

let ok = true;
const check = (name, got, exp) => { const p = got === exp; console.log(`  [${p ? 'ok' : 'FAIL'}] ${name} → ${got}`); if (!p) ok = false; };
check('корпус попадание', cast(new THREE.Vector3(10, 1.12, 0)), 'body');
check('голова попадание', cast(new THREE.Vector3(10, 1.68, 0)), 'head');
check('ноги попадание', cast(new THREE.Vector3(10, 0.45, 0)), 'leg');
check('промах в сторону', cast(new THREE.Vector3(10, 1.12, 6)), null);

console.log(ok ? '✅ HITREG-САНИТИ: ок' : '✖ HITREG-САНИТИ: провал');
process.exit(ok ? 0 : 1);
