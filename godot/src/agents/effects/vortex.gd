# «Воронка» Геры (хост): конус перед кастером стягивает врагов к центру GERA_VORTEX_TIME сек.
# Боты тянутся серверно; люди — force_pull через их клиент. LOS-чек (стены прикрывают).
extends Node

var data := {}  # {fx,fz, dx,dz, team}
var _life := 0.0
var _victims: Array[NodePath] = []
var _center := Vector3.ZERO


func _ready() -> void:
	var f := Vector3(data["fx"], 0, data["fz"])
	var dir := Vector3(data["dx"], 0, data["dz"]).normalized()
	_center = f + dir * float(Balance.ABILITY["GERA_VORTEX_RANGE"]) * 0.55
	var half := float(Balance.ABILITY["GERA_VORTEX_HALFANG"])
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
			continue
		var to := node.global_position - f
		to.y = 0.0
		var d := to.length()
		if d > float(Balance.ABILITY["GERA_VORTEX_RANGE"]) or d < 0.3:
			continue
		if to.normalized().dot(dir) < cos(half):
			continue  # вне конуса
		if not _los(f + Vector3(0, 1.3, 0), node.global_position + Vector3(0, 1.2, 0)):
			continue
		_victims.append(node.get_path())
		if node is FpsPlayer:
			var n := NetHub.node()
			if NetHub.online() and n and (node as Node).get_multiplayer_authority() != 1:
				n.rpc_id((node as Node).get_multiplayer_authority(), "force_pull_self", _center, float(Balance.ABILITY["GERA_VORTEX_TIME"]), float(Balance.ABILITY["GERA_VORTEX_PULL"]))
			else:
				(node as FpsPlayer).force_pull(_center, float(Balance.ABILITY["GERA_VORTEX_TIME"]), float(Balance.ABILITY["GERA_VORTEX_PULL"]))


func _physics_process(dt: float) -> void:
	_life += dt
	if _life >= float(Balance.ABILITY["GERA_VORTEX_TIME"]):
		queue_free()
		return
	for vp in _victims:
		var node := get_node_or_null(vp) as Node3D
		if node == null or not (node is Bot) or int(node.get("hp")) <= 0:
			continue
		var d := _center - node.global_position
		d.y = 0.0
		if d.length() > 0.8:
			node.global_position += d.normalized() * float(Balance.ABILITY["GERA_VORTEX_PULL"]) * dt


func _los(a: Vector3, b: Vector3) -> bool:
	var space := (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var res := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
	return res.is_empty() or (res["collider"] as Node).is_in_group("combatants")
