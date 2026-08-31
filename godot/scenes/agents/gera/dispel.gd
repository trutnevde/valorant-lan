# Гера C «Развеятель» — убирает ВРАЖЕСКИЕ дымы в радиусе + блок новых на пару секунд.
class_name GeraDispel
extends Ability


func _init() -> void:
	char_id = "gera"
	key = "C"


func cast() -> void:
	var p := ground_point(22.0)
	get_node("/root/Fx").call("cast", "dispel", {
		"x": p.x, "z": p.z, "team": player.team,
	})
