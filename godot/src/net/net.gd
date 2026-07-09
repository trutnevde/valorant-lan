# Сеть (autoload Net): ENetMultiplayerPeer + высокоуровневый MultiplayerAPI.
# Авторитет — ПАРИТЕТ вебу (осознанный компромисс, менять нельзя):
# хост = сервер (HP/валидация урона; в G5 — экономика/раунды/шип), движение и
# попадания — клиентские (клиент рейкастит и репортит хиты, хост применяет).
extends Node

const DEFAULT_PORT := 27016  # веб занимает 27015

var players := {}   # peer_id -> {name, char, team}
var my_name := "Игрок"
var my_char := "max"

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
