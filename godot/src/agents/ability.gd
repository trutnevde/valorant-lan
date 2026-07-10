# База способности (правило 4: одна способность = один компонент, вешается в Kit игрока).
# Заряды из Balance.CHARACTERS, сигнатурка — автоперезарядка по SIGNATURES,
# ульта (X) — гейт по player.ult >= ultCost (заряд только за киллы — канон).
class_name Ability
extends Node

var char_id := ""
var key := "C"   # C/Q/E/X
var charges := 0

var _sig_ready_at := 0.0

@onready var player: FpsPlayer = _find_player()

signal used(charges_left: int)


func _find_player() -> FpsPlayer:
	var n: Node = self
	while n != null and not (n is FpsPlayer):
		n = n.get_parent()
	return n as FpsPlayer


func _ready() -> void:
	if key != "X":
		charges = int(Balance.CHARACTERS[char_id]["abilities"][key].get("charges", 1))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _is_signature() -> bool:
	var sig: Dictionary = Balance.SIGNATURES.get(char_id, {})
	return not sig.is_empty() and String(sig["key"]) == key


func _physics_process(_dt: float) -> void:
	if player == null or player.dead:
		return
	# автоперезарядка сигнатурки
	if _is_signature() and _sig_ready_at > 0.0 and _now() >= _sig_ready_at:
		var mx := int(Balance.CHARACTERS[char_id]["abilities"][key].get("charges", 1))
		if charges < mx:
			charges += 1
			used.emit(charges)
		_sig_ready_at = (_now() + float(Balance.SIGNATURES[char_id]["cd"])) if charges < mx else 0.0
	if not Input.is_action_just_pressed("ability_" + key.to_lower()):
		return
	if key == "X":
		var cost := int(Balance.CHARACTERS[char_id]["ultCost"])
		if player.ult < cost:
			return
		if not can_cast():
			return
		player.ult = 0  # потратил ульту
		cast()
	else:
		if charges <= 0 or not can_cast():
			return
		charges -= 1
		if _is_signature() and _sig_ready_at == 0.0:
			_sig_ready_at = _now() + float(Balance.SIGNATURES[char_id]["cd"])
		cast()
	used.emit(charges)


# точка на земле/стене по взгляду (аналог web groundPoint)
func ground_point(max_dist := 22.0) -> Vector3:
	var origin := player.eye_pos()
	var dir := player.aim_dir()
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	q.exclude = [player.get_rid()]
	var res := space.intersect_ray(q)
	var p: Vector3 = res["position"] if not res.is_empty() else origin + dir * max_dist
	p.y = maxf(0.0, p.y)
	return p


# переопределяется наследниками
func can_cast() -> bool:
	return true


func cast() -> void:
	pass
