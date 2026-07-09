# LAN-игра: каждый пир детерминированно спавнит ВСЕХ игроков из Net.players
# (одни данные у всех → одинаковые имена нод → синхронизаторы сходятся) + ботов-заполнителей.
# Авторитет ноды игрока = его пир; боты — хост (id 1).
extends Node3D

const FILL_BOTS_PER_TEAM := 1  # добить команды ботами (для теста G4; лобби-настройка — позже)


func _ready() -> void:
	var map: Node3D = (load("res://scenes/maps/duel.tscn") as PackedScene).instantiate()
	add_child(map)

	var atk := get_tree().get_nodes_in_group("spawn_attack")
	var def := get_tree().get_nodes_in_group("spawn_defend")
	var idx := { "A": 0, "B": 0 }

	var player_scene: PackedScene = load("res://scenes/agents/player.tscn")
	var players: Dictionary = NetHub.node().get("players")
	var ids: Array = players.keys()
	ids.sort()
	for id: int in ids:
		var info: Dictionary = players[id]
		var p: FpsPlayer = player_scene.instantiate()
		p.name = "Player_%d" % id
		add_child(p)
		p.set_multiplayer_authority(id)
		p.char_id = String(info["char"])
		p.team = String(info["team"])
		p.global_position = _spawn_for(String(info["team"]), idx, atk, def)
		if id == multiplayer.get_unique_id():
			_attach_kit(p)

	var bot_scene: PackedScene = load("res://scenes/bots/bot.tscn")
	for tm in ["A", "B"]:
		for i in FILL_BOTS_PER_TEAM:
			var b: Bot = bot_scene.instantiate()
			b.name = "Bot_%s_%d" % [tm, i]
			add_child(b)
			b.set_multiplayer_authority(1)  # ботов ведёт хост
			b.team = tm
			b.preset = "medium"
			b.global_position = _spawn_for(tm, idx, atk, def)


func _spawn_for(tm: String, idx: Dictionary, atk: Array, def: Array) -> Vector3:
	var list := atk if tm == "A" else def
	var i := int(idx[tm])
	idx[tm] = i + 1
	if list.is_empty():
		return Vector3(0, 0.2, 19 if tm == "A" else -19)
	return (list[i % list.size()] as Node3D).global_position + Vector3(0, 0.2, 0)


func _attach_kit(p: FpsPlayer) -> void:
	# кит агента компонентами; пока реализован Макс (остальные — фаза G6)
	if p.char_id != "max":
		return
	var kit := Node.new()
	kit.name = "Kit"
	p.add_child(kit)
	var dash: Node = (load("res://scenes/agents/max/dash.gd") as GDScript).new()
	dash.name = "Dash"
	kit.add_child(dash)
	var launch: Node = (load("res://scenes/agents/max/launch.gd") as GDScript).new()
	launch.name = "Launch"
	kit.add_child(launch)
