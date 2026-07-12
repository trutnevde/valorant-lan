# LAN-игра: каждый пир детерминированно спавнит ВСЕХ игроков из Net.players
# (одни данные у всех → одинаковые имена нод → синхронизаторы сходятся) + ботов-заполнителей.
# Авторитет ноды игрока = его пир; боты — хост (id 1).
extends Node3D

const FILL_BOTS_PER_TEAM := 1  # добить команды ботами (для теста G4; лобби-настройка — позже)

var match_node: Match


func _ready() -> void:
	var map: Node3D = (load("res://scenes/maps/duel.tscn") as PackedScene).instantiate()
	add_child(map)
	# матч-контроллер (одинаковый путь у всех пиров — RPC состояния находит ноду)
	match_node = Match.new()
	match_node.name = "Match"
	add_child(match_node)

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
	var chars: Array = Balance.CHARACTERS.keys()
	var net := NetHub.node()
	var diff := String(net.get("difficulty")) if net else "medium"
	for tm in ["A", "B"]:
		for i in FILL_BOTS_PER_TEAM:
			var b: Bot = bot_scene.instantiate()
			b.name = "Bot_%s_%d" % [tm, i]
			add_child(b)
			b.set_multiplayer_authority(1)  # ботов ведёт хост
			b.team = tm
			b.preset = diff  # сложность из лобби
			b.char_id = chars[(i * 2 + (0 if tm == "A" else 1)) % chars.size()]  # разные агенты — разные скиллы
			b.global_position = _spawn_for(tm, idx, atk, def)

	# матч стартует хост после спавна; смена сторон — рассадка на каждый раунд
	if NetHub.is_host():
		match_node.phase_changed.connect(_on_phase)
		await get_tree().physics_frame
		match_node.start_match()


func _on_phase(phase: int, _deadline: float) -> void:
	if phase != Match.Phase.BUY:
		return
	# рассадка по сторонам: атака ↔ spawn_attack (стороны меняются каждый раунд)
	var table := {}
	var atk := get_tree().get_nodes_in_group("spawn_attack")
	var def := get_tree().get_nodes_in_group("spawn_defend")
	var idx := { "A": 0, "B": 0 }
	for c in get_tree().get_nodes_in_group("combatants"):
		var attacker := String(c.get("team")) == match_node.attack_team
		var list := atk if attacker else def
		var i := int(idx[String(c.get("team"))])
		idx[String(c.get("team"))] = i + 1
		if not list.is_empty():
			table[String((c as Node).name)] = (list[i % list.size()] as Node3D).global_position + Vector3(0, 0.2, 0)
	if NetHub.online():
		_apply_spawns.rpc(table)
	else:
		_apply_spawns(table)


@rpc("authority", "reliable", "call_local")
func _apply_spawns(table: Dictionary) -> void:
	for nm: String in table:
		var node := get_node_or_null(NodePath(nm))
		if node == null:
			continue
		# каждый пир двигает только СВОИ ноды (авторитет синхронизаторов)
		if (node as Node).get_multiplayer_authority() == multiplayer.get_unique_id() or not NetHub.online():
			(node as Node3D).global_position = table[nm]
			if node is CharacterBody3D:
				(node as CharacterBody3D).velocity = Vector3.ZERO


func _spawn_for(tm: String, idx: Dictionary, atk: Array, def: Array) -> Vector3:
	var list := atk if tm == "A" else def
	var i := int(idx[tm])
	idx[tm] = i + 1
	if list.is_empty():
		return Vector3(0, 0.2, 19 if tm == "A" else -19)
	return (list[i % list.size()] as Node3D).global_position + Vector3(0, 0.2, 0)


func _attach_kit(p: FpsPlayer) -> void:
	KitFactory.attach(p, p.char_id)  # дуэлянты готовы (G6a); остальные — G6b/G6c
