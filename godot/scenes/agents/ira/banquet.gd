# Ира X «Финальный банкет» (УЛЬТА): купол — +30 мгновенно, реген 10/с, +15% скорость,
# ТВИСТ: мини-рес одного павшего союзника. Скрытие от детекта — G11 (честно).
class_name IraBanquet
extends Ability


func _init() -> void:
	char_id = "ira"
	key = "X"


func cast() -> void:
	var p := ground_point(9.0)
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/banquet_logic.gd",
		"x": p.x, "z": p.z, "team": player.team,
		"owner_path": String(player.get_path()),
	})
	fx.call("cast", "banquet_dome", { "x": p.x, "z": p.z })
