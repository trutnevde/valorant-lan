# Сова X «Ярость охотника» (УЛЬТА): 3 залпа по линии взгляда — пробивают стены.
class_name SovaFury
extends Ability


func _init() -> void:
	char_id = "sova"
	key = "X"


func cast() -> void:
	var dir := player.aim_dir()
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/fury.gd",
		"fx": player.global_position.x, "fz": player.global_position.z,
		"dx": dir.x, "dz": dir.z,
		"team": player.team, "owner_path": String(player.get_path()),
	})
