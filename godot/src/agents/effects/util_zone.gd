# Универсальная зона (хост): круг или сегмент; врагам dps+слоу, союзникам хил;
# опциональная задержка старта (орбиталка). Покрывает кислоту/подкову/орбиталку/
# криспи-стену/банкет — числа приходят из balance через кастера.
extends Node

var data := {}  # {shape:"circle"|"seg", x,z | ax,az,bx,bz, r, dur, delay?, dps?, slow?, slow_dur?,
#                 heal_rate?, team, owner_path, banquet?: bool}
var _life := 0.0
var _acc := {}


func _physics_process(dt: float) -> void:
	_life += dt
	var delay := float(data.get("delay", 0.0))
	if _life < delay:
		return
	if _life >= delay + float(data["dur"]):
		queue_free()
		return
	var fx := get_node("/root/Fx")
	var owner_node := get_node_or_null(NodePath(String(data.get("owner_path", ""))))
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or not _inside(node.global_position):
			continue
		var ally := String(node.get("team")) == String(data["team"])
		if ally:
			if data.has("heal_rate"):
				_tick(node, float(data["heal_rate"]) * dt, true, fx, owner_node)
			if bool(data.get("banquet", false)):
				node.set("banquet_until", Time.get_ticks_msec() / 1000.0 + 0.3)  # +скорость, пока внутри
		else:
			if data.has("dps"):
				_tick(node, float(data["dps"]) * dt, false, fx, owner_node)
			if data.has("slow") and node.has_method("apply_slow"):
				var n := NetHub.node()
				if node is FpsPlayer and NetHub.online() and n and (node as Node).get_multiplayer_authority() != 1:
					n.rpc_id((node as Node).get_multiplayer_authority(), "slow_self", float(data["slow"]), float(data.get("slow_dur", 0.4)))
				else:
					node.call("apply_slow", float(data["slow"]), float(data.get("slow_dur", 0.4)))


func _tick(node: Node, amount: float, is_heal: bool, fx: Node, owner_node: Node) -> void:
	var k := node.get_instance_id()
	_acc[k] = float(_acc.get(k, 0.0)) + amount
	if _acc[k] >= 1.0:
		var whole := int(_acc[k])
		_acc[k] = float(_acc[k]) - whole
		if is_heal:
			fx.call("apply_heal", node, whole)
		else:
			fx.call("apply_damage", node, whole, owner_node, String(data.get("weapon", "zone")))


func _inside(p: Vector3) -> bool:
	if String(data.get("shape", "circle")) == "seg":
		var a := Vector2(data["ax"], data["az"])
		var b := Vector2(data["bx"], data["bz"])
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		return q.distance_to(a + ab * t) < float(data.get("r", 1.4)) and p.y < 2.6
	return Vector2(p.x - float(data["x"]), p.z - float(data["z"])).length() < float(data["r"]) and p.y < 2.6
