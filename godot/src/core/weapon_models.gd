# Модели оружия. Один источник для первого лица (Viewmodel) и третьего (в руке CharRig):
# ствол выглядит одинаково у себя в руках и у врага. Раньше был один BoxMesh на все стволы.
#
# Один CC0-набор на всё — Quaternius «Ultimate Gun Pack» (FBX, цветные материалы, реальные
# пропорции: пистолеты, револьверы, ПП, дробовики, автоматы, буллпапы, снайперки, штык).
# Все модели пака лежат вдоль +X — таблица разворачивает их в -Z (вперёд по Godot) и
# масштабирует до реальной длины в метрах; корень узла — в центре габаритов.
class_name WeaponModels

const Q := "res://assets/models/weapons/qgun/"
const ROT_X_TO_FWD := Vector3(0, PI * 0.5, 0)  # +X модели → -Z

# {src: файл, len: длина в метрах}; разворот у всего пака одинаковый
const MODELS := {
	"classic":  { "src": Q + "Pistol_5.fbx", "len": 0.19 },
	"ghost":    { "src": Q + "Pistol_6.fbx", "len": 0.25 },
	"frenzy":   { "src": Q + "Pistol_4.fbx", "len": 0.22 },
	"sheriff":  { "src": Q + "Revolver_2.fbx", "len": 0.30 },
	"stinger":  { "src": Q + "SubmachineGun_3.fbx", "len": 0.44 },
	"spectre":  { "src": Q + "SubmachineGun_2.fbx", "len": 0.56 },
	"shorty":   { "src": Q + "Shotgun_SawedOff.fbx", "len": 0.52 },
	"bucky":    { "src": Q + "Shotgun_3.fbx", "len": 1.0 },
	"judge":    { "src": Q + "Shotgun_4.fbx", "len": 0.95 },
	"bulldog":  { "src": Q + "Bullpup_3.fbx", "len": 0.72 },
	"guardian": { "src": Q + "AssaultRifle2_4.fbx", "len": 1.0 },
	"phantom":  { "src": Q + "AssaultRifle2_2.fbx", "len": 0.84 },
	"vandal":   { "src": Q + "AssaultRifle_3.fbx", "len": 0.88 },
	"marshal":  { "src": Q + "SniperRifle_1.fbx", "len": 1.1 },
	"operator": { "src": Q + "SniperRifle_2.fbx", "len": 1.25 },
	"outlaw":   { "src": Q + "SniperRifle_4.fbx", "len": 1.15 },
	"ares":     { "src": Q + "AssaultRifle_5.fbx", "len": 1.0 },
	"odin":     { "src": Q + "AssaultRifle2_1.fbx", "len": 1.05 },
	"knife":    { "src": Q + "Bayonet.fbx", "len": 0.32 },
}

static var _cache := {}
static var _len_cache := {}


static func make(id: String) -> Node3D:
	var spec: Dictionary = MODELS.get(id, MODELS["knife"])
	var root := Node3D.new()
	root.name = "Gun_" + id
	var inner: Node3D = null
	var res = _load(String(spec["src"]))
	if res is PackedScene:
		inner = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		inner = mi
	if inner == null:
		return _fallback(root)
	# нормализация: разворот в -Z, масштаб до реальной длины, центр габаритов в корень
	inner.rotation = ROT_X_TO_FWD
	var raw_len := _measure_z(inner)
	var scale := float(spec["len"]) / maxf(0.001, raw_len)
	inner.scale = Vector3.ONE * scale
	root.add_child(inner)
	var box := local_aabb(root)
	inner.position = -(box.position + box.size * 0.5)
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
		var local := Transform3D.IDENTITY
		var k: Node = mi
		while k != n and k is Node3D:
			local = (k as Node3D).transform * local
			k = k.get_parent()
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


# AABB всех мешей узла в ЕГО локале (без его собственного transform) — для хвата и дула
static func local_aabb(n: Node3D) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var k: Node = m
		while k != n and k is Node3D:
			xf = (k as Node3D).transform * xf
			k = k.get_parent()
		var a := m.get_aabb()
		for i in 8:
			var c := xf * (a.position + Vector3(a.size.x * (i & 1), a.size.y * ((i >> 1) & 1), a.size.z * ((i >> 2) & 1)))
			lo = lo.min(c)
			hi = hi.max(c)
	if hi.x < lo.x:
		return AABB(Vector3.ZERO, Vector3.ONE * 0.3)
	return AABB(lo, hi - lo)


# запасной ствол, если модель не импортировалась: чтобы игра не падала без ассета
static func _fallback(root: Node3D) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.08, 0.4)
	mi.mesh = bm
	mi.position = Vector3(0, 0, -0.1)
	root.add_child(mi)
	_len_cache[String(root.name).trim_prefix("Gun_")] = 0.4
	return root
