# Матч-контроллер: раунды/закупка/экономика/шип — порт логики web server.js 1:1.
# Хост-авторитарен (клиенты получают состояние RPC), офлайн работает без сети.
# Логика тестируема: собственные часы (_clock), тик двигается из _physics_process
# или вручную из GUT (advance()).
class_name Match
extends Node

enum Phase { WAIT, BUY, LIVE, PLANTED, ROUND_END, MATCH_END }

var phase := Phase.WAIT
var round_no := 0
var score := { "A": 0, "B": 0 }
var attack_team := "A"
var deadline := 0.0
var _clock := 0.0

# шип
var spike_planted_at := Vector3.INF
var plant_progress := 0.0     # сек удержания планта
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
	_broadcast_state()
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
					var w := "A" if score["A"] > score["B"] else "B"
					match_ended.emit(w)
					_broadcast_state()
				else:
					start_round()
		_:
			pass


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
func on_death(victim: Node, killer: Node, weapon: String, head: bool) -> void:
	if killer != null and killer != victim and String(killer.get("team")) != String(victim.get("team")):
		killer.set("kills", int(killer.get("kills")) + 1)
		# ульта — ТОЛЬКО за киллы (канон Эпохи 15), кап по агенту
		var ch := String(killer.get("char_id")) if "char_id" in killer else ""
		var cap := int(Balance.CHARACTERS.get(ch, {}).get("ultCost", 7))
		killer.set("ult", mini(cap, int(killer.get("ult")) + 1))
		_give_credits(killer, int(Balance.RULES["KILL_REWARD"]))
		killer_scored.emit(killer)
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
		_broadcast_state()
		phase_changed.emit(phase, deadline)


func try_defuse(defuser: Node, holding: bool, dt: float) -> void:
	if phase != Phase.PLANTED or String(defuser.get("team")) != _defenders():
		return
	var near := (defuser as Node3D).global_position.distance_to(spike_planted_at) < 2.2
	if not near or not holding:
		# половинка помнится (web defuseHalfDone): срезаем до половины, не до нуля
		var half := float(Balance.RULES["DEFUSE_TIME"]) * 0.5
		if defuse_accum >= half:
			defuse_accum = half
		else:
			defuse_accum = 0.0
		return
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
