# Скорости движения игрока = balance.gd (паритет web player.js)
extends GutTest

var player: FpsPlayer


func before_each() -> void:
	player = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(player)


func test_run_speed() -> void:
	player.crouch = false
	player.walk = false
	player.aim_t = 0.0
	player.speed_factor = 1.0
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["RUN_SPEED"]), 0.001)


func test_walk_speed() -> void:
	player.walk = true
	player.crouch = false
	player.aim_t = 0.0
	player.speed_factor = 1.0
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["WALK_SPEED"]), 0.001)


func test_crouch_speed() -> void:
	player.crouch = true
	player.aim_t = 0.0
	player.speed_factor = 1.0
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["CROUCH_SPEED"]), 0.001)


func test_ads_slows() -> void:
	player.crouch = false
	player.walk = false
	player.speed_factor = 1.0
	player.aim_t = 1.0
	# прицеливание замедляет на 42% (web player.js:151)
	assert_almost_eq(player.max_speed(), float(Balance.MOVE["RUN_SPEED"]) * (1.0 - 0.42), 0.001)


func test_knife_speed_factor() -> void:
	var rig: WeaponRig = player.get_node("WeaponRig")
	rig.equip("knife")
	assert_almost_eq(player.speed_factor, 1.10, 0.001, "с ножом бегаешь быстрее")
	rig.equip("operator")
	assert_almost_eq(player.speed_factor, 0.88, 0.001, "Оператор превращает в шкаф")
