# Денис Q «Нюх мясника» — мясо-приманка на точку прицела (до 16м).
class_name DenisScent
extends Ability


func _init() -> void:
	char_id = "denis"
	key = "Q"


func cast() -> void:
	var p := ground_point(16.0)
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/scent.gd",
		"x": p.x, "z": p.z, "team": player.team,
		"owner_path": String(player.get_path()),
	})
