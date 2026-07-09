// Конвертер карт: схема веба (shared.js MAPS) → грейбокс-сцены Godot (.tscn).
// Каждый бокс → MeshInstance3D + StaticBody3D/CollisionShape3D; спавны → Marker3D;
// сайты → Area3D; стены h>=2.9 пишутся в meta walls_aabb (телеметрия сквозь-стен ботматча).
// Запуск из корня репы:  node godot/tools/convert_maps.mjs [duel]
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MAPS } from '../../public/js/shared.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const which = process.argv[2] || 'duel';
const m = MAPS[which];
if (!m) { console.error('нет карты', which); process.exit(1); }

let sub = [];       // sub_resources
let nodes = [];     // node blocks
let subId = 0;

const matIds = {};
function matFor(colorIdx) {
  if (matIds[colorIdx] !== undefined) return matIds[colorIdx];
  const hex = (m.COLORS && m.COLORS[colorIdx]) || '#b8bfc7';
  const r = parseInt(hex.slice(1, 3), 16) / 255, g = parseInt(hex.slice(3, 5), 16) / 255, b = parseInt(hex.slice(5, 7), 16) / 255;
  const id = `mat${subId++}`;
  sub.push(`[sub_resource type="StandardMaterial3D" id="${id}"]\nalbedo_color = Color(${r.toFixed(3)}, ${g.toFixed(3)}, ${b.toFixed(3)}, 1)\nroughness = 0.85`);
  matIds[colorIdx] = id;
  return id;
}

function box(name, cx, cz, w, d, h, colorIdx, yBase = 0) {
  const meshId = `mesh${subId++}`, shapeId = `shape${subId++}`;
  sub.push(`[sub_resource type="BoxMesh" id="${meshId}"]\nsize = Vector3(${w}, ${h}, ${d})`);
  sub.push(`[sub_resource type="BoxShape3D" id="${shapeId}"]\nsize = Vector3(${w}, ${h}, ${d})`);
  const y = yBase + h / 2;
  nodes.push(`[node name="${name}" type="StaticBody3D" parent="Geometry" groups=["map_solid"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, ${cx}, ${y}, ${cz})

[node name="Mesh" type="MeshInstance3D" parent="Geometry/${name}"]
mesh = SubResource("${meshId}")
surface_material_override/0 = SubResource("${matFor(colorIdx)}")

[node name="Col" type="CollisionShape3D" parent="Geometry/${name}"]
shape = SubResource("${shapeId}")`);
}

// пол
{
  const meshId = `mesh${subId++}`, shapeId = `shape${subId++}`;
  sub.push(`[sub_resource type="BoxMesh" id="${meshId}"]\nsize = Vector3(${m.SIZE.w}, 1, ${m.SIZE.d})`);
  sub.push(`[sub_resource type="BoxShape3D" id="${shapeId}"]\nsize = Vector3(${m.SIZE.w}, 1, ${m.SIZE.d})`);
  sub.push(`[sub_resource type="StandardMaterial3D" id="floormat"]\nalbedo_color = Color(0.78, 0.76, 0.71, 1)\nroughness = 0.95`);
  nodes.push(`[node name="Floor" type="StaticBody3D" parent="Geometry" groups=["map_solid"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)

[node name="Mesh" type="MeshInstance3D" parent="Geometry/Floor"]
mesh = SubResource("${meshId}")
surface_material_override/0 = SubResource("floormat")

[node name="Col" type="CollisionShape3D" parent="Geometry/Floor"]
shape = SubResource("${shapeId}")`);
}

const wallsAabb = [];
(m.walls || []).forEach((wl, i) => {
  const [cx, cz, w, d, h, ci, yb] = wl;
  box(`Wall${i}`, cx, cz, w, d, h, ci ?? 1, yb || 0);
  if (h >= 2.9 && (yb || 0) < 1.5) wallsAabb.push([cx - w / 2, cz - d / 2, cx + w / 2, cz + d / 2]);
});
(m.crates || []).forEach((cr, i) => {
  const [cx, cz, w, d, h, ci, yb] = cr;
  box(`Crate${i}`, cx, cz, w, d, h, ci ?? 4, yb || 0);
});
// лестницы: каждая ступень — бокс
(m.stairs || []).forEach((st, i) => {
  for (let s = 0; s < st.steps; s++) {
    const rise = st.rise * (s + 1);
    const off = st.run * s + st.run / 2;
    let cx = st.x, cz = st.z, w = st.w, d = st.run;
    if (st.dir === 'N') cz = st.z - off;
    else if (st.dir === 'S') cz = st.z + off;
    else if (st.dir === 'E') { cx = st.x + off; w = st.run; d = st.w; }
    else if (st.dir === 'W') { cx = st.x - off; w = st.run; d = st.w; }
    box(`Stair${i}_${s}`, cx, cz, w, d, rise, 1);
  }
});

// спавны → Marker3D
for (const side of ['attack', 'defend']) {
  const sp = m.spawns[side];
  sp.pts.forEach((p, i) => {
    nodes.push(`[node name="Spawn_${side}_${i}" type="Marker3D" parent="Spawns" groups=["spawn_${side}"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, ${p[0]}, ${p[1] || 0}, ${p[2]})`);
  });
}
// сайты → Area3D
for (const key of Object.keys(m.sites)) {
  const s = m.sites[key];
  const shapeId = `siteshape${subId++}`;
  sub.push(`[sub_resource type="BoxShape3D" id="${shapeId}"]\nsize = Vector3(${s.w}, 4, ${s.d})`);
  nodes.push(`[node name="Site${key}" type="Area3D" parent="Sites" groups=["site"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, ${s.x}, 2, ${s.z})

[node name="Col" type="CollisionShape3D" parent="Sites/Site${key}"]
shape = SubResource("${shapeId}")`);
}

// NavigationRegion3D — навмеш бейкается tools/bake_navmesh.gd и сохраняется рядом .res
nodes.push(`[node name="Nav" type="NavigationRegion3D" parent="."]`);

const meta = {
  map_id: m.id, size_w: m.SIZE.w, size_d: m.SIZE.d,
  walls_aabb: wallsAabb,
  site_a: [m.sites.A.x, m.sites.A.z], site_b: [m.sites.B.x, m.sites.B.z],
};

const out = `[gd_scene load_steps=${sub.length + 1} format=3]

${sub.join('\n\n')}

[node name="Map_${m.id}" type="Node3D"]
metadata/map_meta = ${JSON.stringify(JSON.stringify(meta))}

[node name="Geometry" type="Node3D" parent="."]

[node name="Spawns" type="Node3D" parent="."]

[node name="Sites" type="Node3D" parent="."]

${nodes.join('\n\n')}
`;

const dest = path.join(__dirname, '..', 'scenes', 'maps', `${m.id}.tscn`);
writeFileSync(dest, out.replace(/\r?\n/g, '\n'), 'utf8');
console.log(`${m.id}.tscn записан: боксов=${(m.walls || []).length + (m.crates || []).length}, стен-AABB=${wallsAabb.length}, спавнов=${m.spawns.attack.pts.length + m.spawns.defend.pts.length}`);
