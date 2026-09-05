# Игрок: движение и камера — паритет 1:1 с web player.js (числа из Balance.MOVE).
# Косметика ощущений (боб/дип/крен) портирована из applyCamera веба — это фил, не баланс.
class_name FpsPlayer
extends CharacterBody3D

const BASE_FOV := 74.0  # web main.js:204

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera3D
@onready var col: CollisionShape3D = $Col
@onready var step_sfx: AudioStreamPlayer3D = $StepSfx

var yaw := 0.0
var pitch := 0.0
var punch_yaw := 0.0    # панч отдачи (weapon.gd пишет сюда)
var punch_pitch := 0.0
var aim_t := 0.0        # 0..1 прицеливание (weapon.gd)
var char_id := "max"    # агент (срез G3 — Макс; выбор агента — фаза G4-лобби)
var weapon_speed := 1.0 # множитель скорости от оружия (weapon_feel)
var speed_factor := 1.0 # прочие эффекты (бусты/слоу) — пока 1.0

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
# матч-поля (экономика/статы — считает Match)
var credits := 0
var kills := 0
var deaths := 0
var ult := 0
var dead := false
# статусы от способностей
var blind_until := 0.0    # вспышки (белый экран — HUD)
var stun_until := 0.0     # стан (движение заморожено)
var boost_until := 0.0    # Порыв Макса (+40%)
var levit_until := 0.0    # «Невесомость» Геры (слоу ×0.35)
var slow_until := 0.0     # зоны (кислота/подкова/криспи) и сигналка Санька
var slow_mul := 1.0
var banquet_until := 0.0  # «Финальный банкет» Иры (+15% скорость)
var gallop_until := 0.0   # «Галоп» Конилия (+50%)
var _kon_ramp := 0.0      # пассивка Конилия «Разгон»
var _kon_yaw := INF


func apply_slow(mul: float, dur: float) -> void:
	slow_mul = mul
	slow_until = Time.get_ticks_msec() / 1000.0 + dur
var last_kill_t := -99.0  # «накормленность» Кровопира Дениса (окно 6с)
var last_dmg_t := -99.0   # пассивка Дениса: реген только вне боя
# принудительное движение (кокон Дениса / воронка Геры / грэпл Геры)
var forced_to := Vector3.INF
var forced_until := 0.0
var forced_speed := 0.0


func force_pull(to: Vector3, dur: float, speed: float) -> void:
	forced_to = to
	forced_until = Time.get_ticks_msec() / 1000.0 + dur
	forced_speed = speed
var ult_mark_until := 0.0 # Второе дыхание Артемия
var ult_mark_pos := Vector3.INF

signal blinded(dur: float)


func apply_blind(dur: float) -> void:
	blind_until = Time.get_ticks_msec() / 1000.0 + dur
	blinded.emit(dur)


func apply_stun(dur: float) -> void:
	stun_until = Time.get_ticks_msec() / 1000.0 + dur


# Второе дыхание: если метка активна — вместо смерти возврат на неё с полным HP
func try_second_wind() -> bool:
	if Time.get_ticks_msec() / 1000.0 >= ult_mark_until or ult_mark_pos == Vector3.INF:
		return false
	ult_mark_until = 0.0
	hp = int(Balance.RULES["BASE_HP"])
	hp_changed.emit(hp)
	if NetHub.online() and multiplayer.is_server() and get_multiplayer_authority() != 1:
		var n := NetHub.node()
		if n:
			n.rpc_id(get_multiplayer_authority(), "teleport_self", ult_mark_pos)
	else:
		global_position = ult_mark_pos
		velocity = Vector3.ZERO
	return true

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
	get_node("/root/Ears").call("register", step_sfx, "Steps", self)  # окклюзия шагов
	var remote := NetHub.online() and not is_multiplayer_authority()
	var body := get_node_or_null("BodyVis") as Node3D
	_remote_audio = remote
	if remote:
		# чужой игрок: без ввода/камеры/HUD, но с видимым телом
		set_physics_process(false)
		set_process(true)  # но шаги ведём от реплицированной позиции (иначе враг беззвучен)
		_last_remote_pos = global_position
		cam.current = false
		($HUD as CanvasLayer).visible = false
		($WeaponRig as Node).set_physics_process(false)
		if body:
			body.visible = true
	else:
		if body:
			body.visible = false  # своё тело от первого лица не видно
		cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# урон применяет хост (Net.report_hit) или напрямую в офлайне — паритет веб-модели
func take_hit(dmg: int, part: String, attacker: Node = null, weapon := "") -> void:
	if hp <= 0:
		return
	hp -= dmg
	last_dmg_t = Time.get_ticks_msec() / 1000.0
	hp_changed.emit(hp)
	if hp <= 0:
		if try_second_wind():
			return  # ульта Артемия: вместо смерти — возврат на метку
		died.emit()
		var mt := Match.find(get_tree())
		if mt and mt.phase != Match.Phase.WAIT:
			# в матче смерть до конца раунда
			mt.on_death(self, attacker, weapon, part == "head")
			dead = true
			visible = false
			set_collision_layer_value(1, false)
		else:
			# тренировка/полигон: авто-респавн
			var tw := create_tween()
			tw.tween_interval(2.0)
			tw.tween_callback(func() -> void:
				global_position = _spawn_pos
				velocity = Vector3.ZERO
				hp = int(Balance.RULES["BASE_HP"])
				hp_changed.emit(hp))


func round_reset() -> void:
	hp = int(Balance.RULES["BASE_HP"])
	dead = false
	visible = true
	set_collision_layer_value(1, true)
	velocity = Vector3.ZERO
	hp_changed.emit(hp)


func give_weapon(id: String) -> void:
	($WeaponRig as WeaponRig).give_weapon(id)


var _shape_part := {}


func part_at(shape_idx: int) -> String:
	if _shape_part.is_empty():
		var idx := 0
		for c in get_children():
			if c is CollisionShape3D:
				_shape_part[idx] = String(c.name).to_lower()
				idx += 1
	var nm: String = _shape_part.get(shape_idx, "body")
	if nm.contains("head"):
		return "head"
	if nm.contains("leg"):
		return "leg"
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
	s *= float(Balance.CHARACTERS.get(char_id, {}).get("speedMul", 1.0))  # пассивка перса (Макс 1.05)
	s *= weapon_speed * speed_factor
	var tt := Time.get_ticks_msec() / 1000.0
	if tt < boost_until:
		s *= float(Balance.ABILITY["BOOST_MUL"])  # Порыв Макса
	if tt < levit_until:
		s *= float(Balance.ABILITY["GERA_ULT_SLOW"])  # «Невесомость» Геры — всплыл, вязнет
	if tt < slow_until:
		s *= slow_mul  # кислота/подкова/криспи/сигналка
	if tt < banquet_until:
		s *= float(Balance.ABILITY["BANQUET_SPEED"])  # Финальный банкет Иры
	if tt < gallop_until:
		s *= float(Balance.ABILITY["GALLOP_MUL"])  # Галоп Конилия
	if _kon_ramp >= 2.0:
		s *= 1.12  # пассивка Конилия «Разгон»: 2с бега прямо без стрельбы
	s *= (1.0 - aim_t * 0.42)  # прицеливание замедляет (web player.js:151)
	return s


func _physics_process(dt: float) -> void:
	if dead:
		return
	var mt := Match.find(get_tree())
	var now_s := Time.get_ticks_msec() / 1000.0
	# принудительная тяга (кокон/воронка/грэпл): движение переопределено, полный 3D (грэпл — вверх на насесты)
	if now_s < forced_until and forced_to != Vector3.INF:
		var d := forced_to - global_position
		if d.length() > 0.4:
			velocity = d.normalized() * forced_speed
		else:
			velocity = Vector3.ZERO
			forced_until = 0.0
		move_and_slide()
		_apply_camera(dt)
		return
	var frozen := (mt != null and mt.phase == Match.Phase.BUY) or now_s < stun_until  # закупка/стан: смотреть можно, ходить нельзя
	var m: Dictionary = Balance.MOVE
	crouch = Input.is_action_pressed("crouch")
	walk = Input.is_action_pressed("walk")
	if mt:
		_spike_input(mt, dt)
	if frozen:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_camera(dt)
		return

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
	elif jump_edge and not is_on_floor() and char_id == "max" and _air_jumps > 0:
		velocity.y = float(m["JUMP_VEL"])  # твист Макса: двойной прыжок
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

	# пассивка Конилия «Разгон»: бег прямо ≥2с без стрельбы/поворота → +12% (сброс поворотом/выстрелом)
	if char_id == "koniliy":
		var h_sp := Vector2(velocity.x, velocity.z).length()
		var dyaw := absf(wrapf(yaw - (_kon_yaw if _kon_yaw != INF else yaw), -PI, PI))
		_kon_yaw = yaw
		var rig := get_node_or_null("WeaponRig") as WeaponRig
		var shot_recent := rig != null and (Time.get_ticks_msec() / 1000.0 - rig.last_shot) < 0.5
		_kon_ramp = (_kon_ramp + dt) if (is_on_floor() and h_sp > 3.5 and dyaw < 0.06 and not shot_recent) else 0.0

	_footsteps(dt)
	_apply_camera(dt)


# авто-подъём на ступени до STEP_UP (web resolveAxis:265) — общий код с ботом (StepMove)
func _move_with_step_up(_dt: float) -> void:
	StepMove.move(self)


var _remote_audio := false
var _last_remote_pos := Vector3.ZERO


func _process(delta: float) -> void:
	# только для чужих игроков: шаги от дельты реплицированной позиции (физика у них выключена)
	if not _remote_audio or delta <= 0.0:
		return
	var d := Vector2(global_position.x - _last_remote_pos.x, global_position.z - _last_remote_pos.z)
	_last_remote_pos = global_position
	var h_speed := d.length() / delta
	if h_speed <= 3.0 or char_id == "max":  # медленно/крадётся/«Ветер» Макса — тихо
		return
	_step_dist += d.length()
	if _step_dist > 2.7:
		_step_dist = 0.0
		_play_step(0.55)


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
		var silent := char_id == "max"  # пассивка Макса «Ветер»: бесшумный бег (тише + боты не слышат)
		_play_step(0.22 if silent else 0.55)
		if not silent:
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


# ===== шип: плант (4, в сайте) и дефуз (F, у шипа) =====
func in_site() -> bool:
	for s in get_tree().get_nodes_in_group("site"):
		if (s as Area3D).overlaps_body(self):
			return true
	return false


func _spike_input(mt: Match, dt: float) -> void:
	var plant_hold := Input.is_action_pressed("plant")
	var defuse_hold := Input.is_action_pressed("defuse")
	if NetHub.online() and not multiplayer.is_server():
		# клиент шлёт намерение хосту (авторитет-паритет); шлём только когда есть смысл
		if plant_hold or defuse_hold:
			var n := NetHub.node()
			if n:
				n.rpc_id(1, "spike_input", plant_hold, in_site(), defuse_hold)
		return
	mt.try_plant(self, in_site(), plant_hold, dt)
	mt.try_defuse(self, defuse_hold, dt)


# направление выстрела с учётом панча — пули летят туда, куда реально смотрит камера
func aim_dir() -> Vector3:
	var cy := yaw + punch_yaw
	var cp := pitch + punch_pitch
	return Vector3(-sin(cy) * cos(cp), sin(cp), -cos(cy) * cos(cp))


func eye_pos() -> Vector3:
	return global_position + Vector3(0.0, height - float(Balance.MOVE["EYE"]), 0.0)
