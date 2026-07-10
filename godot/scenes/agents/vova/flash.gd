# Вова Q «Слепящий заряд» — быстрая вспышка прямо по курсу.
class_name VovaFlash
extends Ability


func _init() -> void:
	char_id = "vova"
	key = "Q"


func cast() -> void:
	var eye := player.eye_pos()
	var dir := player.aim_dir()
	get_node("/root/Fx").call("cast", "flash", {
		"fx": eye.x, "fy": eye.y, "fz": eye.z,
		"dx": dir.x, "dy": dir.y, "dz": dir.z,
		"owner_path": String(player.get_path()),
	})
