# «Рентген» (хост): собрать всех живых врагов и подсветить команде на XRAY_TIME (без LOS — глобально).
extends Node

var data := {}  # {team}


func _ready() -> void:
	var targets: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node and int(node.get("hp")) > 0 and String(node.get("team")) != String(data["team"]):
			targets.append(String(node.get_path()))
	if not targets.is_empty():
		get_node("/root/Fx").call("_fx_broadcast", "reveal", {
			"targets": targets, "dur": float(Balance.ABILITY["XRAY_TIME"]), "team": String(data["team"]),
		})
	queue_free()
