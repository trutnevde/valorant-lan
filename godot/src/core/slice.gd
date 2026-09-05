# Вертикальный срез G3: Дуэль, ты — Макс (пассивка скорости, двойной прыжок, Рывок C,
# Взлёт Q) против ботов (medium). HP/урон/звук шагов работают. Респавны бесконечные.
extends Node3D

const BOTS_ENEMY := 2


func _ready() -> void:
	var map: Node3D = (load("res://scenes/maps/duel.tscn") as PackedScene).instantiate()
	add_child(map)

	# игрок-Макс на спавне атаки
	var player: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child(player)
	var atk := get_tree().get_nodes_in_group("spawn_attack")
	player.global_position = (atk[0] as Node3D).global_position + Vector3(0, 0.2, 0) if atk.size() > 0 else Vector3(0, 0.2, 19)
	# развернуть в центр карты — иначе спавн у периметра смотрит в глухую стену
	var tc := Vector3(-player.global_position.x, 0.0, -player.global_position.z)
	if tc.length() > 0.5:
		player.yaw = atan2(-tc.x, -tc.z)
	player.char_id = "max"
	player.team = "A"

	# кит агента компонентами (правило 4); тренировка уважает выбор из лобби
	var net := NetHub.node()
	if net:
		player.char_id = String(net.get("my_char"))
	KitFactory.attach(player, player.char_id)

	# боты-враги на спавне защиты
	var bot_scene: PackedScene = load("res://scenes/bots/bot.tscn")
	var def := get_tree().get_nodes_in_group("spawn_defend")
	for i in BOTS_ENEMY:
		var b := bot_scene.instantiate() as Bot
		b.team = "B"
		b.preset = "medium"
		add_child(b)
		var sp := (def[i % def.size()] as Node3D).global_position if def.size() > 0 else Vector3(0, 0, -19)
		b.global_position = sp + Vector3(0, 0.2, 0)
