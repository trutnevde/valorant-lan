# Ира C «Куриный дозор» — механический цыплёнок бежит вперёд и палит врагов.
class_name IraScout
extends Ability


func _init() -> void:
	char_id = "ira"
	key = "C"


func cast() -> void:
	var flat := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var cname := "Chicken_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()]
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/scout_chicken.gd",
		"x": player.global_position.x, "z": player.global_position.z,
		"dirx": flat.x, "dirz": flat.z,
		"team": player.team, "cname": cname,
	})
	fx.call("cast", "chicken", { "x": player.global_position.x, "z": player.global_position.z, "cname": cname })
