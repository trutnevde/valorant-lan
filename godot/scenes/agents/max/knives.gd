# Макс X «Стальные перья» (УЛЬТА): 5 ножей 70/150 на 12 с; убийство обновляет ножи (web).
class_name MaxKnives
extends Ability


func _init() -> void:
	char_id = "max"
	key = "X"


func _ready() -> void:
	super()
	# твист/паритет: килл обновляет ножи (и рывок — слушает MaxDash отдельно)
	var mt := Match.find(get_tree())
	if mt:
		mt.killer_scored.connect(_on_kill)


func _on_kill(killer: Node) -> void:
	if killer != player:
		return
	var rig := player.get_node("WeaponRig") as WeaponRig
	if rig.knives_active():
		rig.start_knives()  # полное обновление (web: убийство обновляет ножи)


func cast() -> void:
	(player.get_node("WeaponRig") as WeaponRig).start_knives()
