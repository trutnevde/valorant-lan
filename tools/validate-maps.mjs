// Валидатор связности карт: ноды не в стенах, рёбра не режут барьеры, оба сайта
// достижимы, спавны валидны. Барьеры = НАСТОЯЩИЕ стены (h>=2.9) — как в коллизии ботов
// (server.js botHitsWall): мелкие укрытия/платформы/насесты бот обходит и не застревает.
// Exit 0 — все карты ок; exit 1 — есть проблемы (для npm run gate).
import { MAPS, expandStairs } from '../public/js/shared.js';

const R = 0.34;                 // радиус бота (server.js BOT_R)
const WALL_MIN_H = 2.9;         // порог «настоящей стены»

function barriersOf(d) {
  const boxes = [...d.walls, ...d.crates, ...expandStairs(d)];
  return boxes
    .filter(b => { const yb = b[6] || 0, h = b[4]; return h >= WALL_MIN_H && yb < 1.5 && (yb + h) > 0.35; })
    .map(([cx, cz, w, dep]) => ({ x0: cx - w / 2 - R, x1: cx + w / 2 + R, z0: cz - dep / 2 - R, z1: cz + dep / 2 + R, raw: [cx, cz, w, dep] }));
}

function validateMap(id, d) {
  const bars = barriersOf(d);
  const inBar = (x, z) => bars.find(b => x > b.x0 && x < b.x1 && z > b.z0 && z < b.z1);
  const problems = [];

  for (const side of ['attack', 'defend'])
    for (const p of d.spawns[side].pts)
      if (inBar(p[0], p[2])) problems.push(`спавн ${side} [${p[0]},${p[2]}] в стене`);

  d.nav.nodes.forEach((n, i) => {
    if ((n[2] || 0) < 0.5 && inBar(n[0], n[1])) problems.push(`нода #${i} [${n[0]},${n[1]}] в стене`);
  });

  for (const [a, c] of d.nav.edges) {
    const na = d.nav.nodes[a], nb = d.nav.nodes[c];
    if ((na[2] || 0) >= 0.5 || (nb[2] || 0) >= 0.5) continue; // рампы/платформы пропускаем
    let hits = 0;
    for (let t = 0.1; t < 1; t += 0.1)
      if (inBar(na[0] + (nb[0] - na[0]) * t, na[1] + (nb[1] - na[1]) * t)) hits++;
    if (hits >= 2) problems.push(`ребро ${a}->${c} режет стену (${hits} сэмплов)`);
  }

  // достижимость обоих сайтов от спавна атаки
  const adj = d.nav.nodes.map(() => []);
  for (const [a, c] of d.nav.edges) { adj[a].push(c); adj[c].push(a); }
  const near = (x, z) => {
    let bi = 0, bd = Infinity;
    d.nav.nodes.forEach((n, i) => { const dd = Math.hypot(n[0] - x, n[1] - z); if (dd < bd) { bd = dd; bi = i; } });
    return bi;
  };
  const start = near(d.spawns.attack.pts[0][0], d.spawns.attack.pts[0][2]);
  const seen = new Set([start]); const q = [start];
  while (q.length) { const u = q.shift(); for (const v of adj[u]) if (!seen.has(v)) { seen.add(v); q.push(v); } }
  for (const s of ['A', 'B']) if (!seen.has(near(d.sites[s].x, d.sites[s].z))) problems.push(`сайт ${s} недостижим от спавна атаки`);

  return { problems, reach: seen.size, total: d.nav.nodes.length };
}

let failed = 0;
for (const id of Object.keys(MAPS)) {
  const r = validateMap(id, MAPS[id]);
  if (r.problems.length) {
    failed++;
    console.log(`✖ ${id}: ${r.problems.length} проблем (нод достижимо ${r.reach}/${r.total})`);
    for (const p of r.problems) console.log(`    - ${p}`);
  } else {
    console.log(`✓ ${id}: чисто (нод достижимо ${r.reach}/${r.total})`);
  }
}
if (failed) { console.log(`\n✖ ВАЛИДАЦИЯ КАРТ: ${failed} карт(ы) с проблемами`); process.exit(1); }
console.log('\n✅ ВАЛИДАЦИЯ КАРТ: все карты связны и валидны');
