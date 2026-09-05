# Сторож обзора: движение мыши должно доходить до игрока и поворачивать камеру.
#
# Событие гоняем через ВЕСЬ путь ввода (push_input), а не вызываем обработчик напрямую —
# иначе тест не поймает главную беду: элемент HUD с mouse_filter = STOP перехватывает
# движение мыши раньше игрока, и камера перестаёт вращаться. Прицел ChV/ChH — это
# ColorRect ровно в центре экрана, где и живёт захваченный курсор.
extends GutTest


func _spawn() -> FpsPlayer:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	return p


func test_hud_controls_do_not_eat_mouse() -> void:
	var p := _spawn()
	await wait_frames(2)
	var hud := p.get_node("HUD") as CanvasLayer
	for c in hud.get_children():
		if c is Control:
			var ctl := c as Control
			if not ctl.visible:
				continue
			assert_eq(ctl.mouse_filter, Control.MOUSE_FILTER_IGNORE,
				"%s не должен перехватывать мышь (иначе камера не вращается)" % ctl.name)


# В headless курсор захватить нельзя (mouse_mode остаётся VISIBLE), а игрок обрабатывает
# обзор только при захвате — поэтому такой прогон ничего не проверяет и тест пропускается.
# Гонять его надо С ОКНОМ:
#   godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_look.gd -gexit
func _needs_window() -> bool:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		pass_test("headless: захват мыши недоступен, обзор проверяется оконным прогоном")
		return true
	return false


func test_mouse_motion_turns_camera() -> void:
	var p := _spawn()
	await wait_frames(2)
	if _needs_window():
		return
	var yaw0 := p.yaw
	var pitch0 := p.pitch
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(120, 60)
	# в центр экрана — туда, где при захвате мыши находится курсор и висит прицел
	ev.position = get_viewport().get_visible_rect().size * 0.5
	get_viewport().push_input(ev)
	await wait_frames(2)
	assert_ne(p.yaw, yaw0, "мышь по X должна поворачивать камеру")
	assert_ne(p.pitch, pitch0, "мышь по Y должна наклонять камеру")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_pitch_is_clamped() -> void:
	var p := _spawn()
	await wait_frames(2)
	if _needs_window():
		return
	for i in 40:
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(0, -400)
		ev.position = get_viewport().get_visible_rect().size * 0.5
		get_viewport().push_input(ev)
	await wait_frames(2)
	assert_lt(p.pitch, 1.56, "взгляд не заворачивается за макушку")
	assert_gt(p.pitch, -1.56, "и за пятки тоже")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
