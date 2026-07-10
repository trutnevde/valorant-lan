# Фафик Q «Двойник» — рывок 7 м вперёд, на месте старта клон-приманка (5 с).
# ТВИСТ Эпохи 15: клон ЗЕРКАЛИТ движение игрока. Лопнули — стан врагам вокруг.
class_name FafikTwin
extends Ability


func _init() -> void:
	char_id = "fafik"
	key = "Q"


func cast() -> void:
	var start := player.global_position
	# рывок вперёд как у Макса, но фикс. 7 м (TWIN_DASH)
	var dir := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	var dist := float(Balance.ABILITY["TWIN_DASH"])
	for i in 10:
		player.move_and_collide(dir * (dist / 10.0))
	get_node("/root/Fx").call("cast", "clone_decoy", {
		"x": start.x, "z": start.z, "dirx": 0.0, "dirz": 0.0,
		"mode": "stand", "life": float(Balance.ABILITY["TWIN_DECOY_TIME"]),
		"owner_path": String(player.get_path()),
		"cname": "Clone_twin_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()],
	})
