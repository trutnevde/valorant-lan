# Крюк Дениса — ЛЕТЯЩИЙ снаряд (логика, хост).
#
# Было: ульта проверяла мгновенный рейкаст в can_cast() и без попадания просто не
# применялась — промахнуться было НЕВОЗМОЖНО, а COCOON_SPEED (45) не использовался вовсе.
# Теперь крюк летит: попал во врага — кокон, попал в стену или вышел за COCOON_RANGE —
# промах, и ульта потрачена. Это возвращает ульте цену ошибки.
extends Node

var data := {}  # {fx,fy,fz, dx,dy,dz, by_path, cname}

var _pos := Vector3.ZERO
var _dir := Vector3.FORWARD
var _travelled := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	_pos = Vector3(data["fx"], data["fy"], data["fz"])
	_dir = Vector3(data["dx"], data["dy"], data["dz"]).normalized()
	# ЧЕСТНО: визуал крюка локальный. Покадрово слать позицию по сети — спам; отдельный
	# синк снаряда сделаем, если понадобится (в бою крюк живёт доли секунды).
	var scene := get_tree().current_scene
	if scene:
		_mesh = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		_mesh.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.75, 0.15, 0.12)
		m.emission_enabled = true
		m.emission = Color(0.85, 0.2, 0.15)
		_mesh.material_override = m
		scene.add_child(_mesh)
		_mesh.global_position = _pos


func _exit_tree() -> void:
	if _mesh and is_instance_valid(_mesh):
		_mesh.queue_free()


func _physics_process(dt: float) -> void:
	var scene := get_tree().current_scene as Node3D
	if scene == null:
		queue_free()
		return
	var step := _dir * float(Balance.ABILITY["COCOON_SPEED"]) * dt
	var space := _space()
	var q := PhysicsRayQueryParameters3D.create(_pos, _pos + step)
	var by := get_node_or_null(NodePath(String(data.get("by_path", ""))))
	if by is CollisionObject3D:
		q.exclude = [(by as CollisionObject3D).get_rid()]
	var res := space.intersect_ray(q)
	if not res.is_empty():
		var c := res["collider"] as Node
		if c and c.is_in_group("combatants") and by and String(c.get("team")) != String(by.get("team")) and int(c.get("hp")) > 0:
			get_node("/root/Fx").call("cast", "cocoon", {
				"victim_path": String(c.get_path()),
				"by_path": String(data["by_path"]),
				"cname": String(data["cname"]),
			})
		queue_free()  # попал во врага или в геометрию — снаряд отработал
		return
	_pos += step
	_travelled += step.length()
	if _mesh:
		_mesh.global_position = _pos
	if _travelled >= float(Balance.ABILITY["COCOON_RANGE"]):
		queue_free()  # промах: крюк выдохся


# Физическое пространство берём у КОРНЕВОГО вьюпорта, а не у current_scene: снаряд —
# обычный Node без своего мира, а current_scene бывает пустым (headless-тесты), и тогда
# рейкаст молча падал, снаряд не двигался и пролетал «сквозь» стены.
func _space() -> PhysicsDirectSpaceState3D:
	return get_tree().root.world_3d.direct_space_state
