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
var last_kill_t := -99.0
var last_dmg_t := -99.0

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
	if combat:
		_aim_and_shoot(t)
	elif heard_until > t and heard_pos != Vector3.INF:
		agent.target_position = heard_pos
	elif agent.is_navigation_finished():
		_pick_patrol_point()


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
	var next := agent.get_next_path_position()
	var dir := (next - global_position)
	dir.y = 0.0
	var speed := SPEED_COMBAT if combat else SPEED_CALM
	if t < levit_until:
		speed *= float(Balance.ABILITY["GERA_ULT_SLOW"])  # всплыл — вязнет
	agent.max_speed = speed
	var desired := Vector3.ZERO
	if dir.length() > 0.05:
		dir = dir.normalized()
		desired = dir * speed
		if not combat:
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 0.15)
	agent.set_velocity(desired)  # RVO: безопасная скорость придёт в _on_safe_velocity
	velocity.y -= float(Balance.MOVE["GRAVITY"]) * dt


func _on_safe_velocity(safe: Vector3) -> void:
	velocity.x = safe.x
	velocity.z = safe.z
	move_and_slide()


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
	# на спавн + СБРОС пути (иначе после телепорта бот скребёт стены по протухшему пути)
	global_position = _spawn_pos
	velocity = Vector3.ZERO
	agent.target_position = global_position
	_stuck_t = 0.0
	_last_pos = global_position


func give_weapon(id: String) -> void:
	weapon_id = id
