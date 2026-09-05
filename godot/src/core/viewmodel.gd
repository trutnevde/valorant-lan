# Вьюмодель первого лица: руки + ствол из Blaster Kit, и ВСЁ ощущение веса с веба 1:1
# (web weapons.js:416-461): свей за мышью с рецентровкой, боб при ходьбе и «дыхание» в покое,
# толчок ствола отдачей, доставание снизу, поза прицеливания к центру, наклон при
# перезарядке. Раньше здесь висел один BoxMesh без единого движения.
#
# Узел живёт в Head/Viewmodel игрока; базовое смещение узла (0.22,-0.18,-0.35) — «плечо»,
# поверх которого накладываются формулы веба.
class_name Viewmodel
extends Node3D

const SWAY_SENS := 0.00009    # web:60
const HAND_COL := Color(0.16, 0.15, 0.17)
const GUN_SCALE := 0.58       # реальный 0.8-м ствол в 35 см от глаза закрывал четверть экрана

var _rig: WeaponRig
var _player: FpsPlayer
var _gun: Node3D
var _gun_id := ""
var _hands: Node3D
var _base := Vector3.ZERO
var _sway := Vector2.ZERO      # цель отставания от мыши
var _sway_cur := Vector2.ZERO  # сглаженная
var _bob_phase := 0.0
var _reload_tilt := 0.0
var _muzzle := Node3D.new()


func _ready() -> void:
	var n: Node = self
	while n != null and not (n is FpsPlayer):
		n = n.get_parent()
	_player = n as FpsPlayer
	if _player == null:
		return
	_rig = _player.get_node_or_null("WeaponRig") as WeaponRig
	_base = position
	_hands = _build_hands()
	add_child(_hands)
	add_child(_muzzle)
	_muzzle.name = "Muzzle"
	_swap_gun("classic")


# руки: два перчаточных «кулака» + предплечья в цвете агента, чтобы читалось, за кого играешь
func _build_hands() -> Node3D:
	var root := Node3D.new()
	root.name = "Hands"
	var accent := HAND_COL
	var card: Dictionary = Balance.CHARACTERS.get(_player.char_id, {})
	if card.has("darkColor"):
		accent = Color(String(card["darkColor"]))
	var skin := StandardMaterial3D.new()
	skin.albedo_color = accent
	skin.roughness = 0.85
	var glove := StandardMaterial3D.new()
	glove.albedo_color = HAND_COL
	glove.roughness = 0.7
	# правая: на рукояти; левая: под цевьём
	for side: float in [1.0, -1.0]:
		var fore := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.024
		cm.height = 0.2
		fore.mesh = cm
		fore.material_override = skin
		fore.rotation = Vector3(-0.35 * side + 0.9, 0.0, 0.25 * side)
		fore.position = Vector3(0.03 * side + 0.02, -0.09, 0.02 - (0.14 if side < 0 else 0.0))
		root.add_child(fore)
		var fist := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.03
		sm.height = 0.06
		fist.mesh = sm
		fist.material_override = glove
		fist.position = Vector3(0.02 * side + 0.02, -0.05, -0.08 - (0.22 if side < 0 else 0.0))
		root.add_child(fist)
	return root


func _swap_gun(id: String) -> void:
	if _gun and is_instance_valid(_gun):
		_gun.queue_free()
	_gun = WeaponModels.make(id)  # имя узла «Gun_<id>» — по нему WeaponModels отдаёт длину
	# хват: ствол чуть правее и ниже центра, рукоять у правого кулака
	# уменьшенная и отодвинутая вьюмодель — классический приём FPS вместо отдельного FOV
	_gun.scale = Vector3.ONE * GUN_SCALE
	_gun.position = Vector3(0.03, -0.04, -0.16)
	add_child(_gun)
	_gun_id = id
	var len := WeaponModels.length_of(_gun) * GUN_SCALE
	_muzzle.position = _gun.position + Vector3(0.0, 0.03, -len)


func muzzle_pos() -> Vector3:
	return _muzzle.global_position


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_sway.x = clampf(_sway.x - mm.relative.x * SWAY_SENS, -0.05, 0.05)
		_sway.y = clampf(_sway.y - mm.relative.y * SWAY_SENS, -0.05, 0.05)


func _process(dt: float) -> void:
	if _player == null or _rig == null:
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
	# поза прицеливания (web:445)
	var aim_x := -0.28 * a
	var aim_y := 0.088 * a - eq * 0.24
	var aim_z := 0.14 * a
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
