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

let ext = [];       // ext_resources (текстуры, HDRI)
let sub = [];       // sub_resources
let nodes = [];     // node blocks
let subId = 0;

// ===== PBR-материалы (G10): вендоренные CC0-наборы Poly Haven из godot/assets/textures =====
// Тайлинг задаётся uv1_scale по РЕАЛЬНОМУ размеру бокса, иначе текстура растягивается на
// длинных стенах. Трипланар не берём — он дороже, а боксы осевые, UV предсказуемы.
const TEX = { wall: 'wall', floor: 'floor', ground: 'ground', wood: 'wood' };
const extIds = {};
function texExt(kind, map) {
  const key = `${kind}_${map}`;
  if (extIds[key]) return extIds[key];
  const id = `tex_${key}`;
  extIds[key] = id;
  ext.push(`[ext_resource type="Texture2D" path="res://assets/textures/${TEX[kind]}/${map}.jpg" id="${id}"]`);
  return id;
}

const matIds = {};
// kind — какой CC0-набор класть; tint — оттенок из палитры карты, приглушённый (как в вебе:
// текстура ведёт, цвет лишь подкрашивает, иначе карта теряет читаемость зон)
function pbrMat(kind, colorIdx, uvScale) {
  const key = `${kind}_${colorIdx}_${uvScale.join('x')}`;
  if (matIds[key]) return matIds[key];
  const hex = (m.COLORS && m.COLORS[colorIdx]) || '#b8bfc7';
  const r = parseInt(hex.slice(1, 3), 16) / 255, g = parseInt(hex.slice(3, 5), 16) / 255, b = parseInt(hex.slice(5, 7), 16) / 255;
  // подмешиваем к белому, чтобы PBR-альбедо не уходило в грязь
  const mix = (c) => (c * 0.45 + 0.55).toFixed(3);
  const id = `mat_${key.replace(/[^\w]/g, '_')}`;
  matIds[key] = id;
  sub.push(`[sub_resource type="StandardMaterial3D" id="${id}"]
albedo_color = Color(${mix(r)}, ${mix(g)}, ${mix(b)}, 1)
albedo_texture = ExtResource("${texExt(kind, 'diffuse')}")
normal_enabled = true
normal_texture = ExtResource("${texExt(kind, 'normal')}")
normal_scale = 0.8
roughness_texture = ExtResource("${texExt(kind, 'arm')}")
roughness_texture_channel = 1
ao_enabled = true
ao_texture = ExtResource("${texExt(kind, 'arm')}")
ao_texture_channel = 0
ao_light_affect = 0.6
metallic = 0.0
uv1_scale = Vector3(${uvScale[0].toFixed(2)}, ${uvScale[1].toFixed(2)}, 1)
texture_filter = 4`);
  return id;
}

// метров на тайл — крупнее тайл, меньше «клеточки» на больших поверхностях.
// У пола тайл ВДВОЕ крупнее: на 66×54 м мелкий тайл читается сверху как рябь.
const TILE = 3.0;
const FLOOR_TILE = 6.5;

function box(name, cx, cz, w, d, h, colorIdx, yBase = 0, kind = 'wall') {
  const meshId = `mesh${subId++}`, shapeId = `shape${subId++}`;
  sub.push(`[sub_resource type="BoxMesh" id="${meshId}"]\nsize = Vector3(${w}, ${h}, ${d})`);
  sub.push(`[sub_resource type="BoxShape3D" id="${shapeId}"]\nsize = Vector3(${w}, ${h}, ${d})`);
  const y = yBase + h / 2;
  // масштаб UV по самой длинной горизонтали и высоте — тайл остаётся квадратным
  const uv = [Math.max(1, Math.round(Math.max(w, d) / TILE)), Math.max(1, Math.round(h / TILE))];
  nodes.push(`[node name="${name}" type="StaticBody3D" parent="Geometry" groups=["map_solid"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, ${cx}, ${y}, ${cz})

[node name="Mesh" type="MeshInstance3D" parent="Geometry/${name}"]
mesh = SubResource("${meshId}")
surface_material_override/0 = SubResource("${pbrMat(kind, colorIdx, uv)}")

[node name="Col" type="CollisionShape3D" parent="Geometry/${name}"]
shape = SubResource("${shapeId}")`);
}

// пол
{
  const meshId = `mesh${subId++}`, shapeId = `shape${subId++}`;
  sub.push(`[sub_resource type="BoxMesh" id="${meshId}"]\nsize = Vector3(${m.SIZE.w}, 1, ${m.SIZE.d})`);
  sub.push(`[sub_resource type="BoxShape3D" id="${shapeId}"]\nsize = Vector3(${m.SIZE.w}, 1, ${m.SIZE.d})`);
  const floorUv = [Math.round(m.SIZE.w / FLOOR_TILE), Math.round(m.SIZE.d / FLOOR_TILE)];
  const floorMat = pbrMat('floor', -1, floorUv);
  nodes.push(`[node name="Floor" type="StaticBody3D" parent="Geometry" groups=["map_solid"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)

[node name="Mesh" type="MeshInstance3D" parent="Geometry/Floor"]
mesh = SubResource("${meshId}")
surface_material_override/0 = SubResource("${floorMat}")

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
  box(`Crate${i}`, cx, cz, w, d, h, ci ?? 4, yb || 0, "wood");   // ящики — дерево
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
    box(`Stair${i}_${s}`, cx, cz, w, d, rise, 1, 0, "ground");  // ступени — камень
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

// ===== свет и окружение (G10) =====
// HDRI-небо (CC0, вендорено в assets/hdri/sky.hdr) вместо процедурного: даёт настоящее
// небесное освещение и отражения. Солнце БЕЗ пересвета — правило веб-саги про «яркое
// солнце» в регресс-зонах. SSAO/SSIL сажают геометрию в тени, иначе боксы «висят».
ext.push(`[ext_resource type="Texture2D" path="res://assets/hdri/sky.hdr" id="hdri_sky"]`);
sub.push(`[sub_resource type="PanoramaSkyMaterial" id="skymat"]
panorama = ExtResource("hdri_sky")
energy_multiplier = 1.0`);
sub.push(`[sub_resource type="Sky" id="sky"]
sky_material = SubResource("skymat")
radiance_size = 3`);
sub.push(`[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 3
ambient_light_energy = 1.0
reflected_light_source = 2
tonemap_mode = 3
tonemap_white = 6.0
ssao_enabled = true
ssao_radius = 1.4
ssao_intensity = 1.6
ssao_power = 1.5
ssil_enabled = true
ssil_intensity = 0.55
glow_enabled = true
glow_intensity = 0.55
glow_strength = 0.9
glow_bloom = 0.05
glow_hdr_threshold = 1.15
adjustment_enabled = true
adjustment_contrast = 1.06
adjustment_saturation = 1.08`);

const out = `[gd_scene load_steps=${ext.length + sub.length + 1} format=3]

${ext.join('\n')}

${sub.join('\n\n')}

[node name="Map_${m.id}" type="Node3D"]
metadata/map_meta = ${JSON.stringify(JSON.stringify(meta))}

[node name="Env" type="WorldEnvironment" parent="."]
environment = SubResource("env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.353553, 0.353553, 0, 0.707107, 0.707107, -0.5, -0.612372, 0.612372, 0, 14, 0)
light_energy = 1.0
light_angular_distance = 0.6
shadow_enabled = true
shadow_bias = 0.04
shadow_normal_bias = 1.4
directional_shadow_mode = 2
directional_shadow_split_1 = 0.06
directional_shadow_split_2 = 0.18
directional_shadow_split_3 = 0.45
directional_shadow_max_distance = 120.0

[node name="Geometry" type="Node3D" parent="."]

[node name="Spawns" type="Node3D" parent="."]

[node name="Sites" type="Node3D" parent="."]

${nodes.join('\n\n')}
`;

const dest = path.join(__dirname, '..', 'scenes', 'maps', `${m.id}.tscn`);
writeFileSync(dest, out.replace(/\r?\n/g, '\n'), 'utf8');
console.log(`${m.id}.tscn записан: боксов=${(m.walls || []).length + (m.crates || []).length}, стен-AABB=${wallsAabb.length}, спавнов=${m.spawns.attack.pts.length + m.spawns.defend.pts.length}`);
