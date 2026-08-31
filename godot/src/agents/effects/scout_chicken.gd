# «Куриный дозор» Иры (хост): цыплёнок бежит по прямой SCOUT_LIFE секунд,
# палит врагов в SCOUT_RANGE на SCOUT_REVEAL (LOS). Визуал — жёлтый бегун у всех.
extends Node

var data := {}  # {x,z, dirx,dirz, team, cname}
var _life := 0.0
var _pos := Vector3.ZERO
var _ping_at := {}


func _ready() -> void:
	_pos = Vector3(data["x"], 0, data["z"])


func _physics_process(dt: float) -> void:
	_life += dt
	if _life >= float(Balance.ABILITY["SCOUT_LIFE"]):
		get_node("/root/Fx").call("_fx_broadcast", "clone_gone", { "cname": String(data["cname"]) })
		queue_free()
		return
	var dir := Vector3(data["dirx"], 0, data["dirz"]).normalized()
	# стены останавливают бег (но не жизнь — кудахчет на месте)
	var space := (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var probe := space.intersect_ray(PhysicsRayQueryParameters3D.create(_pos + Vector3(0, 0.4, 0), _pos + Vector3(0, 0.4, 0) + dir * 0.6))
	if probe.is_empty():
		_pos += dir * float(Balance.ABILITY["SCOUT_SPEED"]) * dt
	var t := Time.get_ticks_msec() / 1000.0
	var targets: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
			continue
		if Vector2(node.global_position.x - _pos.x, node.global_position.z - _pos.z).length() >= float(Balance.ABILITY["SCOUT_RANGE"]):
			continue
		if not _los(_pos + Vector3(0, 0.5, 0), node.global_position + Vector3(0, 1.2, 0)):
			continue
		if t > float(_ping_at.get(node.get_instance_id(), 0.0)):
			_ping_at[node.get_instance_id()] = t + float(Balance.ABILITY["SCOUT_REVEAL"]) * 0.8
			targets.append(String(node.get_path()))
	var fx := get_node("/root/Fx")
	if not targets.is_empty():
		fx.call("_fx_broadcast", "reveal", { "targets": targets, "dur": float(Balance.ABILITY["SCOUT_REVEAL"]), "team": String(data["team"]) })
	fx.call("_fx_broadcast", "chicken_move", { "cname": String(data["cname"]), "x": _pos.x, "z": _pos.z })


func _los(a: Vector3, b: Vector3) -> bool:
	if bool(get_node("/root/Smokes").call("seg_blocked", a, b)):
		return false
	var space := (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var res := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
	return res.is_empty() or (res["collider"] as Node).is_in_group("combatants")
