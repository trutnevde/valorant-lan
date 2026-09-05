# Бот v1: NavigationAgent3D + стейты patrol/engage. Паритет веб-модели (server.js):
# AI-тик 20 Гц как веб-сервер; зрение конус ±70° (dot 0.34, ближе 4.5м — периферия) + LOS;
# слух — событийная модель (сигнал made_noise); стрельба вероятностная по пресету
# Balance.BOT_PRESETS (реакция/доворот/pHit/хедшоты); unstuck-watchdog 2с → перепрокладка.
class_name Bot
extends CharacterBody3D

# скорости бота из web server.js moveToward (combat 3.6 / спокойно 5.5) — поведение, не баланс
const SPEED_CALM := 5.5
const SPEED_COMBAT := 3.6
const VISION_DIST := 44.0
const FOV_DOT := 0.34
const AI_TICK := 0.05  # 20 Гц как веб-сервер

@onready var agent: NavigationAgent3D = $NavAgent
@onready var shot_sfx: AudioStreamPlayer3D = $ShotSfx
@onready var step_sfx: AudioStreamPlayer3D = $StepSfx

var _steps: Array = []
var _step_dist := 0.0

var team := "B"
var preset := "medium"
var weapon_id := "vandal"
var hp := 100
var rng := RandomNumberGenerator.new()
# матч-поля (экономика/статы — считает Match)
var credits := 0
var kills := 0
var deaths := 0
var ult := 0
var char_id := "sanek"
var _bought := false
var blind_until := 0.0  # ослеплён вспышкой — не видит
var stun_until := 0.0   # оглушён — стоит
var levit_until := 0.0  # «Невесомость» Геры: слоу + мажет
var slow_until := 0.0   # зоны/сигналка
var slow_mul := 1.0
var last_kill_t := -99.0
var last_dmg_t := -99.0


func apply_slow(mul: float, dur: float) -> void:
	slow_mul = mul
	slow_until = _now() + dur

var target: Node3D = null
var engaging_until := -99.0
var react_at := 0.0
var next_shot := 0.0
var heard_pos := Vector3.INF
var heard_until := -99.0
var _ai_acc := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _spawn_pos := Vector3.ZERO

# телеметрия (ботматч читает)
var stat_shots := 0
var stat_hits := 0
var stat_kills := 0
var stat_deaths := 0
var stat_stuck_events := 0

signal made_noise


func _ready() -> void:
	rng.randomize()
	add_to_group("combatants")
	add_to_group("noise_makers")
	for i in range(1, 7):
		_steps.append(load("res://assets/audio/step%d.ogg" % i))
	var ears := get_node_or_null("/root/Ears")
	if ears:
		ears.call("register", shot_sfx, "SFX", self)
		ears.call("register", step_sfx, "Steps", self)
	if NetHub.online() and not multiplayer.is_server():
		set_physics_process(false)  # AI ботов гоняет только хост; клиенты видят синк
	hp = int(Balance.RULES["BASE_HP"])
	_spawn_pos = global_position
	_last_pos = global_position
	agent.radius = float(Balance.MOVE["RADIUS"])
	agent.path_desired_distance = 0.8
	agent.target_desired_distance = 1.1
	# RVO-избегание: боты не пинят друг друга в чоках (система движка, а не самопал)
	agent.avoidance_enabled = true
	agent.max_speed = SPEED_CALM
	agent.velocity_computed.connect(_on_safe_velocity)
	# слух: подписка на шаги/выстрелы всех шумящих
	for n in get_tree().get_nodes_in_group("noise_makers"):
		if n != self and n.has_signal("made_noise"):
			n.made_noise.connect(_on_noise.bind(n))


func cfg() -> Dictionary:
	return Balance.BOT_PRESETS[preset]


func _on_noise(src: Node3D) -> void:
	if not is_instance_valid(src) or src.get("team") == team:
		return
	var d := global_position.distance_to(src.global_position)
	if d < 28.0 * float(cfg()["hearMul"]):
		heard_pos = src.global_position
		heard_until = _now() + 1.6


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(dt: float) -> void:
	if hp <= 0:
		return
	if _now() < stun_until:
		return  # оглушён — стоит (лопнувший клон Фафика и т.п.)
	var mt := Match.find(get_tree())
	if mt and mt.phase == Match.Phase.BUY:
		# ЗАМОРОЗКА на закупке — паритет web server.js tickBot (движения нет, watchdog молчит)
		_ai_acc += dt
		if _ai_acc >= AI_TICK:
			_ai_acc = 0.0
			_think()  # внутри — только покупка
		_stuck_t = 0.0
		_last_pos = global_position
		return
	_ai_acc += dt
	if _ai_acc >= AI_TICK:
		_ai_acc = 0.0
		_think()
	_move(dt)
	_watchdog(dt)


func _think() -> void:
	var t := _now()
	var mt := Match.find(get_tree())
	if mt and mt.phase == Match.Phase.BUY:
		# закупка: стоим; раз за раунд покупаем лучшее по карману (web-упрощение)
		if not _bought:
			_bought = true
			for cand in ["vandal", "spectre", "stinger"]:
				if mt.try_buy(self, cand):
					break
		return
	var seen := _visible_enemy()
	if seen != null:
		if target != seen or t >= engaging_until:
			# новая цель — задержка реакции по пресету (окно на фланг, паритет веба)
			react_at = t + float(cfg()["react"]) + rng.randf() * float(cfg()["reactJit"])
		target = seen
		engaging_until = t + 1.4
	var combat := t < engaging_until and target != null and is_instance_valid(target)
	_use_ability(t, combat)
	if combat:
		_aim_and_shoot(t)
		return
	# цели матча: плант/дефуз/оборона — важнее слуха и патруля
	if mt and _objective(mt, t):
		return
	if heard_until > t and heard_pos != Vector3.INF:
		agent.target_position = heard_pos
	elif agent.is_navigation_finished():
		_pick_patrol_point()


# ===== цель раунда (G7): атака несёт шип и плантит; защита держит сайты и дефузит =====
var ai_site := ""
var _hold_spot := Vector3.INF
var _guard_ang := -1.0  # персональный угол охраны шипа (случайный — без коллизий точек)


func _objective(mt: Match, _t: float) -> bool:
	var meta := _map_meta()
	if meta.is_empty():
		return false
	var attacker := team == mt.attack_team
	if mt.phase == Match.Phase.LIVE:
		if attacker:
			var carrier := mt.spike_carrier
			if carrier == self:
				# несу шип → на сайт → плант (стоя в сайте держу «4»)
				var site_pos := _site_pos(meta, _my_site(mt))
				var d := Vector2(global_position.x - site_pos.x, global_position.z - site_pos.z).length()
				if d < 5.0:
					agent.target_position = global_position  # стоим — путь чистим (watchdog молчит)
					mt.try_plant(self, true, true, AI_TICK)
					return true
				agent.target_position = site_pos
				return true
			elif carrier != null and is_instance_valid(carrier) and int(carrier.get("hp")) > 0:
				# эскорт: СТАБИЛЬНАЯ точка у сайта (рандом каждый тик дёргал навигацию → стаки)
				if _hold_spot == Vector3.INF:
					var ang0 := rng.randf() * TAU
					_hold_spot = _snap_nav(_site_pos(meta, _my_site(mt)) + Vector3(cos(ang0) * 3.0, 0, sin(ang0) * 3.0))
				if Vector2(global_position.x - _hold_spot.x, global_position.z - _hold_spot.z).length() > 1.2:
					agent.target_position = _hold_spot
				else:
					agent.target_position = global_position
					rotation.y += 0.03
				return true
			return false
		else:
			# оборона: распределяемся по холд-спотам сайтов (не кучкуемся)
			if _hold_spot == Vector3.INF:
				var site := "A" if (get_instance_id() % 2 == 0) else "B"
				var base := _site_pos(meta, site)
				var ang := rng.randf() * TAU
				_hold_spot = _snap_nav(base + Vector3(cos(ang) * 3.5, 0, sin(ang) * 3.5))
			if Vector2(global_position.x - _hold_spot.x, global_position.z - _hold_spot.z).length() > 1.2:
				agent.target_position = _hold_spot
			else:
				agent.target_position = global_position  # на месте — путь чистим
				rotation.y += 0.03  # держим позицию, сканируем
			return true
	elif mt.phase == Match.Phase.PLANTED:
		var spike := mt.spike_planted_at
		if spike == Vector3.INF:
			return false
		if attacker:
			# охраняем шип: персональная точка по кругу; дошли — стоим
			if _guard_ang < 0.0:
				_guard_ang = rng.randf() * TAU
			var guard := _snap_nav(spike + Vector3(cos(_guard_ang) * 4.0, 0, sin(_guard_ang) * 4.0))
			if Vector2(global_position.x - guard.x, global_position.z - guard.z).length() > 1.2:
				agent.target_position = guard
			else:
				agent.target_position = global_position
				rotation.y += 0.03
			return true
		else:
			# дефуз: личная точка на мини-кольце у шипа (не толпимся в одну), у шипа держим «F»
			if _guard_ang < 0.0:
				_guard_ang = rng.randf() * TAU
			var dspot := _snap_nav(spike + Vector3(cos(_guard_ang) * 1.1, 0, sin(_guard_ang) * 1.1))
			var d2 := Vector2(global_position.x - spike.x, global_position.z - spike.z).length()
			if d2 < 1.6:
				agent.target_position = global_position
				mt.try_defuse(self, true, AI_TICK)
				return true
			agent.target_position = dspot
			return true
	return false


func _my_site(mt: Match) -> String:
	if ai_site == "":
		# сайт выбирает носитель шипа (детерминированно от раунда), остальные атакеры следуют
		ai_site = "A" if (mt.round_no % 2 == 0) else "B"
	return ai_site


func _map_meta() -> Dictionary:
	var map_root := get_tree().current_scene
	if map_root == null:
		return {}
	var raw: String = map_root.get_meta("map_meta", "{}")
	if raw == "{}":
		# карта может быть вложена (lan_game/slice инстансят duel внутрь)
		for c in map_root.get_children():
			if c.has_meta("map_meta"):
				raw = c.get_meta("map_meta")
				break
	var parsed = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


func _site_pos(meta: Dictionary, site: String) -> Vector3:
	var key := "site_a" if site == "A" else "site_b"
	var arr: Array = meta.get(key, [0, 0])
	return Vector3(float(arr[0]), 0, float(arr[1]))


# снап точки к навмешу: спот никогда не окажется в ящике/стене (NavigationServer, не самопал)
func _snap_nav(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), p)


# ===== скиллы по простым правилам (G7), кулдаун × abilityMul пресета =====
var _next_ability := 0.0


func _use_ability(t: float, combat: bool) -> void:
	if t < _next_ability:
		return
	var fx := get_node("/root/Fx")
	var cd_mul := float(cfg()["abilityMul"])
	var cd := func(s: float) -> void: _next_ability = t + s * cd_mul
	match char_id:
		"artemiy", "vova", "fafik", "koniliy":
			if combat and target != null and is_instance_valid(target):
				if char_id == "koniliy":
					fx.call("cast", "generic", {
						"logic": "res://src/agents/effects/util_zone.gd", "shape": "circle",
						"x": target.global_position.x, "z": target.global_position.z,
						"r": float(Balance.ABILITY["HORSESHOE_R"]), "dur": float(Balance.ABILITY["HORSESHOE_TIME"]),
						"dps": float(Balance.ABILITY["HORSESHOE_DPS"]), "slow": float(Balance.ABILITY["HORSESHOE_SLOW"]),
						"weapon": "horseshoe", "team": team, "owner_path": String(get_path()),
					})
					cd.call(8.0)
				else:
					var to := (target.global_position + Vector3(0, 1.4, 0)) - (global_position + Vector3(0, 1.6, 0))
					var dir := to.normalized()
					fx.call("cast", "flash", {
						"fx": global_position.x, "fy": global_position.y + 1.6, "fz": global_position.z,
						"dx": dir.x, "dy": dir.y, "dz": dir.z, "owner_path": String(get_path()),
					})
					cd.call(9.0)
			elif char_id == "vova" and not combat:
				# смок на подходе (веб-правило: дым без боя)
				var fwd := -global_transform.basis.z
				fx.call("cast", "smoke", {
					"x": global_position.x + fwd.x * 6.0, "z": global_position.z + fwd.z * 6.0,
					"team": team, "stink": false,
				})
				cd.call(11.0)
		"denis":
			if not combat:
				var fwd2 := -global_transform.basis.z
				fx.call("cast", "smoke", {
					"x": global_position.x + fwd2.x * 6.0, "z": global_position.z + fwd2.z * 6.0,
					"team": team, "stink": true,
				})
				cd.call(11.0)
		"ira":
			var hurt := _hurt_ally()
			if hurt:
				fx.call("cast", "generic", {
					"logic": "res://src/agents/effects/buffet_logic.gd",
					"x": hurt.global_position.x, "z": hurt.global_position.z, "team": team,
				})
				cd.call(9.0)
		"gera":
			var sw := get_node("/root/Smokes")
			for s: Dictionary in (sw.get("smokes") as Array):
				if String(s["team"]) != team and Vector2((s["pos"] as Vector3).x - global_position.x, (s["pos"] as Vector3).z - global_position.z).length() < 13.0:
					fx.call("cast", "dispel", { "x": (s["pos"] as Vector3).x, "z": (s["pos"] as Vector3).z, "team": team })
					cd.call(9.0)
					break
		"sanek":
			if not combat and agent.is_navigation_finished():
				fx.call("cast", "generic", {
					"logic": "res://src/agents/effects/trap.gd",
					"x": global_position.x, "z": global_position.z, "team": team,
					"cname": "Trap_bot_%d_%d" % [get_instance_id(), int(t)],
				})
				cd.call(20.0)
		"sova":
			if combat and target != null and is_instance_valid(target):
				fx.call("cast", "generic", {
					"logic": "res://src/agents/effects/sova_arrow.gd",
					"fx": global_position.x, "fy": global_position.y + 1.6, "fz": global_position.z,
					"tx": target.global_position.x, "ty": 0.0, "tz": target.global_position.z,
					"mode": "shock", "team": team, "owner_path": String(get_path()),
					"cname": "Arrow_bot_%d_%d" % [get_instance_id(), int(t)],
				})
				cd.call(9.0)
		_:
			pass


func _hurt_ally() -> Node3D:
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or node == self or String(node.get("team")) != team:
			continue
		var hp_v := int(node.get("hp"))
		if hp_v > 0 and hp_v < 70 and Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z).length() < 12.0:
			return node
	return null


func _visible_enemy() -> Node3D:
	if _now() < blind_until:
		return null  # ослеплённый бот не видит (честность)
	var fwd := -global_transform.basis.z
	var best: Node3D = null
	var bd := VISION_DIST
	for n in get_tree().get_nodes_in_group("combatants"):
		var node := n as Node3D
		if node == self or not is_instance_valid(node) or node.get("team") == team or int(node.get("hp")) <= 0:
			continue
		var to := node.global_position - global_position
		var d := to.length()
		if d >= bd:
			continue
		var dot := to.normalized().dot(fwd)
		if dot < FOV_DOT and d > 4.5:
			continue  # за спиной не видит — ловит слухом (паритет)
		if _los_clear(node):
			best = node
			bd = d
	return best


func _los_clear(node: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.6, 0)
	var to := node.global_position + Vector3(0, 1.4, 0)
	if bool(get_node("/root/Smokes").call("seg_blocked", from, to)):
		return false  # дым глушит зрение ботов (паритет web losClear)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var res := space.intersect_ray(q)
	return res.is_empty() or res["collider"] == node


func _aim_and_shoot(t: float) -> void:
	if not is_instance_valid(target) or int(target.get("hp")) <= 0:
		target = null  # труп не цель — не стреляем по мёртвым (и киллы не накручиваем)
		return
	var to := target.global_position - global_position
	var tgt_yaw := atan2(-to.x, -to.z)
	var dy := wrapf(tgt_yaw - rotation.y, -PI, PI)
	rotation.y += dy * float(cfg()["turn"])  # человеческий доворот (без снапа)
	if t < react_at or absf(dy) > 0.5 or t < next_shot:
		return
	var wd: Dictionary = Balance.WEAPONS[weapon_id]
	next_shot = t + maxf(0.12, 60.0 / float(wd["rpm"])) + rng.randf() * 0.12
	stat_shots += 1
	shot_sfx.play()
	made_noise.emit()
	# вероятностная модель попадания — ПАРИТЕТ web server.js botShoot
	var dist := to.length()
	var p_hit := clampf(float(cfg()["pHitMax"]) + 0.04 - dist * 0.009, float(cfg()["pHitMin"]), float(cfg()["pHitMax"]))
	if t < levit_until:
		p_hit *= 0.35  # всплыл в «Невесомости» — мажет (паритет)
	if rng.randf() < p_hit:
		stat_hits += 1
		var head := rng.randf() < float(cfg()["head"])
		var dmg := int(wd["head"] if head else wd["dmg"])
		if target.has_method("take_hit"):
			var pre := int(target.get("hp"))
			target.call("take_hit", dmg, "head" if head else "body", self, weapon_id)
			if pre > 0 and int(target.get("hp")) <= 0:
				stat_kills += 1  # килл = живой → мёртвый именно от НАШЕГО попадания


func _move(dt: float) -> void:
	var t := _now()
	var combat := t < engaging_until and target != null
	if agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * dt)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * dt)
		velocity.y -= float(Balance.MOVE["GRAVITY"]) * dt
		move_and_slide()
		return
	_repath_if_off_route()
	var next := agent.get_next_path_position()
	# RVO и столкновения умеют вытолкнуть бота С навмеша — в карман у стены (на «Высоте»
	# это щель между лестницей и трёхметровой платформой). Оттуда путь недостижим, и бот
	# стоит до срабатывания watchdog. Заметив уход с меша, правим курс на ближайшую точку
	# меша (движковый map_get_closest_point) — это возврат в игру, а не телепорт.
	var on_mesh := _snap_nav(global_position)
	if Vector2(global_position.x - on_mesh.x, global_position.z - on_mesh.z).length() > 0.7:
		next = on_mesh
	var dir := (next - global_position)
	dir.y = 0.0
	var speed := SPEED_COMBAT if combat else SPEED_CALM
	if t < levit_until:
		speed *= float(Balance.ABILITY["GERA_ULT_SLOW"])  # всплыл — вязнет
	if t < slow_until:
		speed *= slow_mul  # кислота/подкова/криспи/сигналка
	agent.max_speed = speed
	var desired := Vector3.ZERO
	if dir.length() > 0.05:
		dir = dir.normalized()
		desired = dir * speed
		if not combat:
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 0.15)
	agent.set_velocity(desired)  # RVO: безопасная скорость придёт в _on_safe_velocity
	velocity.y -= float(Balance.MOVE["GRAVITY"]) * dt


# Отход от СОБСТВЕННОГО маршрута. NavigationAgent3D умеет это сам (path_max_distance),
# но сверяется только ПОСЛЕ прохождения первой путевой точки: пока индекс нулевой,
# проверки нет вовсе. А отжимает бота с маршрута обычно как раз до первой точки — RVO
# в чоке, толчея, падение с платформы. Тогда бот молча идёт в путевую точку, оказавшуюся
# за геометрией, упирается в стену и стоит до watchdog (замер: 3.7–7.1 м от своего же
# маршрута, путь не менялся по 5–30 с). Считаем отход сами и просим переложить путь.
const REPATH_OFF_ROUTE := 1.5  # м: дальше нормального обхода по RVO, ближе любого залёта
const REPATH_COOLDOWN := 0.25  # с: перекладка — это A*, чаще смысла нет

var _next_repath := 0.0


func _repath_if_off_route() -> void:
	var t := _now()
	if t < _next_repath:
		return
	var p := agent.get_current_navigation_path()
	if p.size() < 2:
		return
	var off := INF
	for i in p.size() - 1:
		off = minf(off, global_position.distance_to(
			Geometry3D.get_closest_point_to_segment(global_position, p[i], p[i + 1])))
	if off <= REPATH_OFF_ROUTE:
		return
	_next_repath = t + REPATH_COOLDOWN
	# публичного «пересчитай» у агента нет, но смена цели его запускает: сбрасываем цель
	# на себя и тут же возвращаем прежнюю — путь пересчитается от текущей позиции
	var tgt := agent.target_position
	if tgt.is_equal_approx(global_position):
		return
	agent.target_position = global_position
	agent.target_position = tgt


func _on_safe_velocity(safe: Vector3) -> void:
	velocity.x = safe.x
	velocity.z = safe.z
	StepMove.move(self)  # тот же авто-подъём, что у игрока — иначе бот не залезет на лестницу
	_bot_steps()


func _bot_steps() -> void:
	# шаги бота (враг слышен позиционно); Макс-«Ветер» бесшумен, как у игрока
	if char_id == "max" or not is_on_floor():
		return
	var h := Vector2(velocity.x, velocity.z).length()
	if h <= 3.0:
		return
	_step_dist += h * get_physics_process_delta_time()
	if _step_dist > 2.7:
		_step_dist = 0.0
		step_sfx.stream = _steps[randi() % _steps.size()]
		step_sfx.volume_db = -6.0
		step_sfx.pitch_scale = 0.9 + randf() * 0.2
		step_sfx.play()


func _watchdog(dt: float) -> void:
	# анти-застревание: нет движения 2с при живом пути → перепрокладка + телеметрия (канон)
	if agent.is_navigation_finished():
		_stuck_t = 0.0
		_last_pos = global_position
		return
	if global_position.distance_to(_last_pos) < 0.08 * dt * 60.0 * 0.05:
		_stuck_t += dt
	else:
		_stuck_t = 0.0
		_last_pos = global_position
	if _stuck_t > 2.0:
		_stuck_t = 0.0
		stat_stuck_events += 1
		_hold_spot = Vector3.INF  # спот был плохой (в ящике/за стеной) — выберем другой
		_pick_patrol_point()


func _pick_patrol_point() -> void:
	# патруль: сайт A / сайт B / центр (мета карты)
	var map_root := get_tree().current_scene
	var meta_raw: String = map_root.get_meta("map_meta", "{}") if map_root else "{}"
	var meta: Dictionary = JSON.parse_string(meta_raw) if meta_raw != "{}" else {}
	var pts: Array = []
	if meta.has("site_a"):
		pts.append(Vector3(float(meta["site_a"][0]), 0, float(meta["site_a"][1])))
		pts.append(Vector3(float(meta["site_b"][0]), 0, float(meta["site_b"][1])))
	pts.append(Vector3(0, 0, 0))
	agent.target_position = pts[rng.randi() % pts.size()]


# ===== получение урона (тот же утиный интерфейс, что у мишени) =====
var _shape_part := {}


# Зона попадания — ПО ВЫСОТЕ точки, как у игрока (см. player.gd part_at): капсула движения
# Move идёт первым шейпом и перекрывает голову, поэтому индекс шейпа всегда давал «body».
func part_at(shape_idx: int, hit_y: float = INF) -> String:
	if hit_y != INF:
		var rel := hit_y - global_position.y
		if rel >= 1.48:
			return "head"
		if rel <= 0.75:
			return "leg"
		return "body"
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


func take_hit(dmg: int, part: String, attacker: Node = null, weapon := "") -> void:
	if hp <= 0:
		return
	hp -= dmg
	last_dmg_t = _now()
	if hp <= 0:
		stat_deaths += 1
		visible = false
		set_collision_layer_value(1, false)
		var mt := Match.find(get_tree())
		if mt and mt.phase != Match.Phase.WAIT:
			mt.on_death(self, attacker, weapon, part == "head")  # в матче лежим до конца раунда
		else:
			var tw := create_tween()
			tw.tween_interval(2.0)
			tw.tween_callback(func() -> void:
				global_position = _spawn_pos
				hp = int(Balance.RULES["BASE_HP"])
				visible = true
				set_collision_layer_value(1, true))


func round_reset() -> void:
	hp = int(Balance.RULES["BASE_HP"])
	visible = true
	set_collision_layer_value(1, true)
	_bought = false
	weapon_id = "classic"  # новый раунд — с пистолетом, пока не купит
	target = null
	engaging_until = -99.0
	blind_until = 0.0
	stun_until = 0.0
	ai_site = ""
	_hold_spot = Vector3.INF
	_guard_ang = -1.0
	_next_ability = _now() + rng.randf() * 3.0  # скиллы не залпом на старте раунда
	# на спавн + СБРОС пути (иначе после телепорта бот скребёт стены по протухшему пути)
	global_position = _spawn_pos
	velocity = Vector3.ZERO
	agent.target_position = global_position
	_stuck_t = 0.0
	_last_pos = global_position


func give_weapon(id: String) -> void:
	weapon_id = id
