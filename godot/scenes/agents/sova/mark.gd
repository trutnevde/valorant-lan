# Сова Q «Метка-стрела» — разведстрела: враги у попадания подсвечены (LOS).
# ТВИСТ: сбиваемая в полёте (fx спавнит стреляемую стрелу у всех, cname связывает).
class_name SovaMark
extends Ability


func _init() -> void:
	char_id = "sova"
	key = "Q"


func cast() -> void:
	var origin := player.eye_pos()
	var p := ground_point(35.0)
	var cname := "Arrow_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()]
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/sova_arrow.gd",
		"fx": origin.x, "fy": origin.y, "fz": origin.z,
		"tx": p.x, "ty": p.y, "tz": p.z,
		"mode": "mark", "team": player.team,
		"owner_path": String(player.get_path()),
		"cname": cname, "shootable": true,
	})
