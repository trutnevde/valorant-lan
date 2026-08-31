# Санёк E «Кислота» — лужа: урон и замедление.
class_name SanekAcid
extends Ability


func _init() -> void:
	char_id = "sanek"
	key = "E"


func cast() -> void:
	var p := ground_point(18.0)
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/util_zone.gd",
		"shape": "circle", "x": p.x, "z": p.z, "r": float(Balance.ABILITY["ACID_R"]),
		"dur": float(Balance.ABILITY["ACID_TIME"]), "dps": float(Balance.ABILITY["ACID_DPS"]),
		"slow": float(Balance.ABILITY["ACID_SLOW"]), "weapon": "acid",
		"team": player.team, "owner_path": String(player.get_path()),
	})
	fx.call("cast", "fire_zone_vis_acid", { "x": p.x, "z": p.z })
