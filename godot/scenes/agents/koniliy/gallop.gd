# Конилий E «Галоп» — призрачный конь: +50% скорости на 3.5с.
class_name KoniliyGallop
extends Ability


func _init() -> void:
	char_id = "koniliy"
	key = "E"


func cast() -> void:
	player.gallop_until = Time.get_ticks_msec() / 1000.0 + float(Balance.ABILITY["GALLOP_TIME"])
