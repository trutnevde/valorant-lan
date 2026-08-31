# Денис C «Кровопир» — ест ТОЛЬКО у трупа врага (3.6м): +30 HP и реген 7/с 4с;
# после килла (окно 6с) — усиленно: +62 и 11/с («накормлен»).
class_name DenisBloodfeast
extends Ability


func _init() -> void:
	char_id = "denis"
	key = "C"


func can_cast() -> bool:
	# труп проверяет и клиент (быстрый отказ), и хост (авторитетно в fx-логике)
	var mt := Match.find(get_tree())
	return mt != null and mt.corpse_near(player.global_position, player.team, float(Balance.ABILITY["BLOODFEAST_R"]))


func cast() -> void:
	var fed := Time.get_ticks_msec() / 1000.0 - player.last_kill_t < float(Balance.ABILITY["BLOODFEAST_FED_WINDOW"])
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/bloodfeast_logic.gd",
		"owner_path": String(player.get_path()),
		"fed": fed,
	})
