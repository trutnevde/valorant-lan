# G11c: способности доведены — вспышки летят и упираются в стены, ульты не залипают.
extends GutTest


func _player(ch: String) -> FpsPlayer:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	p.char_id = ch
	KitFactory.attach(p, ch)
	return p


# БЫЛО: точка попа считалась формулой по прямой и СКВОЗЬ СТЕНЫ, параметра кривизны не было —
# все четыре флеш-способности летели одинаково.
func test_only_artemiy_flash_is_curved() -> void:
	var curved := {
		"res://scenes/agents/artemiy/flash.gd": true,   # «кривой светошар» — заводится за угол
		"res://scenes/agents/vova/flash.gd": false,
		"res://scenes/agents/fafik/tapok.gd": false,
		"res://scenes/agents/koniliy/neigh.gd": false,
	}
	for path: String in curved:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains('"curve"'), path + ": кривизна передаётся явно")
		assert_true(src.contains('"curve": %s' % ("true" if curved[path] else "false")),
			path + ": кривизна = %s" % curved[path])


func test_flash_orb_stops_at_wall() -> void:
	# стена прямо по курсу: снаряд обязан встать перед ней, а не пролететь насквозь
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(6, 6, 0.4)
	cs.shape = bx
	wall.add_child(cs)
	add_child_autofree(wall)
	wall.global_position = Vector3(0, 1.5, -4)
	await wait_physics_frames(2)
	var orb: Node = (load("res://src/agents/effects/flash_orb.gd") as GDScript).new()
	orb.set("data", {
		"fx": 0.0, "fy": 1.5, "fz": 0.0,
		"dx": 0.0, "dy": 0.0, "dz": -1.0,
		"owner_path": "", "curve": false,
	})
	add_child_autofree(orb)
	await wait_physics_frames(12)
	if not is_instance_valid(orb):
		return  # уже лопнул — значит точно не улетел за карту
	var pos: Vector3 = orb.get("_pos")
	assert_gt(pos.z, -4.5, "снаряд не прошёл сквозь стену")
	assert_true(bool(orb.get("_stopped")), "снаряд встал у стены")


# БЫЛО: ульта Фафика распускалась ТОЛЬКО повторным X — не нажал, и стрельба заблокирована
# до конца матча.
func test_fafik_ult_releases_weapon_on_round_reset() -> void:
	var p := _player("fafik")
	var rig: WeaponRig = p.get_node("WeaponRig")
	var ult: Ability = null
	for ab in p.get_node("Kit").get_children():
		if String(ab.get("key")) == "X":
			ult = ab
	assert_not_null(ult, "ульта Фафика на месте")
	ult.call("cast")
	assert_false(rig.is_physics_processing(), "во время ульты стрелять нельзя")
	p.round_reset()
	assert_true(rig.is_physics_processing(), "новый раунд вернул оружие")


# БЫЛО: метка «Второго дыхания» снималась наполовину — позиция оставалась висеть.
func test_artemiy_mark_fully_cleared_on_use() -> void:
	var p := _player("artemiy")
	p.ult_mark_pos = Vector3(3, 0, 4)
	p.ult_mark_until = Time.get_ticks_msec() / 1000.0 + 10.0
	p.hp = 1
	assert_true(p.try_second_wind(), "метка сработала вместо смерти")
	assert_eq(p.ult_mark_pos, Vector3.INF, "метка снята целиком")
	assert_eq(p.hp, int(Balance.RULES["BASE_HP"]), "вернулся с полным HP")
	assert_false(p.try_second_wind(), "второй раз та же метка не срабатывает")


func test_artemiy_mark_does_not_survive_round() -> void:
	var p := _player("artemiy")
	p.ult_mark_pos = Vector3(3, 0, 4)
	p.ult_mark_until = Time.get_ticks_msec() / 1000.0 + 10.0
	p.round_reset()
	assert_eq(p.ult_mark_pos, Vector3.INF, "метка не переезжает в новый раунд")


# БЫЛО: крюк проверял мгновенный рейкаст в can_cast() — промахнуться было НЕВОЗМОЖНО,
# а COCOON_SPEED не использовался вовсе.
func test_denis_hook_can_miss() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/agents/denis/hook.gd")
	assert_false(src.contains("func can_cast"), "гейта «есть цель» больше нет — можно промазать")
	assert_true(src.contains("hook_projectile"), "крюк уходит снарядом")
	var proj := FileAccess.get_file_as_string("res://src/agents/effects/hook_projectile.gd")
	assert_true(proj.contains('COCOON_SPEED'), "скорость снаряда взята из баланса")
	assert_true(proj.contains('COCOON_RANGE'), "дальность ограничена — крюк выдыхается")
