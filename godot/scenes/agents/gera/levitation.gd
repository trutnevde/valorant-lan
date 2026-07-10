# Гера X «Невесомость» (УЛЬТА): купол — враги теряют опору и всплывают (слоу, мажут).
class_name GeraLevitation
extends Ability


func _init() -> void:
	char_id = "gera"
	key = "X"


func cast() -> void:
	var p := ground_point(9.0)
	get_node("/root/Fx").call("cast", "levit", {
		"x": p.x, "z": p.z, "team": player.team,
		"owner_path": String(player.get_path()),
	})
