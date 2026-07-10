# «Ярость охотника» Совы (хост): 3 залпа энергии по линии — СКВОЗЬ стены (LOS не нужен).
extends Node

var data := {}  # {fx,fz, dx,dz, team, owner_path}
var _wave := 0
var _next := 0.0


func _physics_process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t < _next:
		return
	_wave += 1
	_next = t + 0.32  # интервал залпов (web)
	var a := Vector2(data["fx"], data["fz"])
	var dir := Vector2(data["dx"], data["dz"]).normalized()
	var b := a + dir * float(Balance.ABILITY["SOVA_FURY_LEN"])
	var fx := get_node("/root/Fx")
	var owner_node := get_node_or_null(NodePath(String(data["owner_path"])))
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
			continue
		var q := Vector2(node.global_position.x, node.global_position.z)
		var ab := b - a
		var tt := clampf((q - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		if q.distance_to(a + ab * tt) < float(Balance.ABILITY["SOVA_FURY_WIDTH"]):
			fx.call("apply_damage", node, int(Balance.ABILITY["SOVA_FURY_DMG"]), owner_node, "sovaFury")
	if _wave >= int(Balance.ABILITY["SOVA_FURY_WAVES"]):
		queue_free()
