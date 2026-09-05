# Вова X «Орбитальный удар» (УЛЬТА) — наводится КЛИКОМ ПО ТАКТИЧЕСКОЙ КАРТЕ, как в вебе
# (G9 закрыл заглушку «по точке прицела»). Задержка 1.4с, затем 3с по 40dps в радиусе 5.5.
class_name VovaOrbital
extends Ability


func _init() -> void:
	char_id = "vova"
	key = "X"
	map_target = true


func cast() -> void:
	var p := ground_point(40.0)
	var fx := get_node("/root/Fx")
	fx.call("cast", "generic", {
		"logic": "res://src/agents/effects/util_zone.gd",
		"shape": "circle", "x": p.x, "z": p.z, "r": float(Balance.ABILITY["ORBITAL_R"]),
		"delay": float(Balance.ABILITY["ORBITAL_DELAY"]), "dur": float(Balance.ABILITY["ORBITAL_DUR"]),
		"dps": float(Balance.ABILITY["ORBITAL_DPS"]), "weapon": "orbital",
		"team": player.team, "owner_path": String(player.get_path()),
	})
	fx.call("cast", "orbital_beam", { "x": p.x, "z": p.z })
