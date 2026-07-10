# Гера E «Воронка» — конус перед собой стягивает врагов к центру.
class_name GeraVortex
extends Ability


func _init() -> void:
	char_id = "gera"
	key = "E"


func cast() -> void:
	var dir := player.aim_dir()
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/vortex.gd",
		"fx": player.global_position.x, "fz": player.global_position.z,
		"dx": dir.x, "dz": dir.z, "team": player.team,
	})
