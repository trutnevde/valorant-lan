# Санёк X «Рентген» (УЛЬТА): ГЛОБАЛЬНО — все враги подсвечены сквозь стены XRAY_TIME.
class_name SanekXray
extends Ability


func _init() -> void:
	char_id = "sanek"
	key = "X"


func cast() -> void:
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/xray_logic.gd",
		"team": player.team,
	})
