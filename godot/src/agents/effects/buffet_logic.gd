# «Буфет лечения» (хост): мгновенный +BUFFET_HEAL союзникам в BUFFET_R.
extends Node

var data := {}  # {x,z, team}


func _ready() -> void:
	var pos := Vector3(data["x"], 0, data["z"])
	var fx := get_node("/root/Fx")
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) != String(data["team"]):
			continue
		if Vector2(node.global_position.x - pos.x, node.global_position.z - pos.z).length() < float(Balance.ABILITY["BUFFET_R"]):
			fx.call("apply_heal", node, int(Balance.ABILITY["BUFFET_HEAL"]))
	queue_free()
