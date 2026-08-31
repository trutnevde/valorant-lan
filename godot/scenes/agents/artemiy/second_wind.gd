# Артемий X «Второе дыхание» (УЛЬТА): метка на 10 с — умер? вернулся на неё с полным HP.
class_name ArtemiySecondWind
extends Ability


func _init() -> void:
	char_id = "artemiy"
	key = "X"


func cast() -> void:
	player.ult_mark_pos = player.global_position
	player.ult_mark_until = Time.get_ticks_msec() / 1000.0 + float(Balance.ABILITY["PHOENIX_ULT_TIME"])
	get_node("/root/Fx").call("cast", "ult_mark", {
		"x": player.global_position.x, "z": player.global_position.z,
		"owner_path": String(player.get_path()),
	})
