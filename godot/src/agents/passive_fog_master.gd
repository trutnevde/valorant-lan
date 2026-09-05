# Пассивка Вовы «Хозяин тумана»: находясь в СВОЁМ (союзном) дыму, он видит силуэты
# союзников сквозь него. Врагов — нет: иначе это анти-смок ядро, которое уже признали
# имбовым у Геры и заменили на «Барометр».
#
# Реализация — маркер сквозь геометрию (no_depth_test) над союзником, как у реванулов,
# но в союзном цвете и только пока Вова стоит в дыму. Тик 10 Гц: чаще незачем, а поиск
# по группе combatants каждый кадр — лишняя работа (перф-бюджет, правило 6).
extends Node

const TICK := 0.1
const ALLY_R := 30.0  # дальше силуэт всё равно нечитаем

var player: FpsPlayer
var _acc := 0.0
var _marks := {}  # instance_id -> MeshInstance3D


func _ready() -> void:
	var n: Node = self
	while n != null and not (n is FpsPlayer):
		n = n.get_parent()
	player = n as FpsPlayer


func _physics_process(dt: float) -> void:
	if player == null or player.dead:
		_clear()
		return
	_acc += dt
	if _acc < TICK:
		return
	_acc = 0.0
	if not _in_own_smoke():
		_clear()
		return
	var seen := {}
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or node == player or int(node.get("hp")) <= 0:
			continue
		if String(node.get("team")) != player.team:
			continue  # только союзники — врагов сквозь дым не показываем
		if node.global_position.distance_to(player.global_position) > ALLY_R:
			continue
		seen[node.get_instance_id()] = true
		if not _marks.has(node.get_instance_id()):
			_marks[node.get_instance_id()] = _make_mark(node)
	# убрать маркеры тех, кто вышел из зоны/умер
	for id in _marks.keys():
		if not seen.has(id):
			var m: Node = _marks[id]
			if is_instance_valid(m):
				m.queue_free()
			_marks.erase(id)


func _in_own_smoke() -> bool:
	var sw := get_node_or_null("/root/Smokes")
	if sw == null:
		return false
	for s: Dictionary in (sw.get("smokes") as Array):
		if String(s["team"]) != player.team:
			continue
		var p: Vector3 = s["pos"]
		if player.global_position.distance_to(p) <= float(s["r"]):
			return true
	return false


func _make_mark(target: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.6
	m.mesh = cap
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.85, 1.0, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true  # сквозь дым — в этом и смысл пассивки
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	target.add_child(m)
	m.position = Vector3(0, 1.0, 0)
	return m


func _clear() -> void:
	for id in _marks.keys():
		var m: Node = _marks[id]
		if is_instance_valid(m):
			m.queue_free()
	_marks.clear()
