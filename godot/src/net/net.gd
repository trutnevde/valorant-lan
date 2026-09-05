# Сеть (autoload Net): ENetMultiplayerPeer + высокоуровневый MultiplayerAPI.
# Авторитет — ПАРИТЕТ вебу (осознанный компромисс, менять нельзя):
# хост = сервер (HP/валидация урона; в G5 — экономика/раунды/шип), движение и
# попадания — клиентские (клиент рейкастит и репортит хиты, хост применяет).
extends Node

const DEFAULT_PORT := 27016  # веб занимает 27015

var players := {}   # peer_id -> {name, char, team}
var my_name := "Игрок"
var my_char := "max"
var difficulty := "medium"  # пресет ботов (лобби, только хост)
var map_id := "duel"        # выбор карты (лобби, только хост)

signal players_changed
signal game_started
signal connection_failed


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 9)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	players[1] = { "name": my_name, "char": my_char, "team": "A" }
	players_changed.emit()
	return OK


func join(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit())
	multiplayer.server_disconnected.connect(_reset)
	return OK


func is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == 1


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is ENetMultiplayerPeer


func _reset() -> void:
	players.clear()
	multiplayer.multiplayer_peer = null
	players_changed.emit()


func _on_connected() -> void:
	_register.rpc_id(1, my_name, my_char)


func _on_peer_connected(_id: int) -> void:
	pass  # ждём _register от клиента


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	_sync_players.rpc(players)
	players_changed.emit()


@rpc("any_peer", "reliable")
func _register(nm: String, ch: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	# команды поровну: новичок в меньшую
	var a := 0
	for p: Dictionary in players.values():
		if p["team"] == "A":
			a += 1
	players[id] = { "name": nm, "char": ch, "team": "A" if a <= players.size() - a else "B" }
	_sync_players.rpc(players)
	players_changed.emit()


@rpc("authority", "reliable", "call_local")
func _sync_players(data: Dictionary) -> void:
	players = data
	players_changed.emit()


@rpc("any_peer", "reliable")
func set_char(ch: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if players.has(id):
		players[id]["char"] = ch
		_sync_players.rpc(players)


@rpc("any_peer", "reliable")
func set_difficulty(d: String) -> void:
	if not is_host() or not Balance.BOT_PRESETS.has(d):
		return
	difficulty = d
	_sync_difficulty.rpc(d)


@rpc("authority", "reliable", "call_local")
func _sync_difficulty(d: String) -> void:
	difficulty = d
	players_changed.emit()


@rpc("any_peer", "reliable")
func set_map(mp: String) -> void:
	if not is_host() or not Balance.MAPS.has(mp):
		return
	map_id = mp
	_sync_map.rpc(mp)


@rpc("authority", "reliable", "call_local")
func _sync_map(mp: String) -> void:
	map_id = mp
	players_changed.emit()


@rpc("any_peer", "reliable")
func switch_team() -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if players.has(id):
		players[id]["team"] = "B" if players[id]["team"] == "A" else "A"
		_sync_players.rpc(players)


@rpc("authority", "reliable", "call_local")
func start_game() -> void:
	game_started.emit()
	get_tree().change_scene_to_file("res://scenes/maps/lan_game.tscn")


# ===== урон: клиент репортит попадание, ХОСТ применяет (авторитет-паритет вебу) =====
@rpc("any_peer", "reliable", "call_local")
func report_hit(target_path: NodePath, dmg: int, part: String, attacker_path := NodePath(), weapon := "") -> void:
	if not is_host():
		return
	var target := get_node_or_null(target_path)
	if target == null or not target.has_method("take_hit"):
		return
	if int(target.get("hp")) <= 0:
		return
	var attacker := get_node_or_null(attacker_path) if attacker_path != NodePath() else null
	target.call("take_hit", dmg, part, attacker, weapon)
	# HP разослать всем (у кого есть hp — синхронизирует состояние)
	_sync_hp.rpc(target_path, int(target.get("hp")))


# принудительная тяга своего игрока (кокон/воронка — хост командует, владелец исполняет)
@rpc("authority", "reliable", "call_local")
func force_pull_self(pos: Vector3, dur: float, speed: float) -> void:
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if p and p.has_method("force_pull"):
		p.call("force_pull", pos, dur, speed)


# оживление своего игрока (мини-рес Иры)
@rpc("authority", "reliable", "call_local")
func revive_self(pos: Vector3, hp: int) -> void:
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if p:
		p.set("hp", hp)
		p.set("dead", false)
		p.set("visible", true)
		(p as Node3D).global_position = pos
		if p is CollisionObject3D:
			(p as CollisionObject3D).set_collision_layer_value(1, true)
		if p.has_signal("hp_changed"):
			p.emit_signal("hp_changed", hp)


# слоу своего игрока (зоны/сигналка — хост командует)
@rpc("authority", "reliable", "call_local")
func slow_self(mul: float, dur: float) -> void:
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if p and p.has_method("apply_slow"):
		p.call("apply_slow", mul, dur)


# «Невесомость»: слоу+подброс своего игрока
@rpc("authority", "reliable", "call_local")
func levitate_self(dur: float) -> void:
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if p:
		p.set("levit_until", Time.get_ticks_msec() / 1000.0 + dur)
		if p is CharacterBody3D and (p as CharacterBody3D).is_on_floor():
			(p as CharacterBody3D).velocity.y = 2.2


# телепорт своего игрока (движение клиент-авторитарно — двигает владелец)
@rpc("authority", "reliable", "call_local")
func teleport_self(pos: Vector3) -> void:
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if p:
		(p as Node3D).global_position = pos
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO


# закупка: клиент просит — хост валидирует деньги/фазу, клиент получает подтверждение
@rpc("any_peer", "reliable")
func buy(weapon_id: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % id)
	var mt := Match.find(get_tree())
	if p == null or mt == null:
		return
	if mt.try_buy(p, weapon_id):
		_buy_ok.rpc_id(id, weapon_id, int(p.get("credits")))


@rpc("any_peer", "reliable")
func buy_armor(kind: String) -> void:
	if not is_host():
		return
	var mt := Match.find(get_tree())
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % multiplayer.get_remote_sender_id())
	if mt and p:
		mt.try_buy_armor(p, kind)


@rpc("authority", "reliable")
func _buy_ok(weapon_id: String, credits: int) -> void:
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if p:
		p.set("credits", credits)
		p.call("give_weapon", weapon_id)


# клиент держит 4/F — хост применяет плант/дефуз со своим dt (авторитет-паритет)
@rpc("any_peer", "unreliable_ordered")
func spike_input(plant_hold: bool, at_site: bool, defuse_hold: bool) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % id)
	var mt := Match.find(get_tree())
	if p == null or mt == null:
		return
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	mt.try_plant(p, at_site, plant_hold, dt)
	mt.try_defuse(p, defuse_hold, dt)


@rpc("authority", "reliable", "call_local")
func _sync_hp(target_path: NodePath, hp: int) -> void:
	if is_host():
		return  # хост уже применил
	var target := get_node_or_null(target_path)
	if target and "hp" in target:
		target.set("hp", hp)
		if target.has_signal("hp_changed"):
			target.emit_signal("hp_changed", hp)


# ===== БОЕВОЕ СОСТОЯНИЕ (G11) =====
# Раньше по сети ездил ТОЛЬКО hp. Из-за этого после смерти клиент оставался «живым» у себя:
# ходил и стрелял, тогда как у хоста лежал трупом — и рассинхрон был необратимым до конца
# матча. Кредиты, ульта и счёт киллов не доезжали вовсе, HUD показывал стухшие числа.
# Теперь хост рассылает состояние целиком: жизнь, смерть, видимость, коллизия, экономика.
@rpc("authority", "reliable")
func _sync_combat(path: NodePath, hp: int, is_dead: bool, credits: int, ult: int, kills: int, deaths: int) -> void:
	var n := get_node_or_null(path)
	if n == null:
		return
	n.set("hp", hp)
	if "credits" in n:
		n.set("credits", credits)
	if "ult" in n:
		n.set("ult", ult)
	if "kills" in n:
		n.set("kills", kills)
	if "deaths" in n:
		n.set("deaths", deaths)
	if "dead" in n:
		n.set("dead", is_dead)
	if n is Node3D:
		(n as Node3D).visible = not is_dead
	if n is CollisionObject3D:
		(n as CollisionObject3D).set_collision_layer_value(1, not is_dead)
	if n.has_signal("hp_changed"):
		n.emit_signal("hp_changed", hp)


# хост: разослать состояние одного бойца
func push_combat(n: Node) -> void:
	if not is_online() or not is_host() or n == null or not is_instance_valid(n):
		return
	_sync_combat.rpc(n.get_path(), int(n.get("hp")),
		bool(n.get("dead")) if "dead" in n else int(n.get("hp")) <= 0,
		int(n.get("credits")) if "credits" in n else 0,
		int(n.get("ult")) if "ult" in n else 0,
		int(n.get("kills")) if "kills" in n else 0,
		int(n.get("deaths")) if "deaths" in n else 0)


# хост: разослать состояние всех (старт раунда, конец раунда, подключение)
func push_all_combat() -> void:
	if not is_online() or not is_host():
		return
	for c in get_tree().get_nodes_in_group("combatants"):
		push_combat(c)


# Раунд-ресет на клиентах: заряды способностей, лоадаут и снятие контроля — состояние
# ЛОКАЛЬНОЕ, по сети его не передать, поэтому просто просим каждый пир пересобрать своё.
@rpc("authority", "reliable", "call_local")
func _sync_round_reset() -> void:
	for c in get_tree().get_nodes_in_group("combatants"):
		if c.has_method("round_reset"):
			c.call("round_reset")


func broadcast_round_reset() -> void:
	if is_online() and is_host():
		_sync_round_reset.rpc()
