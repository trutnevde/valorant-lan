# Огонь Артемия (логика, хост): зона (круг r=4) или стена (сегмент 16м, ширина 1.3).
# Жжёт врагов FIRE_DPS, лечит владельца-Артемия FIRE_HEAL/с; свой огонь ему не вредит
# (пассивка «Саламандра»). ТВИСТ Эпохи 15: чем ниже HP — тем сильнее хил (×1..~2.3).
extends Node

var data := {}      # круг: {x,z, owner_path}; стена: {ax,az,bx,bz, owner_path}
var is_wall := false
var _life := 0.0
var _acc := {}      # node -> дробный урон/хил


func _physics_process(dt: float) -> void:
	_life += dt
	var dur := float(Balance.ABILITY["WALL_TIME"] if is_wall else Balance.ABILITY["FIRE_ZONE_TIME"])
	if _life >= dur:
		queue_free()
		return
	var owner_node := get_node_or_null(NodePath(String(data.get("owner_path", ""))))
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0:
			continue
		if not _inside(node.global_position):
			continue
		var fx := get_node("/root/Fx")
		if node == owner_node:
			# Артемий в своём огне: лечится, твист — сильнее на низком HP
			if String(node.get("char_id")) == "artemiy":
				var hp := float(node.get("hp"))
				var maxhp := float(Balance.RULES["BASE_HP"])
				var mult := 1.0 + (1.0 - hp / maxhp) * 1.3
				_tick_amount(node, float(Balance.ABILITY["FIRE_HEAL"]) * mult * dt, true, fx, owner_node)
		elif owner_node != null and String(node.get("team")) != String(owner_node.get("team")):
			_tick_amount(node, float(Balance.ABILITY["FIRE_DPS"]) * dt, false, fx, owner_node)


func _tick_amount(node: Node, amount: float, is_heal: bool, fx: Node, owner_node: Node) -> void:
	var k := node.get_instance_id()
	_acc[k] = float(_acc.get(k, 0.0)) + amount
	if _acc[k] >= 1.0:
		var whole := int(_acc[k])
		_acc[k] = float(_acc[k]) - whole
		if is_heal:
			fx.call("apply_heal", node, whole)
		else:
			fx.call("apply_damage", node, whole, owner_node, "fire")


func _inside(p: Vector3) -> bool:
	if is_wall:
		var a := Vector2(data["ax"], data["az"])
		var b := Vector2(data["bx"], data["bz"])
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		return q.distance_to(a + ab * t) < 1.3 and p.y < 2.6
	return Vector2(p.x - float(data["x"]), p.z - float(data["z"])).length() < float(Balance.ABILITY["FIRE_ZONE_R"]) and p.y < 2.6
