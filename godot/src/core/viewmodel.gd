# Вьюмодель первого лица: риг рук ArmsRig + ствол из WeaponModels в РЕАЛЬНОМ масштабе, и всё
# ощущение веса с веба 1:1 (web weapons.js:416-461): свей за мышью с рецентровкой, боб при
# ходьбе и «дыхание» в покое, толчок ствола отдачей, доставание снизу, поза прицеливания
# к центру, наклон при перезарядке.
#
# Рисуется отдельной камерой (ViewmodelCamera: слой 2, узкий FOV): ствол настоящего размера
# не закрывает пол-экрана и не проваливается в стены. Раньше ствол уменьшали в 0.58 и
# отодвигали, а руками были капсулы, которые до него не доставали.
#
# Узел живёт в Head/Viewmodel игрока; его базовое смещение считается по классу ствола
# (place_for), поверх него накладываются формулы веба. Плечи рига стоят относительно ГЛАЗ.
class_name Viewmodel
extends Node3D

const SWAY_SENS := 0.00009    # web:60
const SHOULDERS := Vector3(0.0, -0.2, 0.05)   # центр плеч относительно глаз
# посадка ствола относительно ГЛАЗ: X/Z центра габаритов и высота ВЕРХА ствола (линии
# прицела); короткое и длинное оружие сидят по-разному, как в классических FPS
const PLACE_SHORT := Vector3(0.10, -0.06, -0.46)
const PLACE_LONG := Vector3(0.13, -0.11, -0.60)
const SHORT_LEN := 0.25
const LONG_LEN := 0.75
const AIM_PULL := 0.1                          # в прицеливании ствол подтягивается к глазу

var _rig: WeaponRig
var _player: FpsPlayer
var _gun: Node3D
var _gun_id := ""
var _arms: ArmsRig
var _base := Vector3.ZERO
var _sway := Vector2.ZERO      # цель отставания от мыши
var _sway_cur := Vector2.ZERO  # сглаженная
var _bob_phase := 0.0
var _reload_tilt := 0.0
var _aim_off := Vector3.ZERO   # смещение узла в прицеливании: мушка на линию глаз по центру
var _muzzle := Node3D.new()
var _local := false


func _ready() -> void:
	var n: Node = self
	while n != null and not (n is FpsPlayer):
		n = n.get_parent()
	_player = n as FpsPlayer
	if _player == null:
		return
	if NetHub.online() and not _player.is_multiplayer_authority():
		visible = false  # чужому игроку вьюмодель не нужна — у него видно тело
		return
	_local = true
	_rig = _player.get_node_or_null("WeaponRig") as WeaponRig
	_base = PLACE_SHORT
	add_child(_muzzle)
	_muzzle.name = "Muzzle"
	_arms = ArmsRig.new()
	_arms.name = "Arms"
	_arms.position = SHOULDERS - _base
	add_child(_arms)
	_arms.build(_dark_skin())
	_to_view_layer(_arms)
	_swap_gun("classic")


# тон кожи — по одежде агента из CharRig (тёмные варианты пака → тёмная кожа рук)
func _dark_skin() -> bool:
	var rig_script := load("res://src/agents/char_rig.gd") as GDScript
	var outfit: Dictionary = rig_script.get_script_constant_map().get("OUTFIT", {})
	return String(outfit.get(_player.char_id, "")).contains("Dark")


# всё видимое во вьюмодели — на слой камеры вьюмодели (основная камера его не рисует)
static func _to_view_layer(root: Node) -> void:
	var nodes: Array = [root]
	nodes.append_array(root.find_children("*", "VisualInstance3D", true, false))
	for v in nodes:
		if v is VisualInstance3D:
			(v as VisualInstance3D).layers = ViewmodelCamera.VIEW_LAYER


func _swap_gun(id: String) -> void:
	if _gun and is_instance_valid(_gun):
		_gun.queue_free()
	_gun = WeaponModels.make(id)  # имя узла «Gun_<id>» — по нему WeaponModels отдаёт длину
	add_child(_gun)
	_to_view_layer(_gun)
	_gun_id = id
	var box := WeaponModels.local_aabb(_gun)
	_base = place_for(box)
	position = _base
	_arms.position = SHOULDERS - _base
	var top := box.position.y + box.size.y
	# дуло — передний срез ствола по его габаритам, у линии прицела
	_muzzle.position = Vector3(0.0, top - 0.015, box.position.z)
	# прицеливание: узел уезжает так, чтобы верх ствола (мушка) лёг на линию глаз по центру
	_aim_off = Vector3(-_base.x, -_base.y - top - 0.012, AIM_PULL)
	_arms.hold(_gun)


# где держать ствол: по длине — от пистолетной посадки к винтовочной (ПП посередине) — так,
# чтобы ВЕРХ его габаритов лёг на заданную высоту под глазами; корень модели — центр
# её габаритов (WeaponModels.make)
static func place_for(box: AABB) -> Vector3:
	var t := clampf((box.size.z - SHORT_LEN) / (LONG_LEN - SHORT_LEN), 0.0, 1.0)
	var p := PLACE_SHORT.lerp(PLACE_LONG, t)
	return Vector3(p.x, p.y - (box.position.y + box.size.y), p.z)


func muzzle_pos() -> Vector3:
	return _muzzle.global_position


func _input(event: InputEvent) -> void:
	if _local and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_sway.x = clampf(_sway.x - mm.relative.x * SWAY_SENS, -0.05, 0.05)
		_sway.y = clampf(_sway.y - mm.relative.y * SWAY_SENS, -0.05, 0.05)


func _process(dt: float) -> void:
	if not _local or _rig == null:
		return
	var want := "knife" if _rig.knives_active() else _rig.current_id
	if want != _gun_id:
		_swap_gun(want)
	# свей затухает и рецентрируется (web:420-424)
	_sway *= exp(-dt * 9.0)
	_sway_cur += (_sway - _sway_cur) * minf(1.0, dt * 12.0)
	var a := _player.aim_t
	var sway_mul := 1.0 - a * 0.72
	# боб (web:427-433)
	var spd := Vector2(_player.velocity.x, _player.velocity.z).length()
	var moving := _player.is_on_floor() and spd > 0.6
	_bob_phase += dt * ((6.5 + (spd / 6.2) * 4.5) if moving else 1.6)
	var bob_amt := (minf(1.1, spd / 6.2) if moving else 0.0) * (0.5 if _player.crouch else 1.0) * (0.5 if _player.walk else 1.0) * (1.0 - a * 0.8)
	var idle_bob := 0.0 if moving else sin(_bob_phase) * 0.004
	var bob_x := sin(_bob_phase) * 0.015 * bob_amt
	var bob_y := -absf(sin(_bob_phase)) * 0.013 * bob_amt + idle_bob
	# доставание: ствол поднимается снизу (web:437)
	var feel := Balance.weapon_feel(_rig.current_id)
	var now := Time.get_ticks_msec() / 1000.0
	var eq := clampf((_rig.ready_at - now) / maxf(0.01, float(feel["equip"])), 0.0, 1.0)
	# поза прицеливания (web:445) — к центру и на линию глаз, по габаритам текущего ствола
	var aim_x := _aim_off.x * a
	var aim_y := _aim_off.y * a - eq * 0.24
	var aim_z := _aim_off.z * a
	# наклон при перезарядке
	var reloading := _rig.reloading_until > now
	_reload_tilt += ((0.55 if reloading else 0.0) - _reload_tilt) * minf(1.0, dt * 8.0)
	position = _base + Vector3(
		aim_x + bob_x + _sway_cur.x * sway_mul * 0.7,
		aim_y + bob_y + _sway_cur.y * sway_mul * 0.7 - _player.land_bob() * 0.35,
		aim_z + _rig.vkick_pos)
	rotation = Vector3(
		_sway_cur.y * sway_mul * 3.0 - _rig.vkick_rot - eq * 0.7 - _reload_tilt + ((sin(_bob_phase) * 0.012 * bob_amt) if moving else 0.0),
		-_sway_cur.x * sway_mul * 3.5,
		_sway_cur.x * sway_mul * 2.2 + ((sin(_bob_phase * 0.5) * 0.02 * bob_amt) if moving else 0.0))
	# снайперский зум: вьюмодель прячем, как в вебе (sniperScoped)
	var scoped := bool(_rig.w().get("scope", false)) and a > 0.85
	visible = not scoped
