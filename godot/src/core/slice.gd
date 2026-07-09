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
	player.char_id = "max"
	player.team = "A"

	# кит Макса — компоненты способностей (правило 4)
	var kit := Node.new()
	kit.name = "Kit"
	player.add_child(kit)
	var dash: Node = (load("res://scenes/agents/max/dash.gd") as GDScript).new()
	dash.name = "Dash"
	kit.add_child(dash)
	var launch: Node = (load("res://scenes/agents/max/launch.gd") as GDScript).new()
	launch.name = "Launch"
	kit.add_child(launch)

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
