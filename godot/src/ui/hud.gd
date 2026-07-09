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


func _on_hp(hp: int) -> void:
	if dmg_flash and hp < _last_hp:
		dmg_flash.modulate.a = 0.45
		var tw := dmg_flash.create_tween()
		tw.tween_property(dmg_flash, "modulate:a", 0.0, 0.35)
	_last_hp = hp


func _on_hit(part: String, dmg: int) -> void:
	hitmark.text = ("ХЕДШОТ %d" if part == "head" else "%d") % dmg
	hitmark.modulate = Color(1.0, 0.35, 0.35) if part == "head" else Color(1, 1, 1)
	hitmark.modulate.a = 1.0
	var tw := hitmark.create_tween()
	tw.tween_property(hitmark, "modulate:a", 0.0, 0.4)
