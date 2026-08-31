# Макс Q «Взлёт» — компонент способности: подброс вверх (только с земли).
# Паритет web player.launch(): vel.y = LAUNCH_V (8.5).
class_name MaxLaunch
extends Ability


func _init() -> void:
	char_id = "max"
	key = "Q"


func can_cast() -> bool:
	return player.is_on_floor()   # в воздухе не взлетаем (паритет)


func cast() -> void:
	player.velocity.y = float(Balance.ABILITY["LAUNCH_V"])
