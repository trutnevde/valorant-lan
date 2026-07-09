# Минимальный HUD G1: прицел, патроны, хитмаркер. Полный HUD — фаза G9.
extends CanvasLayer

@onready var ammo_label: Label = $Ammo
@onready var hitmark: Label = $Hitmark
@onready var weapon_rig: WeaponRig = get_parent().get_node("WeaponRig")


func _ready() -> void:
	weapon_rig.hit_target.connect(_on_hit)


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


func _on_hit(part: String, dmg: int) -> void:
	hitmark.text = ("ХЕДШОТ %d" if part == "head" else "%d") % dmg
	hitmark.modulate = Color(1.0, 0.35, 0.35) if part == "head" else Color(1, 1, 1)
	hitmark.modulate.a = 1.0
	var tw := hitmark.create_tween()
	tw.tween_property(hitmark, "modulate:a", 0.0, 0.4)
