# Санёк Q «Турель» — автотурель на точке прицела (до 6м): бьёт врагов в 20м, 60 HP.
class_name SanekTurret
extends Ability


func _init() -> void:
	char_id = "sanek"
	key = "Q"


func cast() -> void:
	var p := ground_point(6.0)
	var cname := "Turret_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()]
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/turret.gd",
		"x": p.x, "z": p.z, "team": player.team,
		"owner_path": String(player.get_path()), "cname": cname,
	})
	fx.call("cast", "turret_body", { "x": p.x, "z": p.z, "cname": cname })
