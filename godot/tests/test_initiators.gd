# G6b: дымовой мир, трупы/Кровопир, киты инициаторов, числа из balance.
extends GutTest


func _sw() -> Node:
	return get_node("/root/Smokes")


func before_each() -> void:
	(_sw().get("smokes") as Array).clear()
	(_sw().get("no_smoke_zones") as Array).clear()


func test_smoke_blocks_segment() -> void:
	_sw().call("add_smoke", Vector3(5, 0, 0), "A", false)
	assert_true(bool(_sw().call("seg_blocked", Vector3(0, 1.5, 0), Vector3(10, 1.5, 0))), "дым режет LOS")
	assert_false(bool(_sw().call("seg_blocked", Vector3(0, 1.5, 8), Vector3(10, 1.5, 8))), "мимо дыма — видно")


func test_dispel_removes_enemy_smokes_only() -> void:
	_sw().call("add_smoke", Vector3(5, 0, 0), "A", false)
	_sw().call("add_smoke", Vector3(6, 0, 0), "B", false)
	var removed: Array = _sw().call("dispel", Vector3(5, 0, 0), "B")  # Гера команды B
	assert_eq(removed.size(), 1, "убран только вражеский (A) дым")
	assert_eq((_sw().get("smokes") as Array).size(), 1, "свой дым остался")


func test_dispel_blocks_new_enemy_smoke() -> void:
	_sw().call("dispel", Vector3(0, 0, 0), "B")
	assert_false(bool(_sw().call("add_smoke", Vector3(1, 0, 1), "A", false)), "вражеский дым в зоне блока не встаёт")
	assert_true(bool(_sw().call("add_smoke", Vector3(1, 0, 1), "B", true)), "свой — можно")


func test_point_in_smoke() -> void:
	_sw().call("add_smoke", Vector3(3, 0, 3), "A", true)
	assert_true(bool(_sw().call("point_in_smoke", Vector3(3.5, 1, 3))), "внутри")
	assert_false(bool(_sw().call("point_in_smoke", Vector3(30, 1, 30))), "снаружи")


func test_corpse_near_enemy_only() -> void:
	var mt := autofree(Match.new()) as Match
	add_child(mt)
	mt.corpses.append({ "pos": Vector3(2, 0, 2), "team": "B", "until": mt.now() + 10.0 })
	assert_true(mt.corpse_near(Vector3(2.5, 0, 2), "A", 3.6), "Денис-A ест у трупа врага-B")
	assert_false(mt.corpse_near(Vector3(2.5, 0, 2), "B", 3.6), "у своего трупа не ест")
	mt.queue_free()


func test_initiator_kits() -> void:
	for ch in ["denis", "sova", "gera"]:
		var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
		add_child_autofree(p)
		p.char_id = ch
		KitFactory.attach(p, ch)
		assert_eq(p.get_node("Kit").get_child_count(), 4, ch + ": 4 способности")


func test_bloodfeast_numbers() -> void:
	assert_eq(int(Balance.ABILITY["BLOODFEAST_INSTANT"]), 30)
	assert_eq(int(Balance.ABILITY["BLOODFEAST_FED"]), 62)
	assert_almost_eq(float(Balance.ABILITY["GERA_SMOKE_DMG_MUL"]), 1.15, 0.001)
	assert_eq(int(Balance.ABILITY["SOVA_FURY_WAVES"]), 3)
