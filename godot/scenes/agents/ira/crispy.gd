# Ира Q «Криспи-стена» — простреливаемая: врагов замедляет, союзников лечит на проходе.
class_name IraCrispy
extends Ability


func _init() -> void:
	char_id = "ira"
	key = "Q"


func cast() -> void:
	var flat := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var c := player.global_position + flat * 2.2
	var perp := Vector3(-flat.z, 0, flat.x)
	var half := float(Balance.ABILITY["CRISPY_LEN"]) / 2.0
	var a := c - perp * half
	var b := c + perp * half
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/util_zone.gd",
		"shape": "seg", "ax": a.x, "az": a.z, "bx": b.x, "bz": b.z, "r": 1.4,
		"dur": float(Balance.ABILITY["CRISPY_TIME"]),
		"slow": float(Balance.ABILITY["CRISPY_SLOW"]), "heal_rate": float(Balance.ABILITY["CRISPY_HEAL"]),
		"team": player.team, "owner_path": String(player.get_path()),
	})
	fx.call("cast", "crispy_vis", { "ax": a.x, "az": a.z, "bx": b.x, "bz": b.z })
