# Макс Q «Взлёт» — компонент способности: подброс вверх (только с земли).
# Паритет web player.launch(): vel.y = LAUNCH_V (8.5).
class_name MaxLaunch
extends Node

var charges := 2

@onready var player: FpsPlayer = get_parent().get_parent() as FpsPlayer

signal used(charges_left: int)


func _ready() -> void:
	charges = int(Balance.CHARACTERS["max"]["abilities"]["Q"]["charges"])


func _physics_process(_dt: float) -> void:
	if Input.is_action_just_pressed("ability_q") and charges > 0 and player.is_on_floor():
		charges -= 1
		player.velocity.y = float(Balance.ABILITY["LAUNCH_V"])
		used.emit(charges)
