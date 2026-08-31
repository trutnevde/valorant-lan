# Ира E «Буфет лечения» — облако пара: +50 HP союзникам в 8м у точки прицела.
# ⚠ Отклонение (честно): подбор ведёрка для перезарядки (1 раз/раунд) — в G11-полише.
class_name IraBuffet
extends Ability


func _init() -> void:
	char_id = "ira"
	key = "E"


func cast() -> void:
	var p := ground_point(14.0)
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/buffet_logic.gd",
		"x": p.x, "z": p.z, "team": player.team,
	})
