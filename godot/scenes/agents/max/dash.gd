# Макс C «Рывок» — компонент способности (правило 4: одна способность = один компонент).
# Паритет web player.dash(): 6.5м в направлении движения (стоя — вперёд), 10 подшагов с коллизией.
# Заряды и автоперезарядка-сигнатурка (SIGNATURES.max: C, 30с) — из базового Ability.
class_name MaxDash
extends Ability


func _init() -> void:
	char_id = "max"
	key = "C"


func _ready() -> void:
	super()
	# твист Эпохи 15: дэш обновляется за убийство
	var mt := Match.find(get_tree())
	if mt:
		mt.killer_scored.connect(func(killer: Node) -> void:
			if killer == player:
				var mx := int(Balance.CHARACTERS["max"]["abilities"]["C"]["charges"])
				charges = mini(mx, charges + 1)
				used.emit(charges))


func cast() -> void:
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
