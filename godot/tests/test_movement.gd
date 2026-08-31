# Скорости движения игрока = balance.gd (паритет web player.js).
# База — Артемий (speedMul 1.0); пассивка Макса (×1.05) — отдельным тестом.
extends GutTest

var player: FpsPlayer


func before_each() -> void:
	player = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(player)
	player.char_id = "artemiy"
	player.weapon_speed = 1.0
	player.speed_factor = 1.0
	player.aim_t = 0.0
	player.crouch = false
	player.walk = false


func test_run_speed() -> void:
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["RUN_SPEED"]), 0.001)


func test_walk_speed() -> void:
	player.walk = true
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["WALK_SPEED"]), 0.001)


func test_crouch_speed() -> void:
	player.crouch = true
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["CROUCH_SPEED"]), 0.001)


func test_ads_slows() -> void:
	player.aim_t = 1.0
	# прицеливание замедляет на 42% (web player.js:151)
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["RUN_SPEED"]) * (1.0 - 0.42), 0.001)


func test_max_passive_speed() -> void:
	player.char_id = "max"
	# пассивка Макса «Ветер»: speedMul из Balance.CHARACTERS
	var mul := float(Balance.CHARACTERS["max"]["speedMul"])
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["RUN_SPEED"]) * mul, 0.001)


func test_knife_speed_factor() -> void:
	var rig: WeaponRig = player.get_node("WeaponRig")
	rig.equip("knife")
	assert_almost_eq(player.weapon_speed, 1.10, 0.001, "с ножом бегаешь быстрее")
	rig.equip("operator")
	assert_almost_eq(player.weapon_speed, 0.88, 0.001, "Оператор превращает в шкаф")
