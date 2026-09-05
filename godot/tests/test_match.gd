# Раундовый каркас: фазы/экономика/шип/ульта — паритет web server.js (числа из balance.gd).
extends GutTest

var m: Match
var a: Node3D
var b: Node3D


func before_each() -> void:
	m = Match.new()
	m.set_physics_process(false)  # тикаем руками через advance()
	add_child_autofree(m)
	a = _mk("A")
	b = _mk("B")


func _mk(tm: String) -> Node3D:
	var c: Node3D = (load("res://tests/stub_combatant.gd") as GDScript).new()
	c.set("team", tm)
	c.add_to_group("combatants")
	add_child_autofree(c)
	return c


func _start_attack_a() -> void:
	# start_match рандомит сторону — перезапускаем, пока атака не A (для детерминизма сценариев)
	m.start_match()
	while m.attack_team != "A":
		m.start_match()


func test_phases_buy_to_live() -> void:
	_start_attack_a()
	assert_eq(m.phase, Match.Phase.BUY, "после старта — закупка")
	assert_eq(int(a.get("credits")), 800, "стартовые деньги")
	m.advance(float(Balance.RULES["BUY_TIME"]) + 0.1)
	assert_eq(m.phase, Match.Phase.LIVE, "закупка кончилась — live")


func test_elimination_and_economy() -> void:
	_start_attack_a()
	m.advance(15.1)  # -> LIVE
	# A убивает B
	b.set("hp", 0)
	m.on_death(b, a, "vandal", false)
	m.advance(0.05)
	assert_eq(m.phase, Match.Phase.ROUND_END, "элиминация закрыла раунд")
	assert_eq(int(m.score["A"]), 1)
	# деньги: киллер 800 + 200(килл) + 3000(победа); жертва 800 + 1900 (ПЕРВЫЙ проигрыш
	# в серии — паритет web server.js:245, где lossReward = [1900,1900,2400,2900][streak])
	assert_eq(int(a.get("credits")), 4000)
	assert_eq(int(b.get("credits")), 2700)
	assert_eq(int(a.get("kills")), 1)
	assert_eq(int(a.get("ult")), 1, "ульта только за килл")


func test_loss_then_buy_scenario() -> void:
	_start_attack_a()
	m.advance(15.1)
	a.set("hp", 0)  # A проиграла элиминацией
	m.on_death(a, b, "classic", false)
	m.advance(0.05)
	assert_eq(int(a.get("credits")), 800 + 1900, "лузер: 800 + первая ступень эко-серии")
	# следующий раунд: закупка вандала
	m.advance(float(Balance.RULES["ROUND_END_TIME"]) + 0.1)
	assert_eq(m.phase, Match.Phase.BUY, "второй раунд — закупка")
	# 2700 на вандал 2900 НЕ хватает — это и есть смысл эко-серии: после проигрыша
	# приходится экономить. Берём то, что по карману.
	assert_false(m.try_buy(a, "vandal"), "2700 на вандал 2900 не хватает")
	assert_true(m.try_buy(a, "spectre"), "на спектр хватает")
	assert_eq(int(a.get("credits")), 2700 - int(Balance.WEAPONS["spectre"]["price"]))
	assert_eq(String(a.get("last_weapon")), "spectre")
	assert_false(m.try_buy(a, "operator"), "на Оператор 4700 уже не хватает")


func test_spike_plant_boom() -> void:
	_start_attack_a()
	m.spike_carrier = a
	m.advance(15.1)  # LIVE
	# плант: держим 4с в сайте
	for i in 41:
		m.try_plant(a, true, true, 0.1)
	assert_eq(m.phase, Match.Phase.PLANTED, "шип установлен за 4с")
	var planter_credits := int(a.get("credits"))
	assert_eq(planter_credits, 800 + 300, "плант +300")
	# 45с — взрыв, победа атаки
	m.advance(float(Balance.RULES["SPIKE_TIME"]) + 0.1)
	assert_eq(m.phase, Match.Phase.ROUND_END)
	assert_eq(int(m.score["A"]), 1, "бум — победа атаки")


func test_spike_defuse_with_half_memory() -> void:
	_start_attack_a()
	m.spike_carrier = a
	m.advance(15.1)
	for i in 41:
		m.try_plant(a, true, true, 0.1)
	assert_eq(m.phase, Match.Phase.PLANTED)
	b.set("global_position", m.spike_planted_at)
	# полдефуза (3.5с из 7) — отпустил
	for i in 36:
		m.try_defuse(b, true, 0.1)
	m.try_defuse(b, false, 0.1)
	assert_almost_eq(m.defuse_accum, 3.5, 0.11, "половинка запомнилась (web defuseHalfDone)")
	# дожимаем вторую половину
	for i in 36:
		m.try_defuse(b, true, 0.1)
	assert_eq(m.phase, Match.Phase.ROUND_END)
	assert_eq(int(m.score["B"]), 1, "дефуз — победа защиты")


func test_ult_cap() -> void:
	_start_attack_a()
	a.set("char_id", "artemiy")  # кап 5
	m.advance(15.1)
	for i in 8:
		m.on_death(b, a, "vandal", false)
	assert_eq(int(a.get("ult")), 5, "ульта капится по агенту (Артемий 5)")


func test_match_end_at_five() -> void:
	_start_attack_a()
	m.score = { "A": 4, "B": 0 }
	m.advance(15.1)
	b.set("hp", 0)
	m.advance(0.05)
	m.advance(float(Balance.RULES["ROUND_END_TIME"]) + 0.1)
	assert_eq(m.phase, Match.Phase.MATCH_END, "5 побед — конец матча")
