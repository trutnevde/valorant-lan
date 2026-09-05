# G11b: шип читается на слух и глазами, раунд убирает за собой, экономика полная.
extends GutTest


func _match() -> Match:
	var mt := Match.new()
	add_child_autofree(mt)
	return mt


# БЫЛО: сигналы шипа не имели НИ ОДНОГО слушателя во всём проекте.
func test_spike_signals_have_listener() -> void:
	var _mt := _match()
	var fx: Node3D = (load("res://src/agents/spike_fx.gd") as GDScript).new()
	add_child_autofree(fx)
	await wait_process_frames(3)
	# проверяем ТОТ матч, к которому узел реально привязался: в дереве GUT может висеть
	# несколько Match из соседних тестов, и Match.find берёт первый в группе
	var bound = fx.get("_mt")
	assert_not_null(bound, "SpikeFx нашёл матч")
	assert_gt(bound.spike_planted.get_connections().size(), 0, "у планта есть слушатель")
	assert_gt(bound.spike_defused.get_connections().size(), 0, "у дефуза есть слушатель")
	assert_gt(bound.spike_boom.get_connections().size(), 0, "у взрыва есть слушатель")


# БЫЛО: эффекты прошлого раунда оставались на карте.
func test_world_fx_cleared_between_rounds() -> void:
	var fx := get_node("/root/Fx")
	var junk := Node3D.new()
	add_child_autofree(junk)
	junk.add_to_group("world_fx")
	assert_true(junk.is_in_group("world_fx"), "мусор помечен группой")
	fx.call("clear_world")
	await wait_process_frames(2)
	assert_false(is_instance_valid(junk) and junk.is_in_group("world_fx"),
		"новый раунд начался с чистой карты")


# БЫЛО: плоская награда за проигрыш; в вебе — серия [1900, 1900, 2400, 2900].
func test_loss_streak_economy() -> void:
	var mt := _match()
	assert_eq(mt.LOSS_STREAK_REWARD, [1900, 1900, 2400, 2900], "серия как в web server.js")
	mt.loss_streak = { "A": 0, "B": 0 }
	mt.score = { "A": 0, "B": 0 }
	mt.phase = Match.Phase.LIVE
	mt.end_round("A", "elim")
	assert_eq(int(mt.loss_streak["B"]), 1, "проигравший копит серию")
	assert_eq(int(mt.loss_streak["A"]), 0, "победитель серию сбрасывает")
	mt.phase = Match.Phase.LIVE
	mt.end_round("A", "elim")
	assert_eq(int(mt.loss_streak["B"]), 2, "вторая подряд")
	for i in 5:
		mt.phase = Match.Phase.LIVE
		mt.end_round("A", "elim")
	assert_eq(int(mt.loss_streak["B"]), 3, "серия упирается в 3")


# БЫЛО: дефуз общим счётчиком — двое разминировали вдвое быстрее, а стоящий рядом и НЕ
# жмущий F срезал чужой прогресс.
func test_defuse_lock_single_owner() -> void:
	var mt := _match()
	mt.phase = Match.Phase.PLANTED
	mt.attack_team = "A"
	mt.spike_planted_at = Vector3.ZERO
	# без дедлайна advance() мгновенно взрывает шип и закрывает раунд
	mt.deadline = mt.now() + float(Balance.RULES["SPIKE_TIME"])
	var scene: PackedScene = load("res://scenes/bots/bot.tscn")
	var d1: Bot = scene.instantiate()
	var d2: Bot = scene.instantiate()
	for d: Bot in [d1, d2]:
		add_child_autofree(d)
		d.team = "B"          # защита
		d.global_position = Vector3.ZERO
	await wait_process_frames(2)
	# первый разминирует — счётчик пошёл
	mt.try_defuse(d1, true, 1.0)
	assert_almost_eq(mt.defuse_accum, 1.0, 0.001, "первый защитник крутит счётчик")
	# второй у того же шипа НЕ должен ни ускорять, ни сбрасывать
	mt.try_defuse(d2, true, 1.0)
	assert_almost_eq(mt.defuse_accum, 1.0, 0.001, "второй не ускоряет дефуз вдвое")
	mt.try_defuse(d2, false, 1.0)
	assert_almost_eq(mt.defuse_accum, 1.0, 0.001, "и не сбрасывает чужой прогресс")
	# сам владелец отпустил — прогресс срезается (половинка помнится)
	mt.try_defuse(d1, false, 1.0)
	assert_lt(mt.defuse_accum, 1.0, "владелец отпустил — прогресс срезан")
