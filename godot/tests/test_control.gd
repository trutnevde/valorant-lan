# G6c: киты контроля/стражей + ПОЛНЫЙ ростер 10/10 собирается фабрикой.
extends GutTest


func test_all_ten_kits() -> void:
	for ch: String in Balance.CHARACTERS:
		var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
		add_child_autofree(p)
		p.char_id = ch
		KitFactory.attach(p, ch)
		assert_eq(p.get_node("Kit").get_child_count(), 4, ch + ": 4 способности (паритет всех десяти)")


# Сторож интерфейса: HUD-панель способностей (G9) читает `key` у каждого ребёнка Kit.
# Компонент старого образца (extends Node со своим вводом) роняет её — так и случилось
# с Рывком и Взлётом Макса, найдено смоук-стартом после восстановления копии.
func test_all_ability_components_share_interface() -> void:
	for ch: String in Balance.CHARACTERS:
		var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
		add_child_autofree(p)
		p.char_id = ch
		KitFactory.attach(p, ch)
		var keys: Array = []
		for ab in p.get_node("Kit").get_children():
			assert_true(ab is Ability, "%s/%s: компонент должен быть Ability" % [ch, ab.name])
			var k := String(ab.get("key"))
			assert_true(k in ["C", "Q", "E", "X"], "%s/%s: key=%s вне C/Q/E/X" % [ch, ab.name, k])
			assert_eq(String(ab.get("char_id")), ch, "%s/%s: char_id совпадает" % [ch, ab.name])
			keys.append(k)
		keys.sort()
		assert_eq(keys, ["C", "E", "Q", "X"], ch + ": ровно по одному C/Q/E/X")


func test_gallop_and_banquet_speed() -> void:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	p.char_id = "koniliy"
	p.weapon_speed = 1.0
	p.aim_t = 0.0
	var base := p.max_speed()
	p.gallop_until = Time.get_ticks_msec() / 1000.0 + 3.0
	assert_almost_eq(p.max_speed() / base, float(Balance.ABILITY["GALLOP_MUL"]), 0.001, "галоп ×1.5")
	p.gallop_until = 0.0
	p.banquet_until = Time.get_ticks_msec() / 1000.0 + 3.0
	assert_almost_eq(p.max_speed() / base, float(Balance.ABILITY["BANQUET_SPEED"]), 0.001, "банкет ×1.15")


func test_slow_applies() -> void:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	p.char_id = "artemiy"
	p.weapon_speed = 1.0
	var base := p.max_speed()
	p.apply_slow(float(Balance.ABILITY["ACID_SLOW"]), 2.0)
	assert_almost_eq(p.max_speed() / base, float(Balance.ABILITY["ACID_SLOW"]), 0.001, "кислота ×0.7")


func test_control_numbers() -> void:
	assert_eq(int(Balance.ABILITY["TURRET_HP"]), 60)
	assert_almost_eq(float(Balance.ABILITY["TURRET_TICK"]), 0.5, 0.001)
	assert_eq(int(Balance.ABILITY["ORBITAL_DPS"]), 40)
	assert_eq(int(Balance.ABILITY["BUFFET_HEAL"]), 50)
	assert_almost_eq(float(Balance.ABILITY["STAMPEDE_STUN"]), 1.4, 0.001)
	assert_eq(int(Balance.ABILITY["IRA_CORPSE_RATE"]), 14)
