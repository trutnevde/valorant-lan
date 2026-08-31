# Стрела Совы (хост): летит from→to за travel, на попадании — эффект по режиму:
# shock — урон по области (рикошет уже посчитан кастером: to = точка после отскока);
# mark — реванул врагов в SOVA_MARK_R по LOS 5с (сбиваемая: тело стрелы стреляемо у всех);
# drone — скан SOVA_DRONE_R, реванул 2.5с.
extends Node

var data := {}  # {fx,fy,fz, tx,ty,tz, mode, team, owner_path, cname}
var _t := 0.0
var _travel := 0.3
var shot_down := false


func _ready() -> void:
	var from := Vector3(data["fx"], data["fy"], data["fz"])
	var to := Vector3(data["tx"], data["ty"], data["tz"])
	_travel = clampf(from.distance_to(to) * 0.018, 0.12, 0.8)  # web travel-формула


func _physics_process(dt: float) -> void:
	_t += dt
	if shot_down:
		get_node("/root/Fx").call("_fx_broadcast", "clone_gone", { "cname": String(data["cname"]) })
		queue_free()
		return
	if _t < _travel:
		return
	var to := Vector3(data["tx"], data["ty"], data["tz"])
	var fx := get_node("/root/Fx")
	var owner_node := get_node_or_null(NodePath(String(data["owner_path"])))
	match String(data["mode"]):
		"shock":
			for c in get_tree().get_nodes_in_group("combatants"):
				var node := c as Node3D
				if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
					continue
				if Vector2(node.global_position.x - to.x, node.global_position.z - to.z).length() < float(Balance.ABILITY["SOVA_SHOCK_R"]):
					fx.call("apply_damage", node, int(Balance.ABILITY["SOVA_SHOCK_DMG"]), owner_node, "sovaShock")
		"mark", "drone":
			var r := float(Balance.ABILITY["SOVA_DRONE_R"] if String(data["mode"]) == "drone" else Balance.ABILITY["SOVA_MARK_R"])
			var dur := float(Balance.ABILITY["SOVA_DRONE_REVEAL"] if String(data["mode"]) == "drone" else Balance.ABILITY["SOVA_MARK_REVEAL"])
			var targets: Array = []
			for c in get_tree().get_nodes_in_group("combatants"):
				var node := c as Node3D
				if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
					continue
				if Vector2(node.global_position.x - to.x, node.global_position.z - to.z).length() >= r:
					continue
				if not _los(to + Vector3(0, 1.3, 0), node.global_position + Vector3(0, 1.2, 0)):
					continue  # разведка только по прямой видимости — никакой телепатии
				targets.append(String(node.get_path()))
			if not targets.is_empty():
				fx.call("_fx_broadcast", "reveal", { "targets": targets, "dur": dur, "team": String(data["team"]) })
	fx.call("_fx_broadcast", "clone_gone", { "cname": String(data["cname"]) })
	queue_free()


func _los(a: Vector3, b: Vector3) -> bool:
	if bool(get_node("/root/Smokes").call("seg_blocked", a, b)):
		return false
	var space := (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var res := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
	return res.is_empty() or (res["collider"] as Node).is_in_group("combatants")
