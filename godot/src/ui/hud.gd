# Минимальный HUD G1-G3: прицел, патроны, HP, заряды кита, хитмаркер, вспышка урона.
# Полный HUD — фаза G9.
extends CanvasLayer

@onready var ammo_label: Label = $Ammo
@onready var hitmark: Label = $Hitmark
@onready var hp_label: Label = get_node_or_null("Hp")
@onready var kit_label: Label = get_node_or_null("Kit")
@onready var dmg_flash: ColorRect = get_node_or_null("DmgFlash")
@onready var weapon_rig: WeaponRig = get_parent().get_node("WeaponRig")
@onready var player: FpsPlayer = get_parent() as FpsPlayer

var _last_hp := 100


var _minimap: Control
var _ability_bar: HBoxContainer


func _ready() -> void:
	weapon_rig.hit_target.connect(_on_hit)
	if player:
		player.hp_changed.connect(_on_hp)
		player.blinded.connect(_on_blind)
		_build_minimap()
		_build_ability_bar()
		_build_tactical_map()
		# перф-фолбэк (клавиша P): показываем уровень, иначе игрок не поймёт, что нажал
		var q := get_node_or_null("/root/Quality")
		if q:
			q.connect("changed", func(_l: int) -> void: _announce("ГРАФИКА: " + String(q.call("level_name"))))


func _build_minimap() -> void:
	_minimap = (load("res://src/ui/minimap.gd") as GDScript).new()
	_minimap.custom_minimum_size = Vector2(210, 210)
	_minimap.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_minimap.offset_left = 14.0
	_minimap.offset_top = 14.0
	_minimap.size = Vector2(210, 210)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE  # иначе съедает движение мыши
	add_child(_minimap)
	_minimap.call("setup", player)


# ===== тактическая карта: целеуказание кликом (дымы/орбиталка Вовы, клоны Фафика) =====
var _tac: Control
var _tac_hint: Label
var _tac_ability: Node = null


func _build_tactical_map() -> void:
	_tac = (load("res://src/ui/minimap.gd") as GDScript).new()
	_tac.set_anchors_preset(Control.PRESET_CENTER)
	_tac.size = Vector2(640, 640)
	_tac.position = Vector2(-320, -320)
	_tac.visible = false
	_tac.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_tac)
	_tac.call("setup", player)
	_tac.gui_input.connect(_on_tac_input)
	_tac_hint = Label.new()
	_tac_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tac_hint.offset_top = 40.0
	_tac_hint.offset_left = -300.0
	_tac_hint.offset_right = 300.0
	_tac_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tac_hint.visible = false
	_tac_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tac_hint)


func request_map_target(ab: Node) -> void:
	_tac_ability = ab
	_tac.visible = true
	_tac_hint.text = "ЛКМ — отметить точку   ·   ПКМ / ESC — отмена"
	_tac_hint.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_tac() -> void:
	_tac_ability = null
	_tac.visible = false
	_tac_hint.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_tac_input(ev: InputEvent) -> void:
	if _tac_ability == null or not (ev is InputEventMouseButton) or not ev.pressed:
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_close_tac()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var world: Vector3 = _tac.call("m2w", mb.position)
	var ab := _tac_ability
	_close_tac()
	if is_instance_valid(ab):
		ab.call("map_target_confirmed", world)


func _build_ability_bar() -> void:
	_ability_bar = HBoxContainer.new()
	_ability_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ability_bar.offset_top = -118.0
	_ability_bar.offset_bottom = -84.0
	_ability_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_bar.add_theme_constant_override("separation", 10)
	_ability_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ability_bar)


func _on_blind(dur: float) -> void:
	var bf := get_node_or_null("BlindFlash") as ColorRect
	if bf:
		bf.modulate.a = 1.0
		var tw := bf.create_tween()
		tw.tween_interval(dur * 0.55)
		tw.tween_property(bf, "modulate:a", 0.0, dur * 0.45)


func _process(_dt: float) -> void:
	var id := weapon_rig.current_id
	var a: Dictionary = weapon_rig.ammo.get(id, {})
	var nm := String(Balance.WEAPONS[id]["name"])
	if a.is_empty():
		ammo_label.text = nm
	else:
		ammo_label.text = "%s  %d / %d" % [nm, int(a.get("mag", 0)), int(a.get("reserve", 0))]
	if weapon_rig.reloading_until > Time.get_ticks_msec() / 1000.0:
		ammo_label.text += "  [ПЕРЕЗАРЯДКА]"
	if hp_label and player:
		hp_label.text = "HP %d" % maxi(0, player.hp)
	if kit_label:
		kit_label.visible = false  # заменено панелью способностей
	_refresh_abilities()
	if _tac_ability != null and Input.is_action_just_pressed("ui_cancel"):
		_close_tac()
	_process_match(_dt)


# генеричная панель способностей: C/Q/E/X с зарядами/кулдауном/прогрессом ульты (любой агент)
var _chips := {}  # key -> {panel, label}


func _refresh_abilities() -> void:
	if _ability_bar == null:
		return
	var kit := player.get_node_or_null("Kit")
	if kit == null:
		return
	var cost := int(Balance.CHARACTERS[player.char_id]["ultCost"])
	for ab in kit.get_children():
		var key := String(ab.get("key"))
		if not _chips.has(key):
			var panel := PanelContainer.new()
			var lbl := Label.new()
			lbl.add_theme_font_size_override("font_size", 15)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			panel.custom_minimum_size = Vector2(150, 30)
			panel.add_child(lbl)
			_ability_bar.add_child(panel)
			_chips[key] = { "panel": panel, "label": lbl }
		var nm := String(Balance.CHARACTERS[player.char_id]["abilities"][key]["name"])
		var lbl2: Label = _chips[key]["label"]
		var ready := true
		if key == "X":
			ready = player.ult >= cost
			lbl2.text = "[X] %s  %d/%d" % [nm, mini(player.ult, cost), cost]
		else:
			var ch := int(ab.get("charges"))
			ready = ch > 0
			lbl2.text = "[%s] %s  ×%d" % [key, nm, ch]
		lbl2.modulate = Color(1, 1, 1) if ready else Color(0.5, 0.52, 0.55)


func _on_hp(hp: int) -> void:
	if dmg_flash and hp < _last_hp:
		dmg_flash.modulate.a = 0.45
		var tw := dmg_flash.create_tween()
		tw.tween_property(dmg_flash, "modulate:a", 0.0, 0.35)
	_last_hp = hp


# ===== матч-панель (G5): раунд/счёт/таймер/деньги/шип + киллфид + buy-меню =====
var _match_label: Label
var _feed: VBoxContainer
var _buy_panel: PanelContainer
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _bar_label: Label
var _board: PanelContainer
var _board_grid: GridContainer
var _snd := {}
var _mt: Match


func _enter_tree() -> void:
	call_deferred("_setup_match_ui")


func _setup_match_ui() -> void:
	await get_tree().process_frame
	_mt = Match.find(get_tree())
	if _mt == null:
		return  # тренировка без матча
	_match_label = Label.new()
	_match_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_match_label.offset_top = 8.0
	_match_label.offset_left = -260.0
	_match_label.offset_right = 260.0
	_match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_match_label)
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -420.0
	_feed.offset_top = 8.0
	_feed.offset_right = -12.0
	add_child(_feed)
	# полоса планта/дефуза: без неё о работе у шипа сообщал только текст (правило 7)
	_bar_bg = ColorRect.new()
	_bar_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar_bg.offset_left = -170.0
	_bar_bg.offset_right = 170.0
	_bar_bg.offset_top = -190.0
	_bar_bg.offset_bottom = -172.0
	_bar_bg.color = Color(0, 0, 0, 0.55)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.visible = false
	add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar_fill)
	_bar_label = Label.new()
	_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_bg.add_child(_bar_label)
	_mt.killfeed.connect(_on_kill)
	_mt.round_ended.connect(func(w: String, r: String) -> void: _announce("Раунд: победа %s (%s)" % [w, r]))
	_mt.match_ended.connect(func(w: String) -> void: _announce("МАТЧ ОКОНЧЕН — ПОБЕДА %s" % w))
	_build_scoreboard()
	_mt.round_ended.connect(func(w: String, _r: String) -> void:
		_snd_play("confirm" if w == player.team else "hurt", 0.0, 1.0 if w == player.team else 0.8))
	_mt.match_ended.connect(func(_w: String) -> void: _board.visible = true)
	_mt.phase_changed.connect(func(ph: int, _d: float) -> void:
		if ph == Match.Phase.LIVE:
			_snd_play("ting", -4.0, 0.7)   # раунд пошёл — сигнал на слух, а не надписью
		elif ph == Match.Phase.BUY:
			_board.visible = false)
	_build_buy_menu()


# Таб-скорборд: счёт, киллы/смерти, деньги. Показывается по удержанию Tab и сам всплывает
# на конце матча — раньше итог матча вообще негде было посмотреть.
func _build_scoreboard() -> void:
	_board = PanelContainer.new()
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.offset_left = -330.0
	_board.offset_right = 330.0
	_board.offset_top = -190.0
	_board.offset_bottom = 190.0
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.visible = false
	_board_grid = GridContainer.new()
	_board_grid.columns = 5
	_board_grid.add_theme_constant_override("h_separation", 18)
	_board.add_child(_board_grid)
	add_child(_board)


func _refresh_scoreboard() -> void:
	if _board == null or not _board.visible or _mt == null:
		return
	for c in _board_grid.get_children():
		c.queue_free()
	var head := ["БОЕЦ", "АГЕНТ", "К", "С", "$"]
	for h: String in head:
		var hl := Label.new()
		hl.text = h
		hl.modulate = Color(0.7, 0.75, 0.8)
		_board_grid.add_child(hl)
	var rows: Array = _mt._combatants().duplicate()
	rows.sort_custom(func(a: Node, b: Node) -> bool:
		if String(a.get("team")) != String(b.get("team")):
			return String(a.get("team")) < String(b.get("team"))
		return int(a.get("kills")) > int(b.get("kills")))
	for c in rows:
		var ch: Dictionary = Balance.CHARACTERS.get(String(c.get("char_id")), {})
		var tint := Color(0.45, 0.75, 1.0) if String(c.get("team")) == player.team else Color(1.0, 0.55, 0.45)
		var cells := [String((c as Node).name), String(ch.get("name", "?")),
			str(int(c.get("kills"))), str(int(c.get("deaths"))), "$" + str(int(c.get("credits")))]
		for cell: String in cells:
			var l := Label.new()
			l.text = cell
			l.modulate = tint
			_board_grid.add_child(l)


func _snd_play(nm: String, vol := 0.0, pitch := 1.0) -> void:
	if not _snd.has(nm):
		_snd[nm] = load("res://assets/audio/%s.ogg" % nm)
	var pl := AudioStreamPlayer.new()
	pl.stream = _snd[nm]
	pl.volume_db = vol
	pl.pitch_scale = pitch
	pl.bus = "UI"
	add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()


func _announce(txt: String) -> void:
	_on_kill(txt, "", "", false)


func _on_kill(a: String, b: String, w: String, head: bool) -> void:
	if _feed == null:
		return  # тренировка без матча: ленты нет, но сообщать всё равно могут (напр. смена графики)
	var l := Label.new()
	l.text = ("%s ✕ %s [%s]%s" % [a, b, w, " ХЕД" if head else ""]) if b != "" else a
	_feed.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(l.queue_free)


func _build_buy_menu() -> void:
	_buy_panel = PanelContainer.new()
	_buy_panel.set_anchors_preset(Control.PRESET_CENTER)
	_buy_panel.visible = false
	var grid := GridContainer.new()
	grid.columns = 3
	_buy_panel.add_child(grid)
	var items: Array = []
	for id: String in Balance.WEAPONS:
		if id == "knife" or int(Balance.WEAPONS[id]["price"]) == 0:
			continue
		items.append(id)
	items.sort_custom(func(x: String, y: String) -> bool: return int(Balance.WEAPONS[x]["price"]) < int(Balance.WEAPONS[y]["price"]))
	for id: String in items:
		var btn := Button.new()
		btn.text = "%s — %d" % [Balance.WEAPONS[id]["name"], int(Balance.WEAPONS[id]["price"])]
		btn.pressed.connect(_buy.bind(id))
		grid.add_child(btn)
	add_child(_buy_panel)


func _buy(id: String) -> void:
	if NetHub.online() and not multiplayer.is_server():
		NetHub.node().rpc_id(1, "buy", id)
	else:
		_mt.try_buy(player, id)


func _phase_name(p: int) -> String:
	match p:
		Match.Phase.BUY: return "ЗАКУПКА (B — магазин)"
		Match.Phase.LIVE: return "ИГРА"
		Match.Phase.PLANTED: return "ШИП УСТАНОВЛЕН"
		Match.Phase.ROUND_END: return "КОНЕЦ РАУНДА"
		Match.Phase.MATCH_END: return "КОНЕЦ МАТЧА"
	return ""


func _process_match(_dt: float) -> void:
	if _mt == null or _match_label == null:
		return
	var left := maxf(0.0, _mt.deadline - _mt.now())
	_match_label.text = "Раунд %d · A %d : %d B · %s · ТЫ: %s · %d:%02d · $%d" % [
		_mt.round_no, int(_mt.score["A"]), int(_mt.score["B"]), _phase_name(_mt.phase),
		_side_name(), int(left) / 60, int(left) % 60, player.credits]
	if _mt.spike_carrier == player and _mt.phase == Match.Phase.LIVE:
		_match_label.text += "  ·  ТЫ НЕСЁШЬ ШИП (4 — плант в сайте)"
	_update_bar()
	if _board:
		if _mt.phase != Match.Phase.MATCH_END:
			_board.visible = Input.is_action_pressed("scoreboard")
		_refresh_scoreboard()
	if Input.is_action_just_pressed("buy") and _mt.phase == Match.Phase.BUY:
		_buy_panel.visible = not _buy_panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _buy_panel.visible else Input.MOUSE_MODE_CAPTURED
	if _mt.phase != Match.Phase.BUY and _buy_panel.visible:
		_buy_panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Полоса планта/дефуза — показывается ТОЛЬКО пока работа реально идёт.
func _update_bar() -> void:
	if _bar_bg == null or _mt == null:
		return
	var frac := 0.0
	var caption := ""
	var col := Color(0.95, 0.75, 0.2)
	if _mt.phase == Match.Phase.LIVE and _mt.plant_progress > 0.0:
		frac = clampf(_mt.plant_progress / float(Balance.RULES["PLANT_TIME"]), 0.0, 1.0)
		caption = "УСТАНОВКА"
	elif _mt.phase == Match.Phase.PLANTED and _mt.defuse_accum > 0.0:
		frac = clampf(_mt.defuse_accum / float(Balance.RULES["DEFUSE_TIME"]), 0.0, 1.0)
		caption = "РАЗМИНИРОВАНИЕ"
		col = Color(0.35, 0.85, 1.0)
	if frac <= 0.0:
		_bar_bg.visible = false
		return
	_bar_bg.visible = true
	_bar_fill.color = col
	_bar_fill.position = Vector2(2, 2)
	_bar_fill.size = Vector2((_bar_bg.size.x - 4) * frac, _bar_bg.size.y - 4)
	_bar_label.text = caption


# «за какую сторону играю» — без этого непонятно, ставить шип или защищать
func _side_name() -> String:
	if _mt == null or player == null:
		return ""
	return "АТАКА" if player.team == _mt.attack_team else "ЗАЩИТА"


func _on_hit(part: String, dmg: int) -> void:
	hitmark.text = ("ХЕДШОТ %d" if part == "head" else "%d") % dmg
	hitmark.modulate = Color(1.0, 0.35, 0.35) if part == "head" else Color(1, 1, 1)
	hitmark.modulate.a = 1.0
	var tw := hitmark.create_tween()
	tw.tween_property(hitmark, "modulate:a", 0.0, 0.4)
