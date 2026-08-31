# Конилий C «Подкова» — зона: враги вязнут и получают урон.
class_name KoniliyHorseshoe
extends Ability


func _init() -> void:
	char_id = "koniliy"
	key = "C"


func cast() -> void:
	var p := ground_point(18.0)
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/util_zone.gd",
		"shape": "circle", "x": p.x, "z": p.z, "r": float(Balance.ABILITY["HORSESHOE_R"]),
		"dur": float(Balance.ABILITY["HORSESHOE_TIME"]), "dps": float(Balance.ABILITY["HORSESHOE_DPS"]),
		"slow": float(Balance.ABILITY["HORSESHOE_SLOW"]), "weapon": "horseshoe",
		"team": player.team, "owner_path": String(player.get_path()),
	})
	fx.call("cast", "fire_zone_vis_horseshoe", { "x": p.x, "z": p.z })
