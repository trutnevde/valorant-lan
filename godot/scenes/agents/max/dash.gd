# Макс C «Рывок» — компонент способности (правило 4: одна способность = один компонент).
# Паритет web player.dash(): 6.5м в направлении движения (стоя — вперёд), 10 подшагов с коллизией.
# Заряды из Balance.CHARACTERS, автоперезарядка — сигнатурка (SIGNATURES.max: C, 30с).
class_name MaxDash
extends Node

var charges := 2
var _sig_ready_at := 0.0

@onready var player: FpsPlayer = get_parent().get_parent() as FpsPlayer

signal used(charges_left: int)


func _ready() -> void:
	charges = int(Balance.CHARACTERS["max"]["abilities"]["C"]["charges"])


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(_dt: float) -> void:
	# сигнатурка: автоперезарядка C по таймеру (паритет Эпохи 15)
	if _sig_ready_at > 0.0 and _now() >= _sig_ready_at:
		var mx := int(Balance.CHARACTERS["max"]["abilities"]["C"]["charges"])
		if charges < mx:
			charges += 1
			used.emit(charges)
		_sig_ready_at = (_now() + float(Balance.SIGNATURES["max"]["cd"])) if charges < mx else 0.0
	if Input.is_action_just_pressed("ability_c") and charges > 0:
		_dash()


func _dash() -> void:
	charges -= 1
	if charges <= 0 and _sig_ready_at == 0.0:
		_sig_ready_at = _now() + float(Balance.SIGNATURES["max"]["cd"])
	var dist := float(Balance.ABILITY["DASH_DIST"])
	# направление: клавиши движения; стоя — вперёд по взгляду (web dash)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir: Vector3
	if input.length_squared() > 0.0:
		dir = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, player.yaw).normalized()
	else:
		dir = Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	var steps := 10
	for i in steps:
		player.move_and_collide(dir * (dist / steps))
	player.velocity.x = dir.x * 4.0
	player.velocity.z = dir.z * 4.0
	used.emit(charges)
