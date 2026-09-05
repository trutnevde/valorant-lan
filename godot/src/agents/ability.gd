# База способности (правило 4: одна способность = один компонент, вешается в Kit игрока).
# Заряды из Balance.CHARACTERS, сигнатурка — автоперезарядка по SIGNATURES,
# ульта (X) — гейт по player.ult >= ultCost (заряд только за киллы — канон).
class_name Ability
extends Node

var char_id := ""
var key := "C"   # C/Q/E/X
var charges := 0
var map_target := false   # целится кликом по тактической карте (дымы Вовы, орбиталка, ульта Фафика)

var _sig_ready_at := 0.0
var _pending_point := Vector3.INF  # подтверждённая точка карты на время одного каста

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
		if player.ult < int(Balance.CHARACTERS[char_id]["ultCost"]) or not can_cast():
			return
	else:
		if charges <= 0 or not can_cast():
			return
	# карта-цель: заряд НЕ тратим, пока игрок не ткнул точку (или не отменил)
	if map_target:
		var hud := player.get_node_or_null("HUD")
		if hud and hud.has_method("request_map_target"):
			hud.call("request_map_target", self)
			return
	_consume_and_cast()


# списание заряда/ульты + сам каст — общий путь для обычного и карта-целевого применения
func _consume_and_cast() -> void:
	if key == "X":
		player.ult = 0  # потратил ульту
	else:
		charges -= 1
		if _is_signature() and _sig_ready_at == 0.0:
			_sig_ready_at = _now() + float(Balance.SIGNATURES[char_id]["cd"])
	cast()
	used.emit(charges)


# HUD подтвердил точку на тактической карте
func map_target_confirmed(p: Vector3) -> void:
	_pending_point = p
	_consume_and_cast()
	_pending_point = Vector3.INF


# точка на земле/стене по взгляду (аналог web groundPoint).
# Если способность карта-целевая и точка уже подтверждена кликом — возвращаем её,
# поэтому компонентам способностей менять ничего не нужно.
func ground_point(max_dist := 22.0) -> Vector3:
	if _pending_point != Vector3.INF:
		return _pending_point
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
