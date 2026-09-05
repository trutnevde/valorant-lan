# Quality (autoload) — перф-фолбэк по клавише P, как в веб-версии.
#
# ЗАЧЕМ: замер перфа (tools/perfcheck.gd) снят на RTX 5060 Laptop и дал ~164 FPS. Это
# СИЛЬНАЯ карта, и правило 6 «60 FPS на средней видеокарте» им не доказывается. Дорогие
# статьи расхода — SSIL, SSAO и glow; на средней карте они могут съесть больше половины
# кадра. Поэтому даём явный переключатель, а не надеемся на запас.
#
# Три уровня: «полный» (как сгенерировано), «средний» (без SSIL), «быстрый» (без SSIL,
# SSAO и glow, тени короче). Уровень запоминается между запусками.
extends Node

enum Level { FULL, MEDIUM, FAST }

const CFG_PATH := "user://quality.cfg"

var level: int = Level.FULL

signal changed(level: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		level = int(cfg.get_value("gfx", "level", Level.FULL))
	# окружение появляется вместе с картой — применяем на следующий кадр и при смене сцены
	get_tree().node_added.connect(_on_node_added)
	call_deferred("apply")


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment:
		n.ready.connect(apply, CONNECT_ONE_SHOT)


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("toggle_quality"):
		set_level((level + 1) % 3)


func set_level(l: int) -> void:
	level = l
	var cfg := ConfigFile.new()
	cfg.set_value("gfx", "level", level)
	cfg.save(CFG_PATH)
	apply()
	changed.emit(level)


func level_name() -> String:
	match level:
		Level.FULL: return "ПОЛНОЕ"
		Level.MEDIUM: return "СРЕДНЕЕ"
		_: return "БЫСТРОЕ"


func apply() -> void:
	var we := _find_env()
	if we == null or we.environment == null:
		return
	var e: Environment = we.environment
	e.ssil_enabled = level == Level.FULL
	e.ssao_enabled = level != Level.FAST
	e.glow_enabled = level != Level.FAST
	# тени: на быстром режиме короче дистанция и один каскад — самый ощутимый выигрыш
	for l in get_tree().get_nodes_in_group("sun"):
		_tune_sun(l as DirectionalLight3D)
	var scene := get_tree().current_scene
	if scene:
		var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			_tune_sun(sun)


func _tune_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	match level:
		Level.FULL:
			sun.directional_shadow_max_distance = 120.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		Level.MEDIUM:
			sun.directional_shadow_max_distance = 80.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:
			sun.directional_shadow_max_distance = 45.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL


func _find_env() -> WorldEnvironment:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return _dig(scene)


func _dig(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment:
		return n as WorldEnvironment
	for c in n.get_children():
		var f := _dig(c)
		if f:
			return f
	return null
