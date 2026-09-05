# Лобби: хост/подключение по IP (Radmin 26.x.x.x), выбор агента, старт (хост).
extends Control

@onready var name_edit: LineEdit = %NameEdit
@onready var ip_edit: LineEdit = %IpEdit
@onready var menu_box: VBoxContainer = %MenuBox
@onready var lobby_box: VBoxContainer = %LobbyBox
@onready var player_list: ItemList = %PlayerList
@onready var char_pick: OptionButton = %CharPick
@onready var status: Label = %Status
@onready var start_btn: Button = %StartBtn
@onready var net: Node = NetHub.node()

var _char_ids: Array[String] = []
var _map_ids: Array[String] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# главные действия — акцентной бирюзой, второстепенные — стеклом
	%HostBtn.theme_type_variation = &"PrimaryButton"
	%TrainBtn.theme_type_variation = &"PrimaryButton"
	%StartBtn.theme_type_variation = &"PrimaryButton"
	for id: String in Balance.CHARACTERS:
		_char_ids.append(id)
		char_pick.add_item("%s — %s" % [Balance.CHARACTERS[id]["name"], Balance.CHARACTERS[id]["title"]])
	char_pick.select(_char_ids.find("max"))
	net.connect("players_changed", _refresh)
	net.connect("connection_failed", func() -> void: status.text = "Не удалось подключиться")
	%HostBtn.pressed.connect(_on_host)
	%JoinBtn.pressed.connect(_on_join)
	# «Тренировка» — НАСТОЯЩИЙ офлайн-матч против ботов (раунды, закупка, шип), а не тир:
	# кнопка обещает «офлайн против ботов», и раньше вела в slice.tscn, где ни раундов,
	# ни шипа не было в принципе — поставить спайк было невозможно.
	%TrainBtn.pressed.connect(func() -> void:
		_apply_name()
		get_tree().change_scene_to_file("res://scenes/maps/lan_game.tscn"))
	%RangeBtn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/maps/slice.tscn"))
	%TeamBtn.pressed.connect(func() -> void: net.rpc_id(1, "switch_team"))
	var dp := %DiffPick as OptionButton
	for d in ["easy", "medium", "hard"]:
		dp.add_item({ "easy": "БОТЫ: ЛЁГКИЕ", "medium": "БОТЫ: СРЕДНИЕ", "hard": "БОТЫ: ЖЁСТКИЕ" }[d])
	dp.select(1)
	dp.item_selected.connect(func(i: int) -> void:
		net.rpc_id(1, "set_difficulty", ["easy", "medium", "hard"][i]))
	var mp := %MapPick as OptionButton
	_map_ids.assign(Balance.MAPS.keys())
	for mid: String in _map_ids:
		mp.add_item("КАРТА: %s" % Balance.MAPS[mid]["name"])
	mp.select(_map_ids.find("duel"))
	mp.item_selected.connect(func(i: int) -> void:
		net.rpc_id(1, "set_map", _map_ids[i]))
	start_btn.pressed.connect(func() -> void: net.rpc("start_game"))
	char_pick.item_selected.connect(func(i: int) -> void:
		net.set("my_char", _char_ids[i])
		if NetHub.online():
			net.rpc_id(1, "set_char", _char_ids[i]))


func _apply_name() -> void:
	if name_edit.text.strip_edges() != "":
		net.set("my_name", name_edit.text.strip_edges())


func _on_host() -> void:
	_apply_name()
	if net.call("host") == OK:
		_to_lobby("Хост поднят. Порт %d — скажи друзьям свой IP (Radmin 26.x.x.x)" % int(net.get("DEFAULT_PORT")))
	else:
		status.text = "Порт занят?"


func _on_join() -> void:
	_apply_name()
	if net.call("join", ip_edit.text.strip_edges()) == OK:
		_to_lobby("Подключаюсь к %s…" % ip_edit.text)
	else:
		status.text = "Кривой адрес"


func _to_lobby(msg: String) -> void:
	status.text = msg
	menu_box.visible = false
	lobby_box.visible = true
	start_btn.visible = NetHub.is_host()
	_refresh()


func _refresh() -> void:
	player_list.clear()
	var players: Dictionary = net.get("players")
	for id: int in players:
		var p: Dictionary = players[id]
		var ch: Dictionary = Balance.CHARACTERS.get(p["char"], {})
		player_list.add_item("[%s] %s — %s%s" % [p["team"], p["name"], ch.get("name", p["char"]), "  (хост)" if id == 1 else ""])
