# «Табун» Конилия (хост): линия STAMPEDE_LEN×WIDTH — оглушает всех на пути. БЕЗ урона (канон).
extends Node

var data := {}  # {fx,fz, dx,dz, team}


func _ready() -> void:
	var a := Vector2(data["fx"], data["fz"])
	var dir := Vector2(data["dx"], data["dz"]).normalized()
	var b := a + dir * float(Balance.ABILITY["STAMPEDE_LEN"])
	var fx := get_node("/root/Fx")
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
			continue
		var q := Vector2(node.global_position.x, node.global_position.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		if q.distance_to(a + ab * t) < float(Balance.ABILITY["STAMPEDE_WIDTH"]):
			fx.call("stun_target", node, float(Balance.ABILITY["STAMPEDE_STUN"]))
	queue_free()
