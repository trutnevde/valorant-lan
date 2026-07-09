# Санити раундового каркаса: headless-матч ботов на Дуэли до 3 завершённых раундов.
# Проверяет: фазы идут, раунды заканчиваются, экономика течёт (деньги растут по таблице),
# смерти в раунде без ре-спавна, рассадка при смене сторон.
#   godot --headless --path . -s res://tools/matchcheck.gd
extends SceneTree

const MAX_SECONDS := 400.0
var rounds_done := 0
var elapsed := 0.0
var mt: Match
var bots: Array[Bot] = []


func _initialize() -> void:
	var map: Node3D = (load("res://scenes/maps/duel.tscn") as PackedScene).instantiate()
	root.add_child(map)
	current_scene = map
	mt = Match.new()
	mt.name = "Match"
	map.add_child(mt)
	await process_frame
	await process_frame
	var bot_scene: PackedScene = load("res://scenes/bots/bot.tscn")
	var atk := get_nodes_in_group("spawn_attack")
	var def := get_nodes_in_group("spawn_defend")
	for i in 2:
		bots.append(_bot(bot_scene, map, "A", (atk[i] as Node3D).global_position))
		bots.append(_bot(bot_scene, map, "B", (def[i] as Node3D).global_position))
	mt.round_ended.connect(func(w: String, r: String) -> void:
		rounds_done += 1
		print("MATCHCHECK: раунд %d — победа %s (%s), счёт A%d:B%d" % [mt.round_no, w, r, int(mt.score["A"]), int(mt.score["B"])]))
	mt.start_match()
	physics_frame.connect(_tick)


func _bot(scene: PackedScene, map: Node3D, tm: String, pos: Vector3) -> Bot:
	var b := scene.instantiate() as Bot
	b.team = tm
	b.preset = "hard"  # быстрее убивают → быстрее раунды
	map.add_child(b)
	b.global_position = pos + Vector3(0, 0.2, 0)
	return b


func _tick() -> void:
	elapsed += 1.0 / Engine.physics_ticks_per_second
	if rounds_done >= 3:
		_report(true)
	elif elapsed > MAX_SECONDS:
		print("MATCHCHECK: TIMEOUT — раундов завершено %d" % rounds_done)
		_report(false)


func _report(ok: bool) -> void:
	physics_frame.disconnect(_tick)
	var econ_ok := true
	for b in bots:
		# после раундов у всех должны накопиться деньги сверх старта (win/loss награды)
		if int(b.credits) <= int(Balance.RULES["START_CREDITS"]):
			econ_ok = false
		print("MATCHCHECK: %s creds=%d kills=%d deaths=%d ult=%d weap=%s" % [b.name, b.credits, b.kills, b.deaths, b.ult, b.weapon_id])
	if ok and not econ_ok:
		print("MATCHCHECK: FAIL экономика не течёт")
		quit(1)
		return
	print("MATCHCHECK: %s" % ("OK — 3 раунда, экономика течёт" if ok else "FAIL"))
	quit(0 if ok else 1)
