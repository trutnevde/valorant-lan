# Оружейные формулы: детерминизм отдачи (сид), спад урона, разброс — паритет web weapons.js
extends GutTest

var player: FpsPlayer
var rig: WeaponRig


func before_each() -> void:
	player = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(player)
	rig = player.get_node("WeaponRig")


func _recoil_seq(seed_v: int, n: int) -> Array:
	rig.rng.seed = seed_v
	rig.spray_idx = 0
	player.punch_pitch = 0.0
	player.punch_yaw = 0.0
	player.pitch = 0.0
	player.aim_t = 0.0
	rig.equip("vandal")
	var out: Array = []
	for i in n:
		rig.apply_recoil()
		out.append([player.punch_pitch, player.punch_yaw])
	return out


func test_recoil_deterministic() -> void:
	var a := _recoil_seq(1337, 10)
	var b := _recoil_seq(1337, 10)
	for i in 10:
		assert_almost_eq(float(a[i][0]), float(b[i][0]), 0.000001, "kick детерминирован при том же сиде")
		assert_almost_eq(float(a[i][1]), float(b[i][1]), 0.000001, "drift детерминирован при том же сиде")


func test_recoil_grows_in_spray() -> void:
	var seq := _recoil_seq(42, 12)
	# суммарный подъём растёт: панч 10-й пули больше панча 1-й (первые мягче: 0.68 vs 0.92 + разгон)
	assert_gt(float(seq[9][0]) - float(seq[8][0]) + 0.0001, 0.0)
	assert_gt(float(seq[11][0]), float(seq[0][0]), "прицел уехал вверх за очередь")


func test_falloff() -> void:
	rig.equip("classic")  # falloffStart 20, falloffMin 0.8
	assert_almost_eq(rig.falloff_mult(10.0), 1.0, 0.001, "до falloffStart спада нет")
	assert_almost_eq(rig.falloff_mult(45.0), 0.8, 0.001, "к 45м спад до минимума")
	rig.equip("vandal")   # без falloff
	assert_almost_eq(rig.falloff_mult(60.0), 1.0, 0.001, "у Вандала спада нет")


func test_spread_crouch_and_air() -> void:
	rig.equip("vandal")
	player.aim_t = 0.0
	player.velocity = Vector3.ZERO
	player.crouch = true
	var s_crouch := rig.spread()
	player.crouch = false
	var s_stand := rig.spread()
	assert_almost_eq(s_crouch / s_stand, 0.65, 0.01, "присед сужает разброс на 35%")


func test_ammo_and_reload_time() -> void:
	rig.equip("vandal")
	assert_eq(int(rig.ammo["vandal"]["mag"]), 25)
	assert_eq(int(rig.ammo["vandal"]["reserve"]), 50)
	assert_almost_eq(float(Balance.WEAPONS["vandal"]["reload"]), 2.5, 0.001)
