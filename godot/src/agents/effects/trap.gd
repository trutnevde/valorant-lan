# Сигналка Санька (хост): датчик на полу — враг в TRAP_R → подсвечен TRAP_REVEAL
# + ТВИСТ: замедлен (TRAP_SLOW на TRAP_SLOW_TIME). Одноразовая.
extends Node

var data := {}  # {x,z, team, cname}


func _physics_process(_dt: float) -> void:
	var pos := Vector3(data["x"], 0, data["z"])
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
			continue
		if Vector2(node.global_position.x - pos.x, node.global_position.z - pos.z).length() >= float(Balance.ABILITY["TRAP_R"]):
			continue
		var fx := get_node("/root/Fx")
		fx.call("_fx_broadcast", "reveal", {
			"targets": [String(node.get_path())], "dur": float(Balance.ABILITY["TRAP_REVEAL"]), "team": String(data["team"]),
		})
		# твист: растяжка замедляет засечённого
		var n := NetHub.node()
		if node is FpsPlayer and NetHub.online() and n and (node as Node).get_multiplayer_authority() != 1:
			n.rpc_id((node as Node).get_multiplayer_authority(), "slow_self", float(Balance.ABILITY["TRAP_SLOW"]), float(Balance.ABILITY["TRAP_SLOW_TIME"]))
		elif node.has_method("apply_slow"):
			node.call("apply_slow", float(Balance.ABILITY["TRAP_SLOW"]), float(Balance.ABILITY["TRAP_SLOW_TIME"]))
		fx.call("_fx_broadcast", "clone_gone", { "cname": String(data["cname"]) })
		queue_free()
		return
