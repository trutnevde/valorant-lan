# Артемий Q «Огонёк» — зона огня в точке прицела: жжёт врагов, лечит Артемия (+твист лоу-HP).
class_name ArtemiyFireball
extends Ability


func _init() -> void:
	char_id = "artemiy"
	key = "Q"


func cast() -> void:
	var p := ground_point(22.0)
	get_node("/root/Fx").call("cast", "fire_zone", {
		"x": p.x, "z": p.z,
		"owner_path": String(player.get_path()),
	})
