# Денис E «Смрад» — вонючий смок: глушит обзор (и ботам), непрозрачен изнутри.
class_name DenisSmrad
extends Ability


func _init() -> void:
	char_id = "denis"
	key = "E"


func cast() -> void:
	var p := ground_point(22.0)
	get_node("/root/Fx").call("cast", "smoke", {
		"x": p.x, "z": p.z, "team": player.team, "stink": true,
	})
