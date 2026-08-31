# Кит-каркас G6a: фабрика собирает китов, заряды из balance.gd, буст/ножи работают.
extends GutTest

var player: FpsPlayer


func _make_player(char_id: String) -> FpsPlayer:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	p.char_id = char_id
	KitFactory.attach(p, char_id)
	return p


func test_kit_factory_counts() -> void:
	for ch in ["max", "artemiy", "fafik"]:
		var p := _make_player(ch)
		assert_eq(p.get_node("Kit").get_child_count(), 4, ch + ": 4 способности в ките")


func test_charges_from_balance() -> void:
	var p := _make_player("artemiy")
	var flash: Ability = p.get_node("Kit").get_child(0)
	assert_eq(flash.charges, int(Balance.CHARACTERS["artemiy"]["abilities"]["C"]["charges"]), "заряды Вспышки из balance")


func test_boost_speeds_up() -> void:
	var p := _make_player("max")
	p.weapon_speed = 1.0
	p.aim_t = 0.0
	var base := p.max_speed()
	p.boost_until = Time.get_ticks_msec() / 1000.0 + 4.0
	assert_almost_eq(p.max_speed() / base, float(Balance.ABILITY["BOOST_MUL"]), 0.001, "Порыв ×1.4")


func test_knives_numbers() -> void:
	var p := _make_player("max")
	var rig := p.get_node("WeaponRig") as WeaponRig
	rig.start_knives()
	assert_true(rig.knives_active())
	assert_eq(rig.knives_count, int(Balance.ABILITY["KNIVES_COUNT"]))
	assert_eq(int(Balance.ABILITY["KNIFE_DMG"]), 70)
	assert_eq(int(Balance.ABILITY["KNIFE_HEAD"]), 150)


func test_second_wind_revives() -> void:
	var p := _make_player("artemiy")
	p.hp = 10
	p.ult_mark_pos = Vector3(3, 0.1, 3)
	p.ult_mark_until = Time.get_ticks_msec() / 1000.0 + 5.0
	p.take_hit(50, "body")
	assert_eq(p.hp, int(Balance.RULES["BASE_HP"]), "Второе дыхание вернуло полный HP вместо смерти")
	assert_almost_eq(p.global_position.x, 3.0, 0.1, "вернулся на метку")
	assert_lt(p.ult_mark_until, 1.0, "метка потрачена")
