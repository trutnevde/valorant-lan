# Модели оружия. Один источник для первого лица (Viewmodel) и третьего (в руке CharRig):
# ствол выглядит одинаково у себя в руках и у врага. Раньше был один BoxMesh на все стволы.
#
# Два CC0-набора:
#  • Quaternius GunPack (OBJ + текстуры) — АК и винтовка: реалистичные силуэты для
#    автоматов, снайперок и пулемётов;
#  • Kenney Blaster Kit (GLB) — компактные стволы для пистолетов, ПП и дробовиков.
# Каждой модели — своя таблица: ось «вперёд» и реальная длина в метрах, чтобы всё смотрело
# в -Z (вперёд по Godot) и было в масштабе мира.
class_name WeaponModels

const Q := "res://assets/models/weapons/quaternius/"
const K := "res://assets/models/weapons/blaster/"

# {src: путь, len: длина в метрах, rot: разворот (эйлер), tex: текстура для OBJ}
const MODELS := {
	"ak":    { "src": Q + "ak47.obj",  "len": 0.88, "rot": Vector3(0, -PI * 0.5, 0), "tex": Q + "ak47Texture.png" },
	"rifle": { "src": Q + "Rifle.obj", "len": 1.18, "rot": Vector3(0, 0, 0),         "tex": Q + "RifleTexture.png" },
	"kb":    { "src": K + "blaster-b.glb", "len": 0.38 }, "kc": { "src": K + "blaster-c.glb", "len": 0.42 },
	"ki":    { "src": K + "blaster-i.glb", "len": 0.44 }, "ko": { "src": K + "blaster-o.glb", "len": 0.46 },
	"kh":    { "src": K + "blaster-h.glb", "len": 0.58 }, "kj": { "src": K + "blaster-j.glb", "len": 0.60 },
	"kl":    { "src": K + "blaster-l.glb", "len": 0.62 }, "kk": { "src": K + "blaster-k.glb", "len": 0.66 },
	"km":    { "src": K + "blaster-m.glb", "len": 0.70 },
}

const BY_WEAPON := {
	"classic": "kb", "ghost": "kc", "frenzy": "ki", "sheriff": "ko",
	"stinger": "kh", "spectre": "kj",
	"shorty": "kl", "bucky": "kk", "judge": "km",
	"bulldog": "ak", "phantom": "ak", "vandal": "ak", "guardian": "ak",
	"marshal": "rifle", "operator": "rifle", "outlaw": "rifle",
	"ares": "rifle", "odin": "rifle",
}

static var _cache := {}
static var _len_cache := {}


static func make(id: String) -> Node3D:
	var key: String = BY_WEAPON.get(id, "")
	if key == "":
		return _knife()
	var spec: Dictionary = MODELS[key]
	var root := Node3D.new()
	root.name = "Gun_" + id
	var inner: Node3D = null
	var res = _load(String(spec["src"]))
	if res is PackedScene:
		inner = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		if spec.has("tex"):
			var tex := load(String(spec["tex"])) as Texture2D
			for s in (res as Mesh).get_surface_count():
				var mat := StandardMaterial3D.new()
				mat.albedo_texture = tex
				mat.roughness = 0.6
				mat.metallic = 0.25
				mi.set_surface_override_material(s, mat)
		inner = mi
	if inner == null:
		return _knife()
	# нормализация: разворот в -Z и масштаб до реальной длины
	inner.rotation = spec.get("rot", Vector3.ZERO)
	var raw_len := _measure_z(inner)
	var scale := float(spec["len"]) / maxf(0.001, raw_len)
	inner.scale = Vector3.ONE * scale
	root.add_child(inner)
	_len_cache[id] = float(spec["len"])
	return root


static func _load(path: String):
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


# протяжённость модели вдоль Z ПОСЛЕ разворота (на вход — уже повёрнутый узел)
static func _measure_z(n: Node3D) -> float:
	var lo := INF
	var hi := -INF
	var xf := Transform3D(Basis.from_euler(n.rotation), Vector3.ZERO)
	var meshes: Array = []
	if n is MeshInstance3D:
		meshes.append(n)
	meshes.append_array(n.find_children("*", "MeshInstance3D", true, false))
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := mi.get_aabb()
		var local := mi.transform if mi != n else Transform3D.IDENTITY
		for i in 8:
			var c := a.position + Vector3(a.size.x * (i & 1), a.size.y * ((i >> 1) & 1), a.size.z * ((i >> 2) & 1))
			var p := xf * (local * c)
			lo = minf(lo, p.z)
			hi = maxf(hi, p.z)
	return hi - lo if hi > lo else 1.0


# длина ствола в метрах (для дульной вспышки)
static func length_of(node: Node3D) -> float:
	var id := String(node.name).trim_prefix("Gun_")
	return float(_len_cache.get(id, 0.5))


static func _knife() -> Node3D:
	var root := Node3D.new()
	root.name = "Gun_knife"
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.05, 0.30)
	blade.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.84, 0.88)
	m.metallic = 0.9
	m.roughness = 0.25
	blade.material_override = m
	blade.position = Vector3(0, 0, -0.18)
	root.add_child(blade)
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.035, 0.035, 0.12)
	grip.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.12, 0.1, 0.09)
	grip.material_override = gmat
	root.add_child(grip)
	_len_cache["knife"] = 0.3
	return root
