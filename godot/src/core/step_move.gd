# Общее движение с автоподъёмом на ступени (web resolveAxis:265).
# CharacterBody3D сам не переступает боксы: упёрлись в стенку на полу — пробуем тот же
# ход, приподняв тело на STEP_UP; если наверху просвет, переносим и доезжаем.
# Один код для игрока и бота: навмеш печётся с agent_max_climb = STEP_UP, значит и тело
# обязано уметь ровно столько же — иначе путь обещает подъём, который тело не осилит.
class_name StepMove


static func slide(body: CharacterBody3D) -> void:
	var step_up := float(Balance.MOVE["STEP_UP"])
	var pre := body.global_position
	var pre_vel := body.velocity
	body.move_and_slide()
	if not body.is_on_wall() or not body.is_on_floor():
		return
	var flat := Vector3(pre_vel.x, 0.0, pre_vel.z)
	if flat.length() < 0.5:
		return
	var probe := pre + Vector3(0, step_up + 0.02, 0)
	var motion := flat * body.get_physics_process_delta_time()
	if not body.test_move(Transform3D(body.global_transform.basis, probe), motion):
		body.global_position = probe + motion
		body.velocity = pre_vel
		body.move_and_slide()  # доехать и приземлиться на ступень
