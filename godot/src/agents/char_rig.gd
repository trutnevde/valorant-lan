# CharRig — боец от третьего лица на риггованной модели с ЧЕЛОВЕЧЕСКИМИ пропорциями:
# Quaternius «Animated Human» (CC0, FBX, скелет в именовании Mixamo, анимации Idle/Walk/
# Run/Jump/Death). AnimationTree движка (правило 1), ствол в кости RightHand.
#
# Модель приходит в сантиметрах (высота 0.08 юнита) — рост подгоняется АВТО-ФИТОМ по
# мировому AABB до HEIGHT, поэтому сюда можно подложить любой другой риг (солдат WW2 и т.п.)
# без правки чисел. Кость руки и анимации ищутся по именам, а не по индексам.
#
# Опознание: одежда — по агенту (шесть CC0-текстур пака), плюс мягкий оттенок цвета агента.
extends Node3D

const MODEL_PATH := "res://assets/models/characters/quaternius/human.fbx"
const TEX_DIR := "res://assets/models/characters/quaternius/Textures/"
const HEIGHT := 1.75
# одежда по агенту: у пака 6 одетых вариантов (светлая/тёмная кожа × 3 наряда)
const OUTFIT := {
	"max": "ClothedLightSkin", "artemiy": "ClothedLightSkin1", "fafik": "ClothedDarkSkin2",
	"sova": "ClothedLightSkin2", "denis": "ClothedDarkSkin", "gera": "ClothedLightSkin1",
	"vova": "ClothedDarkSkin1", "sanek": "ClothedLightSkin2", "ira": "ClothedLightSkin",
	"koniliy": "ClothedDarkSkin2",
}
const HAND_BONES := ["RightHand", "hand.r", "mixamorig:RightHand", "Hand.R", "handslot.r"]
# ключи состояний → подстроки имён анимаций (у Quaternius это "Human Armature|Idle" и т.п.)
const ANIM_KEYS := {
	"Idle": ["Idle"], "Walk": ["Walk"], "Run": ["Run"], "Jump": ["Jump"], "Death": ["Death"],
}

@export var team := ""
@export var char_id := ""

var _owner_node: Node
var _model: Node3D
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _hand: BoneAttachment3D
var _gun: Node3D
var _gun_id := ""
var _last_pos := Vector3.ZERO
var _state := ""
var _fit := 1.0
var _anim_name := {}  # состояние → реальное имя анимации


func _ready() -> void:
	_owner_node = get_parent()
	if _owner_node:
		if team == "" and _owner_node.get("team") != null:
			team = String(_owner_node.get("team"))
		if char_id == "" and _owner_node.get("char_id") != null:
			char_id = String(_owner_node.get("char_id"))
	build()
	_last_pos = global_position


func build() -> void:
	for c in get_children():
		c.queue_free()
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		push_warning("CharRig: нет модели " + MODEL_PATH)
		return
	_model = scene.instantiate() as Node3D
	_model.rotation.y = PI  # модель смотрит в +Z, «вперёд» у Godot -Z — иначе бежит спиной
	add_child(_model)
	_fit_height()
	_dress()
	_setup_tree()
	_setup_hand()


# авто-фит: измеряем мировой AABB и масштабируем до HEIGHT, ноги ставим на y=0
func _fit_height() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a := m.get_aabb()
		var gt := m.global_transform
		for i in 8:
			var corner := a.position + Vector3(a.size.x * (i & 1), a.size.y * ((i >> 1) & 1), a.size.z * ((i >> 2) & 1))
			var c := gt * corner
			lo = lo.min(c)
			hi = hi.max(c)
	var h := hi.y - lo.y
	if h <= 0.0001:
		return
	_fit = HEIGHT / h
	_model.scale = Vector3.ONE * _fit
	_model.position.y = -lo.y * _fit  # низ модели на уровень ног владельца


# одежда по агенту + мягкий оттенок его цвета (текстура ведёт, оттенок подкрашивает)
func _dress() -> void:
	var tex_name: String = OUTFIT.get(char_id, "ClothedLightSkin")
	var tex := load(TEX_DIR + tex_name + ".png") as Texture2D
	var card: Dictionary = Balance.CHARACTERS.get(char_id, {})
	var tint := Color.WHITE
	if card.has("color"):
		tint = Color(String(card["color"])).lerp(Color.WHITE, 0.7)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.albedo_color = tint
			mat.roughness = 0.9
			m.set_surface_override_material(s, mat)


func _find_anim(ap: AnimationPlayer, keys: Array) -> String:
	for nm in ap.get_animation_list():
		for k in keys:
			if String(nm).findn(String(k)) >= 0:
				return String(nm)
	return ""


# AnimationTree: стейт-машина Idle/Walk/Run/Jump/Death с кроссфейдом «любой → любой»
func _setup_tree() -> void:
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return
	var ap := aps[0] as AnimationPlayer
	var sm := AnimationNodeStateMachine.new()
	for state in ANIM_KEYS:
		var nm := _find_anim(ap, ANIM_KEYS[state])
		if nm == "":
			continue
		_anim_name[state] = nm
		var anim := ap.get_animation(nm)
		anim.loop_mode = Animation.LOOP_NONE if state == "Death" else Animation.LOOP_LINEAR
		var node := AnimationNodeAnimation.new()
		node.animation = nm
		sm.add_node(state, node)
	var states := _anim_name.keys()
	for a_nm in states:
		for b_nm in states:
			if a_nm == b_nm:
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = 0.15
			tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			sm.add_transition(a_nm, b_nm, tr)
	_tree = AnimationTree.new()
	_tree.name = "Tree"
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(ap)
	_tree.tree_root = sm
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback and _anim_name.has("Idle"):
		_playback.start("Idle")
		_state = "Idle"


func _setup_hand() -> void:
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel := skels[0] as Skeleton3D
	for bone in HAND_BONES:
		if skel.find_bone(bone) >= 0:
			_hand = BoneAttachment3D.new()
			_hand.bone_name = bone
			skel.add_child(_hand)
			break
	if _hand:
		_swap_gun(_current_weapon())


func _current_weapon() -> String:
	if _owner_node == null:
		return "classic"
	var rig := _owner_node.get_node_or_null("WeaponRig")
	if rig:
		return String(rig.get("current_id"))
	if _owner_node.get("weapon_id") != null:
		return String(_owner_node.get("weapon_id"))
	return "classic"


func _swap_gun(id: String) -> void:
	if _hand == null:
		return
	if _gun and is_instance_valid(_gun):
		_gun.queue_free()
	_gun = WeaponModels.make(id)
	_hand.add_child(_gun)
	# Ствол вдоль пальцев (ладонь обхватывает рукоять), верхом в сторону большого пальца:
	# оси берём из самого скелета (rest-позы указательного и большого пальцев), а не из
	# угаданных углов — риг можно менять.
	var skel := _hand.get_parent() as Skeleton3D
	var hb := skel.find_bone(_hand.bone_name)
	var fingers := Vector3.UP
	var thumb := Vector3.RIGHT
	for c in skel.get_bone_children(hb):
		var nm := skel.get_bone_name(c)
		var dir := skel.get_bone_rest(c).origin.normalized()
		if nm.findn("Thumb") >= 0:
			thumb = dir
		elif nm.findn("Middle") >= 0 or fingers == Vector3.UP:
			fingers = dir
	var up := thumb - fingers * fingers.dot(thumb)
	if up.length_squared() < 0.01:
		up = Vector3.RIGHT
	_gun.basis = Basis.looking_at(fingers, up.normalized())
	# Компенсируем ФАКТИЧЕСКИЙ мировой масштаб кости, а не свой авто-фит: у FBX внутри свой
	# коэффициент (сантиметры → метры), и делить только на _fit давало ствол в сантиметр.
	var gs := _hand.global_transform.basis.get_scale()
	_gun.scale = Vector3(1.0 / maxf(0.0001, gs.x), 1.0 / maxf(0.0001, gs.y), 1.0 / maxf(0.0001, gs.z))
	# рукоять — в ладонь: корень модели стоит в центре габаритов, сдвигаем на точку хвата
	var box := WeaponModels.local_aabb(_gun)
	var long_gun := box.size.z > 0.75
	var grip := Vector3(0.0, box.position.y + box.size.y * 0.35, box.position.z + box.size.z * (0.62 if long_gun else 0.72))
	_gun.position = -(_gun.basis * grip)
	_gun_id = id


func _process(dt: float) -> void:
	if _playback == null or _owner_node == null or dt <= 0.0:
		return
	var want := _current_weapon()
	if want != _gun_id:
		_swap_gun(want)
	var alive := int(_owner_node.get("hp")) > 0
	if not alive:
		_go("Death")
		return
	var vel := Vector3.ZERO
	if _owner_node is CharacterBody3D:
		vel = (_owner_node as CharacterBody3D).velocity
	if vel.length() < 0.01:
		vel = (global_position - _last_pos) / dt  # сетевые игроки: физика у них выключена
	_last_pos = global_position
	var on_floor := (_owner_node as CharacterBody3D).is_on_floor() if _owner_node is CharacterBody3D else true
	var spd := Vector2(vel.x, vel.z).length()
	if not on_floor and absf(vel.y) > 1.5:
		_go("Jump")
	elif spd < 0.4:
		_go("Idle")
	else:
		_go("Run" if spd > 4.0 else "Walk")


func _go(state: String) -> void:
	if not _anim_name.has(state) or state == _state:
		return
	if _playback.get_current_node() == state:
		_state = state
		return
	_playback.travel(state)
	_state = state


func round_reset() -> void:
	if _playback and _anim_name.has("Idle"):
		_playback.start("Idle")
		_state = "Idle"
