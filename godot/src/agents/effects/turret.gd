# Турель Санька (хост-логика): каждые TURRET_TICK бьёт ближайшего видимого врага
# на TURRET_DMG. Тело турели (стреляемое, TURRET_HP) спавнится у всех через Fx.
extends Node

var data := {}  # {x,z, team, owner_path, cname}
var hp := 60
var _next := 0.0


func _ready() -> void:
	hp = int(Balance.ABILITY["TURRET_HP"])


func _physics_process(_dt: float) -> void:
	if hp <= 0:
		get_node("/root/Fx").call("_fx_broadcast", "clone_gone", { "cname": String(data["cname"]) })
		queue_free()
		return
	var t := Time.get_ticks_msec() / 1000.0
	if t < _next:
		return
	_next = t + float(Balance.ABILITY["TURRET_TICK"])
	var pos := Vector3(data["x"], 1.0, data["z"])
	var best: Node3D = null
	var bd := float(Balance.ABILITY["TURRET_R"])
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0 or String(node.get("team")) == String(data["team"]):
			continue
		var d := Vector2(node.global_position.x - pos.x, node.global_position.z - pos.z).length()
		if d < bd and _los(pos, node.global_position + Vector3(0, 1.2, 0)):
			bd = d
			best = node
	if best:
		var fx := get_node("/root/Fx")
		fx.call("apply_damage", best, int(Balance.ABILITY["TURRET_DMG"]), get_node_or_null(NodePath(String(data["owner_path"]))), "turret")


func take_body_hit(dmg: int) -> void:
	hp -= dmg


func _los(a: Vector3, b: Vector3) -> bool:
	if bool(get_node("/root/Smokes").call("seg_blocked", a, b)):
		return false
	var space := (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var res := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
	return res.is_empty() or (res["collider"] as Node).is_in_group("combatants")
