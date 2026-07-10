# Конилий Q «Ржание» — оглушительное ржание перед собой: контузит и ослепляет (флеш-конус).
class_name KoniliyNeigh
extends Ability


func _init() -> void:
	char_id = "koniliy"
	key = "Q"


func cast() -> void:
	var eye := player.eye_pos()
	var dir := player.aim_dir()
	get_node("/root/Fx").call("cast", "flash", {
		"fx": eye.x, "fy": eye.y, "fz": eye.z,
		"dx": dir.x, "dy": dir.y, "dz": dir.z,
		"owner_path": String(player.get_path()),
	})
