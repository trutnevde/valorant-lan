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


func _ready() -> void:
	weapon_rig.hit_target.connect(_on_hit)
	if player:
		player.hp_changed.connect(_on_hp)


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
		var dash := player.get_node_or_null("Kit/Dash")
		var launch := player.get_node_or_null("Kit/Launch")
		if dash and launch:
			kit_label.text = "C Рывок ×%d   Q Взлёт ×%d" % [int(dash.get("charges")), int(launch.get("charges"))]
	_process_match(_dt)


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
	_mt.killfeed.connect(_on_kill)
	_mt.round_ended.connect(func(w: String, r: String) -> void: _announce("Раунд: победа %s (%s)" % [w, r]))
	_mt.match_ended.connect(func(w: String) -> void: _announce("МАТЧ ОКОНЧЕН — ПОБЕДА %s" % w))
	_build_buy_menu()


func _announce(txt: String) -> void:
	_on_kill(txt, "", "", false)


func _on_kill(a: String, b: String, w: String, head: bool) -> void:
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
	_match_label.text = "Раунд %d · A %d : %d B · %s · %d:%02d · $%d" % [
		_mt.round_no, int(_mt.score["A"]), int(_mt.score["B"]), _phase_name(_mt.phase),
		int(left) / 60, int(left) % 60, player.credits]
	if _mt.spike_carrier == player and _mt.phase == Match.Phase.LIVE:
		_match_label.text += "  ·  ТЫ НЕСЁШЬ ШИП (4 — плант в сайте)"
	if Input.is_action_just_pressed("buy") and _mt.phase == Match.Phase.BUY:
		_buy_panel.visible = not _buy_panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _buy_panel.visible else Input.MOUSE_MODE_CAPTURED
	if _mt.phase != Match.Phase.BUY and _buy_panel.visible:
		_buy_panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_hit(part: String, dmg: int) -> void:
	hitmark.text = ("ХЕДШОТ %d" if part == "head" else "%d") % dmg
	hitmark.modulate = Color(1.0, 0.35, 0.35) if part == "head" else Color(1, 1, 1)
	hitmark.modulate.a = 1.0
	var tw := hitmark.create_tween()
	tw.tween_property(hitmark, "modulate:a", 0.0, 0.4)
