# Конилий X «Табун» (УЛЬТА): линия оглушения по направлению взгляда. Урона НЕТ (канон).
class_name KoniliyStampede
extends Ability


func _init() -> void:
	char_id = "koniliy"
	key = "X"


func cast() -> void:
	var dir := player.aim_dir()
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/stampede.gd",
		"fx": player.global_position.x, "fz": player.global_position.z,
		"dx": dir.x, "dz": dir.z, "team": player.team,
	})
	fx.call("cast", "stampede_vis", {
		"fx": player.global_position.x, "fz": player.global_position.z,
		"dx": dir.x, "dz": dir.z,
	})
