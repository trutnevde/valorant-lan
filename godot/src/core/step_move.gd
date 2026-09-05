# Авто-подъём на ступени до MOVE.STEP_UP — CharacterBody3D сам на боксы не шагает
# (паритет web resolveAxis: тот же приём с пробой просвета над препятствием).
#
# ОБЩИЙ код игрока и бота. Раньше он жил только в player.gd, а бот двигался голым
# move_and_slide() — и физически не мог подняться ни по одной лестнице. На плоской
# «Дуэли» это не проявлялось, на «Высоте» с пятью лестницами боты вставали в риск
# первой же ступени. Держим одну реализацию, чтобы расхождение не повторилось.
class_name StepMove


static func move(body: CharacterBody3D) -> void:
	var step_up := float(Balance.MOVE["STEP_UP"])
	var pre := body.global_position
	var pre_vel := body.velocity
	body.move_and_slide()
	if not body.is_on_wall() or not body.is_on_floor():
		return
	var flat := Vector3(pre_vel.x, 0.0, pre_vel.z)
	if flat.length() < 0.5:
		return
	# упёрлись в стенку: тот же ход, но с подъёмом на step_up — если там просвет
	var probe := pre + Vector3(0, step_up + 0.02, 0)
	var motion := flat * body.get_physics_process_delta_time()
	if not body.test_move(Transform3D(body.global_transform.basis, probe), motion):
		body.global_position = probe + motion
		body.velocity = pre_vel
		body.move_and_slide()  # доехать и приземлиться на ступень
