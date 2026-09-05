# agent_eyes — «глаза агента»: открыть сцену, подождать N кадров, снять PNG на диск.
# Запуск (окно мигнёт — скриншоту нужен рендер, headless не умеет):
#   godot --path . res://tools/agent_eyes.tscn -- --scene=res://scenes/maps/duel.tscn --frames=90 --out=build/eyes.png
# Доп. флаги: --cam=over|eye (обзор сверху / с высоты глаз), --yaw=<град>
#
# Сцены карт своей камеры не содержат — без неё инструмент снимал ПУСТОЕ небо, и все
# «пруфы» выходили побайтово одинаковыми. Поэтому камеру ставим сами, кадрируя по
# размеру карты из меты map_meta.
extends Node

var _target_scene := ""
var _frames := 90
var _out := "build/eyes.png"
var _cam_mode := "over"
var _yaw := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_target_scene = arg.substr(8)
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--cam="):
			_cam_mode = arg.substr(6)
		elif arg.begins_with("--yaw="):
			_yaw = deg_to_rad(float(arg.substr(6)))
	if _target_scene != "":
		var packed: PackedScene = load(_target_scene)
		if packed == null:
			push_error("agent_eyes: сцена не загрузилась: " + _target_scene)
			get_tree().quit(1)
			return
		var inst := packed.instantiate()
		add_child(inst)
		_ensure_camera(inst)
	_snap()


func _ensure_camera(root: Node) -> void:
	if _find_camera(root) != null:
		return  # у сцены своя камера — не мешаем
	var w := 60.0
	var d := 60.0
	if root.has_meta("map_meta"):
		var meta = JSON.parse_string(String(root.get_meta("map_meta")))
		if meta is Dictionary:
			w = float(meta.get("size_w", w))
			d = float(meta.get("size_d", d))
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 600.0
	add_child(cam)
	cam.current = true
	var span := maxf(w, d)
	if _cam_mode == "eye":
		# с высоты глаз бойца от края карты — видно силуэт застройки
		cam.global_position = Vector3(sin(_yaw) * span * 0.42, 1.7, cos(_yaw) * span * 0.42)
		cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	else:
		# облёт сверху под углом — видно всю планировку и вертикаль
		cam.global_position = Vector3(sin(_yaw) * span * 0.55, span * 0.62, cos(_yaw) * span * 0.55)
		cam.look_at(Vector3.ZERO, Vector3.UP)
	print("agent_eyes: камера ", _cam_mode, " поставлена (карта %.0fx%.0f)" % [w, d])


func _find_camera(n: Node) -> Camera3D:
	if n is Camera3D:
		return n as Camera3D
	for c in n.get_children():
		var f := _find_camera(c)
		if f:
			return f
	return null


func _snap() -> void:
	for i in _frames:
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var abs_out := _out if _out.is_absolute_path() else ProjectSettings.globalize_path("res://" + _out)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var err := img.save_png(abs_out)
	print("agent_eyes: ", "OK " + abs_out if err == OK else "FAIL err=" + str(err))
	get_tree().quit(0 if err == OK else 1)
