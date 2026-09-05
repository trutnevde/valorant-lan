# LAN-игра: каждый пир детерминированно спавнит ВСЕХ игроков из Net.players
# (одни данные у всех → одинаковые имена нод → синхронизаторы сходятся) + ботов-заполнителей.
# Авторитет ноды игрока = его пир; боты — хост (id 1).
extends Node3D

const FILL_BOTS_PER_TEAM := 1        # добить команды ботами в сетевой игре
const FILL_BOTS_OFFLINE := 3         # офлайн («тренировка») — полноценный матч 3 на 3

var match_node: Match


func _ready() -> void:
	var net0 := NetHub.node()
	var mid := String(net0.get("map_id")) if net0 else "duel"
	if not ResourceLoader.exists("res://scenes/maps/%s.tscn" % mid):
		mid = "duel"
	var map: Node3D = (load("res://scenes/maps/%s.tscn" % mid) as PackedScene).instantiate()
	add_child(map)
	# реверб-зоны на сайтах (гулкость закрытых точек) — движковый Area3D reverb
	var meta = JSON.parse_string(String(map.get_meta("map_meta", "{}")))
	if meta is Dictionary:
		get_node("/root/Ears").call("setup_reverb_zones", map, meta)
	# матч-контроллер (одинаковый путь у всех пиров — RPC состояния находит ноду)
	match_node = Match.new()
	match_node.name = "Match"
	add_child(match_node)
	# звук и визуал шипа (правило 7: информация — звуком, а не надписью)
	var spike_fx: Node3D = (load("res://src/agents/spike_fx.gd") as GDScript).new()
	spike_fx.name = "SpikeFx"
	add_child(spike_fx)

	var atk := get_tree().get_nodes_in_group("spawn_attack")
	var def := get_tree().get_nodes_in_group("spawn_defend")
	var idx := { "A": 0, "B": 0 }

	var player_scene: PackedScene = load("res://scenes/agents/player.tscn")
	var players: Dictionary = NetHub.node().get("players")
	# ОФЛАЙН (кнопка «ТРЕНИРОВКА»): реестра игроков нет, потому что никто не подключался.
	# Раньше из-за этого офлайн-режим вообще не спавнил игрока, и «тренировкой» служил тир
	# без раундов и шипа — то есть шип нельзя было поставить в принципе.
	if players.is_empty():
		var n0 := NetHub.node()
		players = { 1: {
			"name": String(n0.get("my_name")) if n0 else "Игрок",
			"char": String(n0.get("my_char")) if n0 else "max",
			"team": "A",
		} }
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
		_face_center(p, p.global_position)
		if id == multiplayer.get_unique_id():
			_attach_kit(p)

	var bot_scene: PackedScene = load("res://scenes/bots/bot.tscn")
	var chars: Array = Balance.CHARACTERS.keys()
	var net := NetHub.node()
	var diff := String(net.get("difficulty")) if net else "medium"
	var fill := FILL_BOTS_PER_TEAM if NetHub.online() else FILL_BOTS_OFFLINE
	for tm in ["A", "B"]:
		for i in fill:
			if not NetHub.online() and tm == "A" and i == fill - 1:
				continue  # место в команде A занял живой игрок
			var b: Bot = bot_scene.instantiate()
			b.name = "Bot_%s_%d" % [tm, i]
			add_child(b)
			b.set_multiplayer_authority(1)  # ботов ведёт хост
			b.team = tm
			b.preset = diff  # сложность из лобби
			b.char_id = chars[(i * 2 + (0 if tm == "A" else 1)) % chars.size()]  # разные агенты — разные скиллы
			b.global_position = _spawn_for(tm, idx, atk, def)
			_face_center(b, b.global_position)

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
			var pos: Vector3 = table[nm]
			(node as Node3D).global_position = pos
			if node is CharacterBody3D:
				(node as CharacterBody3D).velocity = Vector3.ZERO
			_face_center(node, pos)


# Разворот на спавне В ЦЕНТР КАРТЫ. Без него боец появляется в той ориентации, в какой был
# создан, а спавны стоят у периметра — игрок утыкался носом в глухую бетонную стену.
# Мышь при этом работала, но картинка не менялась, и выглядело это как «камера не крутится».
func _face_center(node: Node, pos: Vector3) -> void:
	var to_center := Vector3(-pos.x, 0.0, -pos.z)
	if to_center.length() < 0.5:
		return
	var yaw := atan2(-to_center.x, -to_center.z)
	if node is FpsPlayer:
		(node as FpsPlayer).yaw = yaw
		(node as FpsPlayer).pitch = 0.0
	(node as Node3D).rotation.y = yaw


func _spawn_for(tm: String, idx: Dictionary, atk: Array, def: Array) -> Vector3:
	var list := atk if tm == "A" else def
	var i := int(idx[tm])
	idx[tm] = i + 1
	if list.is_empty():
		return Vector3(0, 0.2, 19 if tm == "A" else -19)
	return (list[i % list.size()] as Node3D).global_position + Vector3(0, 0.2, 0)


func _attach_kit(p: FpsPlayer) -> void:
	KitFactory.attach(p, p.char_id)  # дуэлянты готовы (G6a); остальные — G6b/G6c
