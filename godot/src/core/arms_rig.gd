# ArmsRig — руки первого лица на CC0-риге «FPS Arms» (реалистичные предплечья с кожей,
# Blender-скелет: кисть висит на control-кости в корне, локтевая цепочка upper_arm→forearm).
# Раньше руками были две капсулы и два шара.
#
# Поза считается, а не рисуется: кисти ставятся на рукоять и цевьё по ГАБАРИТАМ ствола
# (AABB в его корне), плечо и локоть доводит TwoBoneIK3D движка (правило 1), пальцы
# сжимаются поворотом фаланг. Поэтому один код держит и пистолет, и винтовку, и нож.
#
# Оси кисти в её локале (измерено по rest-позе пака): +Y — вдоль пальцев, +Z — ладонь,
# ±X — сторона большого пальца (R: +X, L: −X). Базис «мир из локала» для обеих кистей —
# Basis(F×P, F, P): зеркало левой уже сидит в её локальных осях.
class_name ArmsRig
extends Node3D

const MODEL := "res://assets/models/weapons/arms/fps_arms.fbx"
const TEX := "res://assets/models/weapons/arms/arms_diffuse.png"
const SCALE := 1.0                 # риг в метрах, как и стволы: вьюмодель рисует своя камера
const DARK_SKIN := Color(0.62, 0.45, 0.36)
# сжатие пальцев (рад) по фалангам: указательный — на спуске, остальные — в кулак
const CURL := {
	"f_index": [0.35, 0.45, 0.3], "f_middle": [0.85, 1.0, 0.6],
	"f_ring": [0.95, 1.05, 0.7], "f_pinky": [1.05, 1.1, 0.7],
}
const THUMB := [0.25, 0.45]
# смещения запястья от точки хвата (в метрах, пространство вьюмодели: X вправо, -Z вперёд)
const WRIST_R := Vector3(0.01, -0.035, 0.05)
const WRIST_L_PISTOL := Vector3(-0.05, -0.05, 0.04)
const WRIST_L_LONG := Vector3(-0.04, -0.04, 0.0)
const ELBOW_R := Vector3(0.28, -0.3, 0.02)     # полюс локтя от плеча: вниз-наружу
const ELBOW_L := Vector3(-0.28, -0.3, -0.03)

var _model: Node3D
var _skel: Skeleton3D
var _ik: TwoBoneIK3D
var _targets := {}   # "R"/"L" → Node3D (цель запястья, в пространстве родителя ArmsRig)
var _poles := {}
var _hand_rest_inv := {}  # "R"/"L" → обратная rest-поза hand.X относительно её control-кости
var _ready_ok := false


func build(dark_skin: bool = false) -> void:
	var ps := load(MODEL) as PackedScene
	if ps == null:
		push_warning("ArmsRig: нет модели " + MODEL)
		return
	_model = ps.instantiate() as Node3D
	_model.rotation.y = PI          # риг «смотрит» в +Z — разворачиваем вперёд по Godot
	_model.scale = Vector3.ONE * SCALE
	add_child(_model)
	var tex := load(TEX) as Texture2D
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = DARK_SKIN if dark_skin else Color.WHITE
	mat.roughness = 0.72
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	_skel = skels[0] as Skeleton3D
	for side in ["R", "L"]:
		var hb := _skel.find_bone("hand." + side)
		_hand_rest_inv[side] = _skel.get_bone_rest(hb).affine_inverse()
		var t := Node3D.new()
		t.name = "Wrist" + side
		add_child(t)
		_targets[side] = t
		var p := Node3D.new()
		p.name = "Elbow" + side
		add_child(p)
		_poles[side] = p
	_ik = TwoBoneIK3D.new()
	_ik.name = "ArmIK"
	_skel.add_child(_ik)
	_ik.set_setting_count(2)
	for i in 2:
		var side: String = ["R", "L"][i]
		_ik.set_root_bone_name(i, "upper_arm." + side)
		_ik.set_middle_bone_name(i, "forearm." + side)
		_ik.set_end_bone_name(i, "forearm." + side + "_end")
		_ik.set_target_node(i, _ik.get_path_to(_targets[side]))
		_ik.set_pole_node(i, _ik.get_path_to(_poles[side]))
	_curl_fingers()
	_ready_ok = true


# сжать пальцы обеих кистей: фаланги гнутся вокруг локальной X к ладони (+Z)
func _curl_fingers() -> void:
	for side in ["R", "L"]:
		for finger in CURL:
			var angles: Array = CURL[finger]
			for k in angles.size():
				_bend("%s.%02d.%s" % [finger, k + 1, side], float(angles[k]))
		for k in THUMB.size():
			_bend("thumb.%02d.%s" % [k + 1, side], float(THUMB[k]))


func _bend(bone: String, angle: float) -> void:
	var bi := _skel.find_bone(bone)
	if bi < 0:
		return
	var rest := _skel.get_bone_rest(bi).basis.get_rotation_quaternion()
	_skel.set_bone_pose_rotation(bi, rest * Quaternion(Vector3.RIGHT, angle))


# взять ствол: gun — узел Gun_<id> в том же родителе, что и ArmsRig (пространство вьюмодели)
func hold(gun: Node3D) -> void:
	if not _ready_ok or gun == null:
		return
	var box := WeaponModels.local_aabb(gun)
	var size := box.size
	var lo := box.position
	var length := size.z
	var long_gun := length > 0.4  # ПП и обрезы — тоже с поддержкой под цевьё
	var knife := gun.name == "Gun_knife"
	# рукоять: задняя часть ствола, нижняя треть; цевьё — середина длины, под линией ствола
	var top := lo.y + size.y
	var grip_l := Vector3(lo.x + size.x * 0.5, lo.y + size.y * (0.4 if knife else 0.33), lo.z + length * (0.62 if long_gun else 0.72))
	var grip := gun.transform * grip_l
	var f_r := Vector3(0.0, 0.3, -1.0).normalized()
	_place("R", grip + WRIST_R, f_r, Vector3(-1, 0, 0))
	if knife:
		# нож: левая свободна, чуть ниже кадра
		_place("L", Vector3(-0.2, -0.32, -0.28), Vector3(0.2, 0.2, -1.0).normalized(), Vector3(0.3, 1, 0))
	elif long_gun:
		var sup_l := Vector3(lo.x + size.x * 0.5, top - 0.08, lo.z + length * 0.45)
		var sup := gun.transform * sup_l
		_place("L", sup + WRIST_L_LONG, Vector3(0.75, 0.15, -0.65).normalized(), Vector3(0.2, 1.0, 0.0))
	else:
		_place("L", grip + WRIST_L_PISTOL, f_r, Vector3(1, 0, 0))
	# плечи — корни цепочек; полюса локтей от них
	for side in ["R", "L"]:
		var ub := _skel.find_bone("upper_arm." + side)
		var shoulder := to_local(_skel.global_transform * _skel.get_bone_global_rest(ub).origin)
		(_poles[side] as Node3D).position = shoulder + (ELBOW_R if side == "R" else ELBOW_L)


# поставить кисть: запястье в wrist (пространство родителя), пальцы вдоль f, ладонь в p
func _place(side: String, wrist: Vector3, f: Vector3, p: Vector3) -> void:
	var fn := f.normalized()
	var pn := (p - fn * fn.dot(p)).normalized()
	var basis := Basis(fn.cross(pn), fn, pn).orthonormalized()
	var t := _targets[side] as Node3D
	t.transform = transform.affine_inverse() * Transform3D(basis, wrist)  # маркер — наш ребёнок
	# hand.<side> висит на control-кости в корне скелета: её глобальная поза = мир кисти
	# минус rest кисти относительно control. Базис — только поворот: у скелета масштаб 0.1,
	# и без ортонормализации кисть раздувало в 12 раз.
	var world: Transform3D = (get_parent() as Node3D).global_transform * Transform3D(basis, wrist)
	var in_skel: Transform3D = _skel.global_transform.affine_inverse() * world
	var pose := Transform3D(in_skel.basis.orthonormalized(), in_skel.origin) * (_hand_rest_inv[side] as Transform3D)
	var ctl := _skel.find_bone("hand." + side + ".control")
	_skel.set_bone_global_pose(ctl, pose)
