# agent_eyes — «глаза агента»: открыть сцену, подождать N кадров, снять PNG на диск.
# Запуск (окно мигнёт — скриншоту нужен рендер, headless не умеет):
#   godot --path . res://tools/agent_eyes.tscn -- --scene=res://scenes/maps/range.tscn --frames=90 --out=build/eyes.png
extends Node

var _target_scene := ""
var _frames := 90
var _out := "build/eyes.png"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_target_scene = arg.substr(8)
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
	if _target_scene != "":
		var packed: PackedScene = load(_target_scene)
		if packed == null:
			push_error("agent_eyes: сцена не загрузилась: " + _target_scene)
			get_tree().quit(1)
			return
		add_child(packed.instantiate())
	_snap()


func _snap() -> void:
	for i in _frames:
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var abs_out := _out if _out.is_absolute_path() else ProjectSettings.globalize_path("res://" + _out)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var err := img.save_png(abs_out)
	print("agent_eyes: ", "OK " + abs_out if err == OK else "FAIL err=" + str(err))
	get_tree().quit(0 if err == OK else 1)
