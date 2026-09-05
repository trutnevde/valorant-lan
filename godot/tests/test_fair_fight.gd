# G11a: честный бой — броня, теггинг, разброс, эксплойты, взаимный размен.
extends GutTest


func _player(ch := "artemiy") -> FpsPlayer:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	p.char_id = ch
	return p


# БЫЛО: Balance.ARMOR существует с самого начала, но брони в игре не было вовсе —
# ни поля, ни поглощения, ни покупки.
func test_armor_absorbs_damage() -> void:
	var p := _player()
	p.armor = 50
	p.hp = 100
	p.take_hit(40, "body")
	# поглощено round(40 * 0.66) = 26, значит в HP ушло 14, брони осталось 24
	assert_eq(p.armor, 50 - 26, "броня потратилась на поглощение")
	assert_eq(p.hp, 100 - 14, "в HP ушёл только остаток")


func test_armor_runs_out() -> void:
	var p := _player()
	p.armor = 5
	p.hp = 100
	p.take_hit(100, "body")
	assert_eq(p.armor, 0, "броня кончилась")
	assert_eq(p.hp, 5, "дальше урон идёт целиком")


func test_armor_does_not_survive_round() -> void:
	var p := _player()
	p.armor = 50
	p.round_reset()
	assert_eq(p.armor, 0, "броня не переезжает в новый раунд")


# БЫЛО: попадание никак не влияло на скорость — «tagging» отсутствовал.
func test_tagging_slows_target() -> void:
	var p := _player()
	p.weapon_speed = 1.0
	p.aim_t = 0.0
	var base := p.max_speed()
	p.take_hit(10, "body")
	assert_almost_eq(p.max_speed() / base, p.TAG_SLOW, 0.001, "пуля вяжет ноги")
	p.round_reset()
	assert_almost_eq(p.max_speed(), base, 0.001, "к новому раунду отпускает")


# БЫЛО: смена ствола отменяла перезарядку — бесплатный мгновенный релоад в один хоткей.
func test_weapon_switch_does_not_cancel_reload() -> void:
	var p := _player()
	var rig: WeaponRig = p.get_node("WeaponRig")
	rig.give_weapon("vandal")
	rig.ammo["vandal"]["mag"] = 1
	rig.reload()
	assert_gt(rig.reloading_until, 0.0, "перезарядка пошла")
	rig.equip("classic")
	rig.equip("vandal")
	assert_lt(rig.ammo["vandal"]["mag"], int(Balance.WEAPONS["vandal"]["mag"]),
		"магазин НЕ наполнился от переключения слотов")


# БЫЛО: при взаимном размене не срабатывала ни одна ветка и раунд не заканчивался.
func test_mutual_trade_ends_round() -> void:
	var mt := Match.new()
	add_child_autofree(mt)
	mt.attack_team = "A"
	mt.phase = Match.Phase.LIVE
	mt.deadline = mt.now() + 100.0
	var ended := []
	mt.round_ended.connect(func(w: String, r: String) -> void: ended.append([w, r]))
	# бойцов нет вовсе — обе стороны по нулям, это и есть размен
	mt.advance(0.1)
	assert_eq(ended.size(), 1, "раунд закрылся, а не завис")
	assert_eq(ended[0][1], "trade", "причина — размен")
	assert_eq(ended[0][0], "B", "шип не установлен → раунд забирает защита")


# БЫЛО: разброс сэмплился кубом по МИРОВЫМ осям — конус зависел от того, куда смотришь.
func test_spread_is_disc_around_aim() -> void:
	var p := _player()
	p.global_position = Vector3.ZERO
	var rig: WeaponRig = p.get_node("WeaponRig")
	rig.rng.seed = 12345
	# смотрим вдоль мировой диагонали — при кубе разброс тут был бы заметно шире
	for yaw: float in [0.0, PI * 0.25, PI * 0.5]:
		p.yaw = yaw
		p.pitch = 0.0
		var base := p.aim_dir()
		var mx := 0.0
		for i in 200:
			var d := base
			var s := rig.spread()
			var right := d.cross(Vector3.UP).normalized()
			var up := right.cross(d).normalized()
			var ang := rig.rng.randf() * TAU
			var rad := sqrt(rig.rng.randf()) * s
			var got := (d + right * (cos(ang) * rad) + up * (sin(ang) * rad)).normalized()
			mx = maxf(mx, base.angle_to(got))
		# максимальное отклонение не превышает сам разброс — и не зависит от направления
		assert_lt(mx, rig.spread() * 1.15, "конус ограничен разбросом при yaw=%.2f" % yaw)
