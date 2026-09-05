# perfcheck — перф-бюджет фазы (правило 6: 60 FPS на средней видеокарте).
# Открывает карту в окне, летает камерой по кругу N секунд и печатает JSON:
# средний/минимальный FPS, 1% low, время кадра, число draw-call'ов и примитивов.
# Headless не годится — без рендера мерить нечего.
#
#   godot --path . res://tools/perfcheck.tscn -- --scene=res://scenes/maps/bastion.tscn --seconds=20
extends Node

var _scene_path := "res://scenes/maps/bastion.tscn"
var _seconds := 20.0
var _warmup := 3.0
var _quality := -1

var _cam: Camera3D
var _t := 0.0
var _frames: Array[float] = []
var _span := 60.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_path = arg.substr(8)
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.substr(10))
		elif arg.begins_with("--quality="):
			# 0 полное / 1 среднее / 2 быстрое — чтобы мерить перф-фолбэк (клавиша P)
			_quality = int(arg.substr(10))
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		print(JSON.stringify({ "pass": false, "error": "сцена не загрузилась: " + _scene_path }))
		get_tree().quit(1)
		return
	var inst := packed.instantiate()
	add_child(inst)
	if inst.has_meta("map_meta"):
		var meta = JSON.parse_string(String(inst.get_meta("map_meta")))
		if meta is Dictionary:
			_span = maxf(float(meta.get("size_w", 60.0)), float(meta.get("size_d", 60.0)))
	_cam = Camera3D.new()
	_cam.fov = 74.0
	_cam.far = 400.0
	add_child(_cam)
	_cam.current = true
	# БЕЗ ЭТОГО ЗАМЕР ВРЁТ: с включённым V-Sync кадры упираются в развёртку монитора
	# (на этой машине ~164 Гц) и одинаковы на любом уровне качества — видно «запас», которого
	# на самом деле не измеряли. Снимаем ограничение, чтобы увидеть настоящую цену кадра.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if _quality >= 0:
		var q := get_node_or_null("/root/Quality")
		if q:
			q.call("set_level", _quality)


func _process(dt: float) -> void:
	_t += dt
	# облёт на высоте глаз через всю карту — худший случай: много геометрии в кадре
	var a := _t * 0.55
	_cam.global_position = Vector3(sin(a) * _span * 0.33, 1.7, cos(a) * _span * 0.33)
	_cam.look_at(Vector3(sin(a + 2.2) * _span * 0.2, 1.6, cos(a + 2.2) * _span * 0.2), Vector3.UP)
	if _t < _warmup:
		return  # прогрев: первые секунды идут шейдеры и стриминг, их не считаем
	_frames.append(dt)
	if _t >= _warmup + _seconds:
		_report()


func _report() -> void:
	_frames.sort()
	var n := _frames.size()
	var total := 0.0
	for f in _frames:
		total += f
	var avg_dt := total / maxf(1.0, float(n))
	# 1% low: худший процент кадров (самые долгие) — их и чувствует игрок
	var low_n := maxi(1, n / 100)
	var low_sum := 0.0
	for i in range(n - low_n, n):
		low_sum += _frames[i]
	var low_dt := low_sum / float(low_n)
	var out := {
		"scene": _scene_path,
		"quality": (get_node_or_null("/root/Quality").get("level") if get_node_or_null("/root/Quality") else -1),
		"frames": n,
		"fps_avg": snappedf(1.0 / maxf(0.0001, avg_dt), 0.1),
		"fps_1pct_low": snappedf(1.0 / maxf(0.0001, low_dt), 0.1),
		"frame_ms_avg": snappedf(avg_dt * 1000.0, 0.01),
		"frame_ms_worst": snappedf(_frames[n - 1] * 1000.0, 0.01),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
	}
	# Критерий — ВРЕМЯ КАДРА, а не FPS: правило 6 требует 60 FPS на СРЕДНЕЙ видеокарте, а
	# меряем мы на той, что есть. 60 FPS = 16.67 мс. Держим потолок 5.5 мс, то есть трёхкратный
	# запас на более слабое железо; это и есть страховка от регресса, которую можно проверить
	# на любой машине. Отдельно сторожим 1% low: 11 мс — уже заметный рывок.
	out["frame_budget_ms"] = 5.5
	out["headroom_x"] = snappedf(16.67 / maxf(0.01, float(out["frame_ms_avg"])), 0.1)
	out["pass"] = float(out["frame_ms_avg"]) <= 5.5 and (1000.0 / maxf(0.01, float(out["fps_1pct_low"]))) <= 11.0
	print(JSON.stringify(out))
	get_tree().quit(0 if out["pass"] else 1)
