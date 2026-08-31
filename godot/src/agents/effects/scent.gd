# «Нюх мясника» Дениса (хост): приманка живёт SCENT_LIFE, чует врагов в SCENT_R
# (раненых <SCENT_WOUND_HP — вдвое дальше), палит команде по LOS (стены + дым глушат).
extends Node

var data := {}  # {x,z, team, owner_path}
var _life := 0.0
var _ping_at := {}  # instance_id -> next allowed ping


func _physics_process(dt: float) -> void:
	_life += dt
	if _life >= float(Balance.ABILITY["SCENT_LIFE"]):
		queue_free()
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pos := Vector3(data["x"], 1.2, data["z"])
	var targets: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
			continue
		var d := Vector2(node.global_position.x - pos.x, node.global_position.z - pos.z).length()
		var wounded := int(node.get("hp")) < int(Balance.ABILITY["SCENT_WOUND_HP"])
		var range_m := float(Balance.ABILITY["SCENT_R"]) * (float(Balance.ABILITY["SCENT_BLOOD_MUL"]) if wounded else 1.0)
		if d >= range_m:
			continue
		if not _los(pos, node.global_position + Vector3(0, 1.2, 0)):
			continue  # не палит сквозь стены/дым (серверная проверка — паритет)
		if t > float(_ping_at.get(node.get_instance_id(), 0.0)):
			_ping_at[node.get_instance_id()] = t + float(Balance.ABILITY["SCENT_REVEAL"]) * 0.8
			targets.append(String(node.get_path()))
	if not targets.is_empty():
		get_node("/root/Fx").call("_fx_broadcast", "reveal", {
			"targets": targets, "dur": float(Balance.ABILITY["SCENT_REVEAL"]), "team": String(data["team"]),
		})


func _los(a: Vector3, b: Vector3) -> bool:
	if bool(get_node("/root/Smokes").call("seg_blocked", a, b)):
		return false
	var space := (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var res := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
	return res.is_empty() or (res["collider"] as Node).is_in_group("combatants")
