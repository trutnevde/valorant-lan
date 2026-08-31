# Артемий E «Стена огня» — стена пламени 16 м вперёд от игрока.
class_name ArtemiyFirewall
extends Ability


func _init() -> void:
	char_id = "artemiy"
	key = "E"


func cast() -> void:
	var fwd := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var a := player.global_position + fwd * 1.5
	var b := a + fwd * float(Balance.ABILITY["WALL_LEN"])
	get_node("/root/Fx").call("cast", "fire_wall", {
		"ax": a.x, "az": a.z, "bx": b.x, "bz": b.z,
		"owner_path": String(player.get_path()),
	})
