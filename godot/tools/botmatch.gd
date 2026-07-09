# Headless бот-матч с телеметрией (гейт-инструмент, паритет веб test/botmatch.mjs):
#   godot --headless --path . -s res://tools/botmatch.gd -- --preset=medium --seconds=45
# Спавнит ботов двух команд на duel, гоняет симуляцию, печатает JSON:
# застревания, сквозь-стены (по walls_aabb из меты карты), точность, k/d.
# Пороги: застреваний 0, сквозь-стен 0, точность в коридоре пресета. Exit 0/1.
extends SceneTree

var preset := "medium"
var seconds := 45.0
var per_team := 3
var bots: Array[Bot] = []
var walls: Array = []
var elapsed := 0.0
var through_walls := 0
var _through_seen := {}
var _done := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			preset = arg.substr(9)
		elif arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--bots="):
			per_team = int(arg.substr(7))
	var map: Node3D = (load("res://scenes/maps/duel.tscn") as PackedScene).instantiate()
	root.add_child(map)
	current_scene = map
	var meta: Dictionary = JSON.parse_string(String(map.get_meta("map_meta", "{}")))
	walls = meta.get("walls_aabb", [])
	await process_frame
	await process_frame

	var bot_scene: PackedScene = load("res://scenes/bots/bot.tscn")
	var spawns_a := _spawn_points(map, "spawn_attack")
	var spawns_d := _spawn_points(map, "spawn_defend")
	for i in per_team:
		bots.append(_spawn_bot(bot_scene, map, "A", spawns_a[i % spawns_a.size()]))
		bots.append(_spawn_bot(bot_scene, map, "B", spawns_d[i % spawns_d.size()]))
	print("botmatch: карта duel, пресет %s, ботов %d, %d сек" % [preset, bots.size(), int(seconds)])
	physics_frame.connect(_tick)


func _spawn_points(map: Node3D, grp: String) -> Array:
	var out: Array = []
	for n in get_nodes_in_group(grp):
		out.append((n as Node3D).global_position)
	if out.is_empty():
		out.append(Vector3.ZERO)
	return out


func _spawn_bot(scene: PackedScene, map: Node3D, tm: String, pos: Vector3) -> Bot:
	var b := scene.instantiate() as Bot
	b.team = tm
	b.preset = preset
	map.add_child(b)
	b.global_position = pos + Vector3(0, 0.2, 0)
	return b


func _tick() -> void:
	if _done:
		return
	elapsed += 1.0 / Engine.physics_ticks_per_second
	# сквозь-стены: центр бота строго внутри стенового AABB
	for i in bots.size():
		var b := bots[i]
		if b.hp <= 0:
			continue
		var p := b.global_position
		for wl in walls:
			if p.x > float(wl[0]) + 0.1 and p.z > float(wl[1]) + 0.1 and p.x < float(wl[2]) - 0.1 and p.z < float(wl[3]) - 0.1:
				if not _through_seen.has(i):
					_through_seen[i] = true
					through_walls += 1
	if elapsed >= seconds:
		_done = true
		_report()


func _report() -> void:
	var shots := 0
	var hits := 0
	var kills := 0
	var deaths := 0
	var stuck := 0
	for b in bots:
		shots += b.stat_shots
		hits += b.stat_hits
		kills += b.stat_kills
		deaths += b.stat_deaths
		stuck += b.stat_stuck_events
	var acc := (float(hits) / float(shots)) if shots > 0 else 0.0
	var c: Dictionary = Balance.BOT_PRESETS[preset]
	var acc_lo := float(c["pHitMin"]) * 0.6
	var acc_hi := float(c["pHitMax"]) * 1.15
	var fails: Array[String] = []
	if stuck > 0:
		fails.append("застревания: %d" % stuck)
	if through_walls > 0:
		fails.append("сквозь стены: %d" % through_walls)
	if shots < 20:
		fails.append("мало выстрелов: %d" % shots)
	elif acc < acc_lo or acc > acc_hi:
		fails.append("точность вне коридора: %.3f (%.3f..%.3f)" % [acc, acc_lo, acc_hi])
	var out := {
		"preset": preset, "seconds": seconds, "bots": bots.size(),
		"shots": shots, "hits": hits, "accuracy": acc,
		"kills": kills, "deaths": deaths,
		"stuck_events": stuck, "through_walls": through_walls,
		"pass": fails.is_empty(), "fails": fails,
	}
	print(JSON.stringify(out))
	quit(0 if fails.is_empty() else 1)
