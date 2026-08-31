# Кит Артемия — 4 компонента-способности (числа из balance.gd, механики web-паритет).
class_name ArtemiyFlash
extends Ability


func _init() -> void:
	char_id = "artemiy"
	key = "C"


func cast() -> void:
	var eye := player.eye_pos()
	var dir := player.aim_dir()
	get_node("/root/Fx").call("cast", "flash", {
		"fx": eye.x, "fy": eye.y, "fz": eye.z,
		"dx": dir.x, "dy": dir.y, "dz": dir.z,
		"owner_path": String(player.get_path()),
	})
