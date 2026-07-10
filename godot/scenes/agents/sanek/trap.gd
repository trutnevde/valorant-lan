# Санёк C «Сигналка» — датчик под ногами: враг рядом → подсвечен + замедлен (твист).
class_name SanekTrap
extends Ability


func _init() -> void:
	char_id = "sanek"
	key = "C"


func cast() -> void:
	var cname := "Trap_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()]
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/trap.gd",
		"x": player.global_position.x, "z": player.global_position.z,
		"team": player.team, "cname": cname,
	})
	fx.call("cast", "trap_vis", {
		"x": player.global_position.x, "z": player.global_position.z,
		"team": player.team, "cname": cname,
	})
