# Клон Фафика (логика+тело, хост): стреляемая приманка. Режимы:
# stand — стоит и ЗЕРКАЛИТ движение хозяина (твист Эпохи 15), run — бежит вперёд.
# Лопнули (hp<=0 от выстрела) — стан врагам вокруг (CLONE_POP_STUN, r=CLONE_POP_STUN_R).
class_name CloneDecoy
extends StaticBody3D

var data := {}  # {x,z, dirx,dirz, mode: "stand"|"run", owner_path, life, speed?, max_run?, cname}
var hp := 60
var _life := 0.0
var _ran := 0.0
var _owner_last := Vector3.INF


func _wall_ahead(dir: Vector3, dist: float) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	q.exclude = [get_rid()]
	var res := space.intersect_ray(q)
	return not res.is_empty() and not (res["collider"] is CloneDecoy)


func _ready() -> void:
	add_to_group("clones")
	global_position = Vector3(data["x"], 0, data["z"])
	# хитбоксы как у бота (голова/корпус/ноги)
	_shape("Body", _box(Vector3(0.52, 0.9, 0.3)), Vector3(0, 1.12, 0))
	_shape("Head", _sphere(0.2), Vector3(0, 1.68, 0))
	_shape("Leg", _box(Vector3(0.42, 0.9, 0.26)), Vector3(0, 0.45, 0))
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.5
	mesh.mesh = cap
	mesh.position.y = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.36, 0.55)
	mesh.material_override = mat
	add_child(mesh)


func _shape(nm: String, s: Shape3D, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = nm
	cs.shape = s
	cs.position = pos
	add_child(cs)


func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _physics_process(dt: float) -> void:
	_life += dt
	if _life >= float(data.get("life", 5.0)):
		if not NetHub.online() or multiplayer.is_server():
			get_node("/root/Fx").call("_fx_broadcast", "clone_gone", { "cname": String(name) })
		return
	if String(data.get("mode", "stand")) == "run":
		var dir := Vector3(data["dirx"], 0, data["dirz"]).normalized()
		var speed := float(data.get("speed", float(Balance.ABILITY["SWAP_SPEED"])))
		var step := speed * dt
		var max_run := float(data.get("max_run", 1e9))
		if _ran + step <= max_run:
			# не бежим сквозь стены: короткий рейкаст перед собой
			if not _wall_ahead(dir, step + 0.4):
				global_position += dir * step
				_ran += step
	else:
		# ТВИСТ: зеркалим движение хозяина (дельта его позиции за кадр)
		var owner_node := get_node_or_null(NodePath(String(data.get("owner_path", "")))) as Node3D
		if owner_node:
			if _owner_last != Vector3.INF:
				var d := owner_node.global_position - _owner_last
				global_position += Vector3(d.x, 0, d.z)
			_owner_last = owner_node.global_position


var _shape_part := {}


func part_at(shape_idx: int) -> String:
	if _shape_part.is_empty():
		var idx := 0
		for c in get_children():
			if c is CollisionShape3D:
				_shape_part[idx] = String(c.name).to_lower()
				idx += 1
	var nm: String = _shape_part.get(shape_idx, "body")
	return "head" if nm.contains("head") else ("leg" if nm.contains("leg") else "body")


func take_hit(dmg: int, _part: String, _attacker: Node = null, _weapon := "") -> void:
	if NetHub.online() and not multiplayer.is_server():
		return  # авторитет у хоста: локальная копия ждёт clone_gone
	hp -= dmg
	if hp > 0:
		return
	# лопнул: стан врагам хозяина вокруг (боты — stun_until; люди — RPC) + исчезнуть у всех
	var owner_node := get_node_or_null(NodePath(String(data.get("owner_path", ""))))
	var fx := get_node("/root/Fx")
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0:
			continue
		if owner_node and String(node.get("team")) == String(owner_node.get("team")):
			continue
		if Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z).length() < float(Balance.ABILITY["CLONE_POP_STUN_R"]):
			fx.call("stun_target", node, float(Balance.ABILITY["CLONE_POP_STUN"]))
	fx.call("_fx_broadcast", "clone_gone", { "cname": String(name) })
