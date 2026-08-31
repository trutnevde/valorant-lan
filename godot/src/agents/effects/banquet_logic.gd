# «Финальный банкет» Иры (хост): мгновенный +30 союзникам в куполе, дальше зона
# регена/скорости (util_zone), + ТВИСТ Эпохи 15: мини-рес ОДНОГО павшего союзника (50% HP).
extends Node

var data := {}  # {x,z, team, owner_path}


func _ready() -> void:
	var pos := Vector3(data["x"], 0, data["z"])
	var fx := get_node("/root/Fx")
	var revived := false
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or String(node.get("team")) != String(data["team"]):
			continue
		var inside := Vector2(node.global_position.x - pos.x, node.global_position.z - pos.z).length() < float(Balance.ABILITY["BANQUET_R"])
		if not inside:
			continue
		if int(node.get("hp")) > 0:
			fx.call("apply_heal", node, int(Balance.ABILITY["BANQUET_INSTANT"]))
		elif not revived:
			revived = true
			_revive(node, pos)
	# зона регена + скорости на BANQUET_TIME
	var z: Node = (load("res://src/agents/effects/util_zone.gd") as GDScript).new()
	z.set("data", {
		"shape": "circle", "x": pos.x, "z": pos.z, "r": float(Balance.ABILITY["BANQUET_R"]),
		"dur": float(Balance.ABILITY["BANQUET_TIME"]), "heal_rate": float(Balance.ABILITY["BANQUET_REGEN"]),
		"team": String(data["team"]), "owner_path": String(data.get("owner_path", "")), "banquet": true,
	})
	get_tree().current_scene.add_child(z)
	queue_free()


func _revive(node: Node3D, pos: Vector3) -> void:
	# мини-рес: максимум 1 за применение (канон-предохранитель)
	node.set("hp", int(Balance.RULES["BASE_HP"]) / 2)
	node.set("dead", false)
	node.set("visible", true)
	if node is CollisionObject3D:
		(node as CollisionObject3D).set_collision_layer_value(1, true)
	if node.has_signal("hp_changed"):
		node.emit_signal("hp_changed", int(node.get("hp")))
	var n := NetHub.node()
	if node is FpsPlayer and NetHub.online() and n and (node as Node).get_multiplayer_authority() != 1:
		n.rpc_id((node as Node).get_multiplayer_authority(), "revive_self", pos + Vector3(1, 0.2, 0), int(node.get("hp")))
	elif node is FpsPlayer:
		(node as Node3D).global_position = pos + Vector3(1, 0.2, 0)
	else:
		(node as Node3D).global_position = pos + Vector3(1, 0.2, 0)
	if NetHub.online() and n:
		n.rpc("_sync_hp", node.get_path(), int(node.get("hp")))