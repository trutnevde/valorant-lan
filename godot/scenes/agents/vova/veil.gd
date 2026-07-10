# Вова E «Завеса» — стена из трёх дымов перед собой (зазор SMOKE_WALL_GAP).
class_name VovaVeil
extends Ability


func _init() -> void:
	char_id = "vova"
	key = "E"


func cast() -> void:
	var flat := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var center := player.global_position + flat * 7.0
	var perp := Vector3(-flat.z, 0, flat.x)
	var gap := float(Balance.ABILITY["SMOKE_WALL_GAP"])
	var fx := get_node("/root/Fx")
	for off: float in [-gap, 0.0, gap]:
		var p: Vector3 = center + perp * off
		fx.call("cast", "smoke", { "x": p.x, "z": p.z, "team": player.team, "stink": false })
