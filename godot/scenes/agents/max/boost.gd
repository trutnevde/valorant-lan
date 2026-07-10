# Макс E «Порыв» — +40% скорости на 4 с (BOOST_MUL/BOOST_TIME из balance.gd).
class_name MaxBoost
extends Ability


func _init() -> void:
	char_id = "max"
	key = "E"


func cast() -> void:
	player.boost_until = Time.get_ticks_msec() / 1000.0 + float(Balance.ABILITY["BOOST_TIME"])
