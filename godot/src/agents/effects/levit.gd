# «Невесомость» Геры (хост): купол GERA_ULT_R на GERA_ULT_TIME — враги внутри всплывают:
# слоу ×GERA_ULT_SLOW, боты мажут; подсветка команде Геры (лёгкие мишени).
extends Node

var data := {}  # {x,z, team, owner_path}
var _life := 0.0
var _ping := 0.0


func _physics_process(dt: float) -> void:
	_life += dt
	if _life >= float(Balance.ABILITY["GERA_ULT_TIME"]):
		queue_free()
		return
	var t := Time.get_ticks_msec() / 1000.0
	var do_ping := t > _ping
	if do_ping:
		_ping = t + 0.4
	var pos := Vector3(data["x"], 0, data["z"])
	var fx := get_node("/root/Fx")
	var n := NetHub.node()
	var targets: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
			continue
		if Vector2(node.global_position.x - pos.x, node.global_position.z - pos.z).length() >= float(Balance.ABILITY["GERA_ULT_R"]):
			continue
		if node is Bot:
			node.set("levit_until", t + 0.15)
		elif node is FpsPlayer and do_ping:
			if NetHub.online() and n and (node as Node).get_multiplayer_authority() != 1:
				n.rpc_id((node as Node).get_multiplayer_authority(), "levitate_self", 0.5)
			else:
				node.set("levit_until", t + 0.5)
				if (node as CharacterBody3D).is_on_floor():
					(node as CharacterBody3D).velocity.y = 2.2
		if do_ping:
			targets.append(String(node.get_path()))
	if do_ping and not targets.is_empty():
		fx.call("_fx_broadcast", "reveal", { "targets": targets, "dur": 0.5, "team": String(data["team"]) })
