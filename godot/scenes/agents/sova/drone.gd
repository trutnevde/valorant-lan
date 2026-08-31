# Сова E «Дрон-филин» — скан вокруг точки попадания: реванул 22м на 2.5с (LOS).
class_name SovaDrone
extends Ability


func _init() -> void:
	char_id = "sova"
	key = "E"


func cast() -> void:
	var origin := player.eye_pos()
	var p := ground_point(30.0)
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/sova_arrow.gd",
		"fx": origin.x, "fy": origin.y, "fz": origin.z,
		"tx": p.x, "ty": p.y, "tz": p.z,
		"mode": "drone", "team": player.team,
		"owner_path": String(player.get_path()),
		"cname": "Arrow_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()],
	})
