# Вспышка (логика, хост): ЛЕТЯЩИЙ снаряд, а не мгновенный расчёт точки.
#
# Было: точка попа считалась формулой from + dir * SPEED * FUSE, то есть по прямой и СКВОЗЬ
# СТЕНЫ — вспышка, брошенная в стену, взрывалась за ней. И параметра кривизны не было вовсе,
# поэтому все четыре флеш-способности (Артемий C, Вова Q, тапок Фафика, ржание Конилия)
# летели одинаково.
#
# Теперь как в вебе (abilities.js:1011-1041):
#  • vel = dir * FLASH_SPEED * (кривая ? 1.0 : 1.4) — прямая летит быстрее;
#  • кривая получает боковое ускорение cross(dir, UP) * CURVE_ACC — тот самый «крюк»
#    Артемия, которым вспышку заводят за угол;
#  • каждый кадр шаг проверяется рейкастом: упёрлись в геометрию — снаряд ВСТАЁТ и лопается
#    на месте, а не за стеной;
#  • по FLASH_FUSE — поп в фактической точке.
extends Node

const CURVE_ACC := 10.0   # web abilities.js:355 — multiplyScalar(10)
const STRAIGHT_MUL := 1.4 # web abilities.js:357

var data := {}  # {fx,fy,fz, dx,dy,dz, owner_path, curve}

var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _curve := Vector3.ZERO
var _born := 0.0
var _stopped := false


func _ready() -> void:
	_pos = Vector3(data["fx"], data["fy"], data["fz"])
	var dir := Vector3(data["dx"], data["dy"], data["dz"]).normalized()
	var curved := bool(data.get("curve", false))
	_vel = dir * float(Balance.ABILITY["FLASH_SPEED"]) * (1.0 if curved else STRAIGHT_MUL)
	if curved:
		_curve = dir.cross(Vector3.UP).normalized() * CURVE_ACC
	_born = Time.get_ticks_msec() / 1000.0


func _physics_process(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if not _stopped:
		_vel += _curve * dt
		var step := _vel * dt
		if step.length() > 0.0001:
			var space := _space()
			var q := PhysicsRayQueryParameters3D.create(_pos, _pos + step)
			var res := space.intersect_ray(q)
			if res.is_empty():
				_pos += step
			else:
				# упёрлись в геометрию — снаряд встаёт здесь (в вебе так же: vel и curve в ноль)
				_pos = res["position"] as Vector3
				_vel = Vector3.ZERO
				_curve = Vector3.ZERO
				_stopped = true
	if t - _born >= float(Balance.ABILITY["FLASH_FUSE"]):
		_pop()


func _pop() -> void:
	var pop := _pos
	var hits: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0:
			continue
		var eye := node.global_position + Vector3(0, 1.6, 0)
		var to := pop - eye
		var dist := to.length()
		if dist > 40.0 or dist < 0.1:
			continue
		var look := -node.global_transform.basis.z
		var dot := to.normalized().dot(look)
		if dot < 0.3:
			continue  # не смотрит — не слепнет
		if not _los(eye, pop, node):
			continue
		var k := (dot - 0.3) / 0.7
		hits.append({ "node": node, "dur": 0.4 + k * (float(Balance.ABILITY["FLASH_MAX_BLIND"]) - 0.4) })
	get_node("/root/Fx").call("blind_targets", pop, hits)
	queue_free()


func _los(from: Vector3, to: Vector3, exclude_node: Node3D) -> bool:
	var space := _space()
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if exclude_node is CollisionObject3D:
		q.exclude = [(exclude_node as CollisionObject3D).get_rid()]
	var res := space.intersect_ray(q)
	return res.is_empty()


# Физическое пространство берём у КОРНЕВОГО вьюпорта, а не у current_scene: снаряд —
# обычный Node без своего мира, а current_scene бывает пустым (headless-тесты), и тогда
# рейкаст молча падал, снаряд не двигался и пролетал «сквозь» стены.
func _space() -> PhysicsDirectSpaceState3D:
	return get_tree().root.world_3d.direct_space_state
