# Матч-контроллер: раунды/закупка/экономика/шип — порт логики web server.js 1:1.
# Хост-авторитарен (клиенты получают состояние RPC), офлайн работает без сети.
# Логика тестируема: собственные часы (_clock), тик двигается из _physics_process
# или вручную из GUT (advance()).
class_name Match
extends Node

enum Phase { WAIT, BUY, LIVE, PLANTED, ROUND_END, MATCH_END }

const MATCH_END_TIME := 12.0  # сколько показываем итог матча, потом новый матч (web backToLobby)

var phase := Phase.WAIT
var round_no := 0
var score := { "A": 0, "B": 0 }
var attack_team := "A"
var deadline := 0.0
var _clock := 0.0

# шип
var spike_planted_at := Vector3.INF
var plant_progress := 0.0     # сек удержания планта
var _defuser: Node = null  # замок: кто именно разминирует (web defuseBusy)
var defuse_accum := 0.0       # сек дефуза (половинки помнятся: web defuseHalfDone)
var spike_carrier: Node3D = null

signal phase_changed(phase: int, deadline: float)
signal score_changed(a: int, b: int, attack_team: String)
signal round_ended(winner: String, reason: String)
signal match_ended(winner: String)
signal killfeed(killer_name: String, victim_name: String, weapon: String, head: bool)
signal killer_scored(killer: Node)  # твисты «на килл» (дэш/ножи Макса)
signal spike_planted(pos: Vector3)
signal spike_defused
signal spike_boom


func _ready() -> void:
	add_to_group("match")


static func find(tree: SceneTree) -> Match:
	return tree.get_first_node_in_group("match") as Match


func now() -> float:
	return _clock


func _physics_process(dt: float) -> void:
	if NetHub.online() and not multiplayer.is_server():
		_clock += dt  # клиент: часы идут (для таймеров HUD), логику считает хост
		return
	advance(dt)


# ===== старт =====
func start_match() -> void:
	round_no = 0
	score = { "A": 0, "B": 0 }
	attack_team = "A" if randi() % 2 == 0 else "B"
	for c in _combatants():
		c.set("credits", int(Balance.RULES["START_CREDITS"]))
		c.set("kills", 0)
		c.set("deaths", 0)
		c.set("ult", 0)
	start_round()


func start_round() -> void:
	round_no += 1
	if round_no > 1:
		attack_team = "B" if attack_team == "A" else "A"  # смена сторон каждый раунд (web)
	phase = Phase.BUY
	deadline = now() + float(Balance.RULES["BUY_TIME"])
	spike_planted_at = Vector3.INF
	plant_progress = 0.0
	defuse_accum = 0.0
	_defuser = null
	corpses.clear()
	var sw := get_node("/root/Smokes")
	(sw.get("smokes") as Array).clear()
	(sw.get("no_smoke_zones") as Array).clear()
	# оживить всех + шип случайному атакеру (людям приоритет — web)
	var attackers: Array = []
	for c in _combatants():
		if c.has_method("round_reset"):
			c.call("round_reset")
		if String(c.get("team")) == attack_team:
			attackers.append(c)
	spike_carrier = null
	if not attackers.is_empty():
		var humans := attackers.filter(func(c: Node) -> bool: return not (c is Bot))
		var pool: Array = humans if not humans.is_empty() else attackers
		spike_carrier = pool[randi() % pool.size()]
	NetHub.broadcast_round_reset()  # клиенты пересобирают заряды/лоадаут/CC у себя
	_broadcast_state()
	NetHub.push_all_combat()        # и получают живое состояние всех бойцов
	_broadcast_spike()
	phase_changed.emit(phase, deadline)


# ===== тик =====
func advance(dt: float) -> void:
	_clock += dt
	match phase:
		Phase.BUY:
			if now() >= deadline:
				phase = Phase.LIVE
				deadline = now() + float(Balance.RULES["ROUND_TIME"])
				_broadcast_state()
				phase_changed.emit(phase, deadline)
		Phase.LIVE:
			_denis_regen(dt)
			_check_elimination()
			if phase == Phase.LIVE and now() >= deadline:
				end_round(_defenders(), "time")  # время вышло — защита удержала
		Phase.PLANTED:
			_check_elimination_planted()
			if phase == Phase.PLANTED and now() >= deadline:
				spike_boom.emit()
				end_round(attack_team, "boom")
		Phase.ROUND_END:
			if now() >= deadline:
				if score["A"] >= int(Balance.RULES["ROUNDS_TO_WIN"]) or score["B"] >= int(Balance.RULES["ROUNDS_TO_WIN"]):
					phase = Phase.MATCH_END
					deadline = now() + MATCH_END_TIME
					var w := "A" if score["A"] > score["B"] else "B"
					match_ended.emit(w)
					_broadcast_state()
					phase_changed.emit(phase, deadline)  # на этом переходе сигнал раньше не шёл
				else:
					start_round()
		Phase.MATCH_END:
			# Раньше здесь стояло `_: pass` — дедлайн не выставлялся, и после пятого выигранного
			# раунда игра зависала навсегда: второй матч был невозможен без перезапуска процесса.
			# Паритет web backToLobby (server.js:263, 1425): показали итог — и начали заново.
			if now() >= deadline:
				start_match()
		_:
			pass


var _regen_acc := {}


# пассивка Дениса «Регенерация мясника»: 3.5 HP/с до 100 вне боя (не били 4с) — хост
func _denis_regen(dt: float) -> void:
	var t := now()
	var fx := get_node("/root/Fx")
	for c in _combatants():
		if String(c.get("char_id")) != "denis" or int(c.get("hp")) <= 0:
			continue
		if int(c.get("hp")) >= int(Balance.ABILITY["DENIS_REGEN_CAP"]):
			continue
		if t - float(c.get("last_dmg_t")) < float(Balance.ABILITY["DENIS_REGEN_DELAY"]):
			continue
		var k: int = c.get_instance_id()
		_regen_acc[k] = float(_regen_acc.get(k, 0.0)) + float(Balance.ABILITY["DENIS_REGEN"]) * dt
		if _regen_acc[k] >= 1.0:
			var whole := int(_regen_acc[k])
			_regen_acc[k] = float(_regen_acc[k]) - whole
			fx.call("apply_heal", c, whole)


func _defenders() -> String:
	return "B" if attack_team == "A" else "A"


func _combatants() -> Array:
	return get_tree().get_nodes_in_group("combatants")


func _alive(tm: String) -> int:
	var n := 0
	for c in _combatants():
		if String(c.get("team")) == tm and int(c.get("hp")) > 0:
			n += 1
	return n


func _check_elimination() -> void:
	if _alive(attack_team) == 0 and _alive(_defenders()) > 0:
		end_round(_defenders(), "elim")
	elif _alive(_defenders()) == 0 and _alive(attack_team) > 0:
		end_round(attack_team, "elim")


func _check_elimination_planted() -> void:
	# после планта атаке достаточно шипа: смерть атакеров НЕ завершает раунд (web-паритет)
	if _alive(_defenders()) == 0 and _alive(attack_team) > 0:
		end_round(attack_team, "elim")


# ===== смерть/киллы (нода-жертва зовёт через сигнал died у матча нет; зовём напрямую) =====
var corpses: Array[Dictionary] = []  # {pos, team, until} — Кровопир Дениса ест ТОЛЬКО у трупа


func corpse_near(pos: Vector3, enemy_of_team: String, r: float) -> bool:
	var t := now()
	for c in corpses:
		if t > float(c["until"]) or String(c["team"]) == enemy_of_team:
			continue
		var cp: Vector3 = c["pos"]
		if Vector2(pos.x - cp.x, pos.z - cp.z).length() < r:
			return true
	return false


func on_death(victim: Node, killer: Node, weapon: String, head: bool) -> void:
	if killer != null and killer != victim and String(killer.get("team")) != String(victim.get("team")):
		killer.set("kills", int(killer.get("kills")) + 1)
		# ульта — ТОЛЬКО за киллы (канон Эпохи 15), кап по агенту
		var ch := String(killer.get("char_id")) if "char_id" in killer else ""
		var cap := int(Balance.CHARACTERS.get(ch, {}).get("ultCost", 7))
		killer.set("ult", mini(cap, int(killer.get("ult")) + 1))
		_give_credits(killer, int(Balance.RULES["KILL_REWARD"]))
		killer.set("last_kill_t", now())  # «накормленность» Кровопира Дениса
		killer_scored.emit(killer)
	# труп для Кровопира (host) + визуал всем (стабы тестов — не Node3D, пропускаем)
	var v3 := victim as Node3D
	if v3 and v3.is_inside_tree():
		var vp := v3.global_position
		corpses.append({ "pos": vp, "team": String(victim.get("team")), "until": now() + float(Balance.ABILITY["CORPSE_LIFE"]) })
		var fxn := get_node("/root/Fx")
		fxn.call("_fx_broadcast", "corpse", { "x": vp.x, "z": vp.z })
		# пассивка Иры «Прощальный ужин»: её убийство создаёт хил-зону у трупа врага
		if killer and String(killer.get("char_id")) == "ira" and killer != victim:
			var z: Node = (load("res://src/agents/effects/util_zone.gd") as GDScript).new()
			z.set("data", {
				"shape": "circle", "x": vp.x, "z": vp.z, "r": float(Balance.ABILITY["IRA_CORPSE_R"]),
				"dur": float(Balance.ABILITY["IRA_CORPSE_TIME"]), "heal_rate": float(Balance.ABILITY["IRA_CORPSE_RATE"]),
				"team": String(killer.get("team")), "owner_path": String(killer.get_path()),
			})
			get_tree().current_scene.add_child(z)
			fxn.call("_fx_broadcast", "ira_corpse_vis", { "x": vp.x, "z": vp.z })
	victim.set("deaths", int(victim.get("deaths")) + 1)
	killfeed.emit(String(killer.name) if killer else "?", String(victim.name), weapon, head)
	if spike_carrier == victim:
		spike_carrier = null  # шип упал (подбор — упрощение: авто-переход к ближайшему атакеру в G7)
		for c in _combatants():
			if String(c.get("team")) == attack_team and int(c.get("hp")) > 0:
				spike_carrier = c
				break


func _give_credits(c: Node, amount: int) -> void:
	c.set("credits", mini(int(Balance.RULES["MAX_CREDITS"]), int(c.get("credits")) + amount))


# ===== шип =====
func try_plant(planter: Node, in_site: bool, holding: bool, dt: float) -> void:
	if phase != Phase.LIVE or String(planter.get("team")) != attack_team or planter != spike_carrier:
		return
	if not in_site or not holding:
		plant_progress = 0.0
		return
	plant_progress += dt
	if plant_progress >= float(Balance.RULES["PLANT_TIME"]):
		phase = Phase.PLANTED
		spike_planted_at = (planter as Node3D).global_position
		deadline = now() + float(Balance.RULES["SPIKE_TIME"])
		_give_credits(planter, int(Balance.RULES["PLANT_REWARD"]))
		spike_carrier = null
		spike_planted.emit(spike_planted_at)
		_broadcast_spike()
		_broadcast_state()
		phase_changed.emit(phase, deadline)


func try_defuse(defuser: Node, holding: bool, dt: float) -> void:
	if phase != Phase.PLANTED or String(defuser.get("team")) != _defenders():
		return
	if int(defuser.get("hp")) <= 0:
		return
	# ЗАМОК ВЛАДЕЛЬЦА (паритет web defuseBusy, server.js:606). Без него defuse_accum был
	# общим счётчиком: двое защитников у шипа разминировали за 3.5 с вместо 7, трое — за 2.33,
	# а любой стоящий рядом и НЕ жмущий F каждый кадр срезал чужой прогресс.
	if _defuser != null and (not is_instance_valid(_defuser) or int(_defuser.get("hp")) <= 0):
		_defuser = null  # прежний разминирующий умер — замок свободен
	if _defuser != null and _defuser != defuser:
		return
	var near := (defuser as Node3D).global_position.distance_to(spike_planted_at) < 2.8
	if not near or not holding:
		if _defuser == defuser:
			_defuser = null
			# половинка помнится (web defuseHalfDone): срезаем до половины, не до нуля
			var half := float(Balance.RULES["DEFUSE_TIME"]) * 0.5
			defuse_accum = half if defuse_accum >= half else 0.0
		return
	_defuser = defuser
	defuse_accum += dt
	if defuse_accum >= float(Balance.RULES["DEFUSE_TIME"]):
		spike_defused.emit()
		end_round(_defenders(), "defuse")


# ===== конец раунда =====
func end_round(winner: String, reason: String) -> void:
	if phase == Phase.ROUND_END or phase == Phase.MATCH_END:
		return
	phase = Phase.ROUND_END
	deadline = now() + float(Balance.RULES["ROUND_END_TIME"])
	score[winner] = int(score[winner]) + 1
	for c in _combatants():
		var win := String(c.get("team")) == winner
		_give_credits(c, int(Balance.RULES["WIN_REWARD"]) if win else int(Balance.RULES["LOSS_REWARD"]))
	round_ended.emit(winner, reason)
	score_changed.emit(int(score["A"]), int(score["B"]), attack_team)
	_broadcast_state()
	phase_changed.emit(phase, deadline)


# ===== закупка (хост валидирует) =====
func try_buy(buyer: Node, weapon_id: String) -> bool:
	if phase != Phase.BUY:
		return false
	var wd: Dictionary = Balance.WEAPONS.get(weapon_id, {})
	if wd.is_empty():
		return false
	var price := int(wd["price"])
	if int(buyer.get("credits")) < price:
		return false
	buyer.set("credits", int(buyer.get("credits")) - price)
	if buyer.has_method("give_weapon"):
		buyer.call("give_weapon", weapon_id)
	NetHub.push_combat(buyer)  # кредиты списались — иначе у клиента в HUD старая сумма
	return true


# ===== синк состояния клиентам =====
func _broadcast_state() -> void:
	if NetHub.online() and multiplayer.is_server():
		_state.rpc(phase, deadline - now(), int(score["A"]), int(score["B"]), attack_team, round_no)


@rpc("authority", "reliable")
func _state(ph: int, time_left: float, a: int, b: int, atk: String, rnd: int) -> void:
	phase = ph as Phase
	deadline = now() + time_left
	score = { "A": a, "B": b }
	attack_team = atk
	round_no = rnd
	phase_changed.emit(phase, deadline)
	score_changed.emit(a, b, atk)


# ===== шип по сети =====
# Клиент не знал ни кто несёт шип, ни где он установлен: spike_carrier и spike_planted_at
# жили только у хоста. Из-за этого носитель не понимал, что несёт шип, а после планта
# у клиента не было ни точки на миникарте, ни цели для дефуза.
func _broadcast_spike() -> void:
	if NetHub.online() and multiplayer.is_server():
		var cp := NodePath()
		if spike_carrier != null and is_instance_valid(spike_carrier):
			cp = spike_carrier.get_path()
		_spike_state.rpc(cp, spike_planted_at)


@rpc("authority", "reliable")
func _spike_state(carrier_path: NodePath, planted_at: Vector3) -> void:
	spike_carrier = get_node_or_null(carrier_path) as Node3D if carrier_path != NodePath() else null
	spike_planted_at = planted_at
	if planted_at != Vector3.INF:
		spike_planted.emit(planted_at)
