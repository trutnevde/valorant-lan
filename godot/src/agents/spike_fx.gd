# SpikeFx — шип как ИГРОВАЯ ИНФОРМАЦИЯ, а не строка в HUD (железное правило 7).
#
# До этой фазы сигналы Match.spike_planted / spike_defused / spike_boom не имели ни одного
# слушателя во всём проекте: об установке и разминировании сообщал только текст матч-панели.
# Из-за этого не работал главный приём режима — дефуз-фейк: атака не слышала, что шип
# начали разминировать, а защита не могла найти шип на слух.
#
# Что даёт узел:
#  • бип шипа с УСКОРЕНИЕМ по мере истечения таймера — позиционный, слышен всем; по нему
#    защита ищет шип, а атака понимает, сколько осталось, не глядя на цифры;
#  • тики планта и дефуза — по ним слышно, что кто-то работает у шипа (основа фейков);
#  • установка, разминирование и взрыв — отдельными звуками;
#  • сам шип виден в мире и пульсирует в такт бипу.
extends Node3D

const BEEP_SLOW := 1.15   # интервал бипа сразу после планта
const BEEP_FAST := 0.13   # и в последние секунды
const TICK_EVERY := 0.42  # тики планта/дефуза

var _mt: Match
var _body: Node3D
var _light: OmniLight3D
var _beep_at := 0.0
var _tick_at := 0.0
var _last_plant := 0.0
var _last_defuse := 0.0
var _snd := {}


func _ready() -> void:
	_try_bind()


# Матч может появиться позже узла (порядок создания в сцене не гарантирован), поэтому
# привязку повторяем, пока не выйдет, — иначе шип молча остаётся без звука.
func _try_bind() -> bool:
	if _mt != null:
		return true
	_mt = Match.find(get_tree())
	if _mt == null:
		return false
	_mt.spike_planted.connect(_on_planted)
	_mt.spike_defused.connect(_on_defused)
	_mt.spike_boom.connect(_on_boom)
	_mt.phase_changed.connect(func(_p: int, _d: float) -> void: _sync_body())
	return true


func _snd_of(nm: String) -> AudioStream:
	if not _snd.has(nm):
		_snd[nm] = load("res://assets/audio/%s.ogg" % nm)
	return _snd[nm]


func _play(nm: String, pos: Vector3, vol := 0.0, pitch := 1.0) -> void:
	var ears := get_node_or_null("/root/Ears")
	if ears:
		ears.call("one_shot", get_tree().current_scene, pos, _snd_of(nm), "SFX", pitch, vol)


func _on_planted(pos: Vector3) -> void:
	_spawn_body(pos)
	_play("slam", pos, 2.0, 0.8)
	_beep_at = 0.0


func _on_defused() -> void:
	if _body:
		_play("confirm", _body.global_position, 2.0, 1.0)
	_clear_body()


func _on_boom() -> void:
	var p := _body.global_position if _body else global_position
	_play("explosion", p, 6.0, 0.9)
	_play("boom", p, 4.0, 0.7)
	_clear_body()


func _spawn_body(pos: Vector3) -> void:
	_clear_body()
	_body = Node3D.new()
	add_child(_body)
	_body.global_position = pos + Vector3(0, 0.18, 0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.36, 0.3)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.15, 0.18)
	mat.metallic = 0.7
	mat.roughness = 0.35
	mi.material_override = mat
	_body.add_child(mi)
	# мигающий сердечник — тот же ритм, что и звук: видно и слышно одно и то же
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	core.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.25, 0.2)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.25, 0.2)
	cmat.emission_energy_multiplier = 3.0
	core.material_override = cmat
	core.name = "Core"
	_body.add_child(core)
	core.position = Vector3(0, 0.26, 0)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.22)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_body.add_child(_light)
	_light.position = Vector3(0, 0.3, 0)


func _clear_body() -> void:
	if _body and is_instance_valid(_body):
		_body.queue_free()
	_body = null
	_light = null


func _sync_body() -> void:
	# раунд сменился — шипа в мире быть не должно
	if _mt and _mt.phase != Match.Phase.PLANTED and _body:
		_clear_body()


func _process(dt: float) -> void:
	if not _try_bind():
		return
	var t := _mt.now()
	if _mt.phase == Match.Phase.PLANTED and _mt.spike_planted_at != Vector3.INF:
		if _body == null:
			_spawn_body(_mt.spike_planted_at)  # клиент узнал о шипе позже (синк по сети)
		_beep(dt, t)
		_defuse_ticks(t)
	else:
		_plant_ticks(t)
	if _light:
		_light.light_energy = maxf(0.0, _light.light_energy - dt * 9.0)


func _beep(_dt: float, t: float) -> void:
	var left := maxf(0.0, _mt.deadline - t)
	var total := float(Balance.RULES["SPIKE_TIME"])
	var k := clampf(left / maxf(0.01, total), 0.0, 1.0)
	var interval := lerpf(BEEP_FAST, BEEP_SLOW, k)
	if t < _beep_at:
		return
	_beep_at = t + interval
	_play("ting", _body.global_position, -2.0, lerpf(1.5, 0.95, k))
	if _light:
		_light.light_energy = 2.4
	var core := _body.get_node_or_null("Core") as Node3D
	if core:
		core.scale = Vector3.ONE * 1.6
		var tw := core.create_tween()
		tw.tween_property(core, "scale", Vector3.ONE, minf(0.25, interval * 0.8))


func _plant_ticks(t: float) -> void:
	# кто-то ставит шип: слышно, что работа идёт
	if _mt.plant_progress > 0.0 and _mt.plant_progress > _last_plant:
		if t >= _tick_at and _mt.spike_carrier and is_instance_valid(_mt.spike_carrier):
			_tick_at = t + TICK_EVERY
			_play("hit", (_mt.spike_carrier as Node3D).global_position, -7.0, 0.85)
	_last_plant = _mt.plant_progress


func _defuse_ticks(t: float) -> void:
	# кто-то режет шип — по этому звуку атака понимает, что пора возвращаться (дефуз-фейки)
	if _mt.defuse_accum > 0.0 and _mt.defuse_accum > _last_defuse:
		if t >= _tick_at:
			_tick_at = t + TICK_EVERY
			_play("pop", _body.global_position, -3.0, 1.35)
	_last_defuse = _mt.defuse_accum
