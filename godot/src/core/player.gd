# Игрок: движение и камера — паритет 1:1 с web player.js (числа из Balance.MOVE).
# Косметика ощущений (боб/дип/крен) портирована из applyCamera веба — это фил, не баланс.
class_name FpsPlayer
extends CharacterBody3D

const BASE_FOV := 74.0  # web main.js:204

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera3D
@onready var col: CollisionShape3D = $Col
@onready var step_sfx: AudioStreamPlayer = $StepSfx

var yaw := 0.0
var pitch := 0.0
var punch_yaw := 0.0    # панч отдачи (weapon.gd пишет сюда)
var punch_pitch := 0.0
var aim_t := 0.0        # 0..1 прицеливание (weapon.gd)
var speed_factor := 1.0 # множители скорости персонажа/эффектов (в G1 — 1.0)

var crouch := false
var walk := false
var height := 1.8
var _air_jumps := 1
var _land_bob := 0.0
var _cam_dip := 0.0
var _bob_phase := 0.0
var _roll_z := 0.0
var _step_dist := 0.0
var _steps: Array[AudioStream] = []
var mouse_sens := 0.0022
var hp := 100
var team := "A"
var _spawn_pos := Vector3.ZERO

signal made_noise  # шаг на бегу — для событийного слуха ботов
signal hp_changed(hp: int)
signal died


func _ready() -> void:
	height = float(Balance.MOVE["HEIGHT"])
	hp = int(Balance.RULES["BASE_HP"])
	_spawn_pos = global_position
	add_to_group("combatants")
	add_to_group("noise_makers")
	for i in range(1, 7):
		_steps.append(load("res://assets/audio/step%d.ogg" % i))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# бот стреляет вероятностно (паритет веб-модели) — просто наносит урон
func take_hit(dmg: int, _part: String) -> void:
	if hp <= 0:
		return
	hp -= dmg
	hp_changed.emit(hp)
	if hp <= 0:
		died.emit()
		# минимальный респавн для полигона/среза (раундовая смерть — фаза G5)
		var tw := create_tween()
		tw.tween_interval(2.0)
		tw.tween_callback(func() -> void:
			global_position = _spawn_pos
			velocity = Vector3.ZERO
			hp = int(Balance.RULES["BASE_HP"])
			hp_changed.emit(hp))


func part_at(_shape_idx: int) -> String:
	return "body"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens := mouse_sens * (1.0 - aim_t * 0.45)  # в прицеле медленнее (паритет ADS)
		yaw -= mm.relative.x * sens
		pitch = clampf(pitch - mm.relative.y * sens, -1.55, 1.55)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func max_speed() -> float:
	var m: Dictionary = Balance.MOVE
	var s := float(m["CROUCH_SPEED"]) if crouch else (float(m["WALK_SPEED"]) if walk else float(m["RUN_SPEED"]))
	s *= speed_factor
	s *= (1.0 - aim_t * 0.42)  # прицеливание замедляет (web player.js:151)
	return s


func _physics_process(dt: float) -> void:
	var m: Dictionary = Balance.MOVE
	crouch = Input.is_action_pressed("crouch")
	walk = Input.is_action_pressed("walk")

	# плавная высота капсулы (присед)
	var target_h := float(m["CROUCH_HEIGHT"]) if crouch else float(m["HEIGHT"])
	height += (target_h - height) * minf(1.0, dt * 12.0)
	var shape := col.shape as CapsuleShape3D
	shape.height = height
	col.position.y = height * 0.5

	# желаемое направление (WASD в системе взгляда)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)).normalized() if input.length_squared() > 0.0 else Vector3.ZERO

	# экспоненциальный разгон как в вебе: vel += (target-vel)*min(1, accel*dt)
	var accel := float(m["ACCEL"]) if is_on_floor() else float(m["AIR_ACCEL"])
	var target_v := wish * max_speed()
	var k := minf(1.0, accel * dt)
	velocity.x += (target_v.x - velocity.x) * k
	velocity.z += (target_v.z - velocity.z) * k

	# прыжок + двойной прыжок Макса (в G1 персонаж один — Макс, для среза G3)
	var jump_edge := Input.is_action_just_pressed("jump")
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = float(m["JUMP_VEL"])
	elif jump_edge and not is_on_floor() and _air_jumps > 0:
		velocity.y = float(m["JUMP_VEL"])
		_air_jumps -= 1

	var was_air := not is_on_floor()
	var fell := maxf(0.0, -velocity.y)
	velocity.y -= float(m["GRAVITY"]) * dt

	_move_with_step_up(dt)

	if is_on_floor():
		_air_jumps = 1
		if was_air:  # приземление: дип по силе падения (web moveCollide:229)
			_land_bob = minf(0.3, 0.05 + fell * 0.022)
			_cam_dip = maxf(_cam_dip, _land_bob)
			_play_step(minf(1.0, 0.5 + fell * 0.05))

	_footsteps(dt)
	_apply_camera(dt)


# авто-подъём на ступени до STEP_UP (web resolveAxis:265) — CharacterBody3D сам не умеет боксы
func _move_with_step_up(_dt: float) -> void:
	var step_up := float(Balance.MOVE["STEP_UP"])
	var pre := global_position
	var pre_vel := velocity
	move_and_slide()
	if not is_on_wall() or not is_on_floor():
		return
	var flat := Vector3(pre_vel.x, 0.0, pre_vel.z)
	if flat.length() < 0.5:
		return
	# упёрлись в стенку: пробуем тот же ход с подъёмом на step_up (если есть просвет)
	var probe := pre + Vector3(0, step_up + 0.02, 0)
	var motion := flat * get_physics_process_delta_time()
	if not test_move(Transform3D(global_transform.basis, probe), motion):
		global_position = probe + motion
		velocity = pre_vel
		move_and_slide()  # доехать и приземлиться на ступень


func _footsteps(dt: float) -> void:
	# шаги слышны ТОЛЬКО при беге; Shift/присед бесшумны (правило звука)
	if not is_on_floor() or walk or crouch:
		return
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if h_speed <= 3.0:
		return
	_step_dist += h_speed * dt
	if _step_dist > 2.7:
		_step_dist = 0.0
		_play_step(0.55)
		made_noise.emit()


func _play_step(vol: float) -> void:
	step_sfx.stream = _steps[randi() % _steps.size()]
	step_sfx.volume_db = linear_to_db(clampf(vol, 0.05, 1.0))
	step_sfx.pitch_scale = 0.9 + randf() * 0.2
	step_sfx.play()


func _apply_camera(dt: float) -> void:
	# панч пружиной в ноль (web applyCamera:289)
	var rec := exp(-dt * 9.0)
	punch_pitch *= rec
	punch_yaw *= rec
	_land_bob = maxf(0.0, _land_bob - dt * 0.9)
	_cam_dip += (0.0 - _cam_dip) * minf(1.0, dt * 8.0)

	var h_speed := Vector2(velocity.x, velocity.z).length()
	var speed_k := minf(1.0, h_speed / float(Balance.MOVE["RUN_SPEED"]))

	var moving := is_on_floor() and h_speed > 0.6
	if moving:
		_bob_phase += dt * (6.2 + speed_k * 4.2)
	var bob_scale := (speed_k if moving else 0.0) * (0.5 if crouch else 1.0) * (0.55 if walk else 1.0) * (1.0 - aim_t * 0.75)
	var bob_y := absf(sin(_bob_phase)) * 0.05 * bob_scale
	var bob_side := sin(_bob_phase) * 0.035 * bob_scale
	var idle := sin(Time.get_ticks_msec() / 1000.0 * 1.8) * 0.006 if (not moving and is_on_floor()) else 0.0

	# крен на стрейфе
	var strafe := Input.get_axis("move_left", "move_right")
	var roll_target := (-strafe * 0.022 * speed_k + sin(_bob_phase) * 0.006 * bob_scale) * (1.0 - aim_t * 0.7)
	_roll_z += (roll_target - _roll_z) * minf(1.0, dt * 7.0)

	var eye := height - float(Balance.MOVE["EYE"])
	head.position = Vector3(bob_side, eye - _land_bob - _cam_dip + bob_y + idle, 0.0)
	rotation.y = yaw + punch_yaw
	head.rotation.x = pitch + punch_pitch
	head.rotation.z = _roll_z


# направление выстрела с учётом панча — пули летят туда, куда реально смотрит камера
func aim_dir() -> Vector3:
	var cy := yaw + punch_yaw
	var cp := pitch + punch_pitch
	return Vector3(-sin(cy) * cos(cp), sin(cp), -cos(cy) * cos(cp))


func eye_pos() -> Vector3:
	return global_position + Vector3(0.0, height - float(Balance.MOVE["EYE"]), 0.0)
