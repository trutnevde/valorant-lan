# G11d: боты применяют ульты, слух по канону, спектатор после смерти.
extends GutTest


func _bot(ch: String, tm := "B") -> Bot:
	var b: Bot = (load("res://scenes/bots/bot.tscn") as PackedScene).instantiate()
	add_child_autofree(b)
	b.char_id = ch
	b.team = tm
	return b


# БЫЛО: боты не применяли ульту НИ РАЗУ — заряд копился и лежал мёртвым грузом.
func test_bots_spend_ultimate() -> void:
	var fx := get_node("/root/Fx")
	for ch: String in ["artemiy", "vova", "sanek", "koniliy", "ira", "denis", "gera"]:
		var b := _bot(ch)
		var victim := _bot("max", "A")
		victim.global_position = Vector3(0, 0, 6)
		b.ult = int(Balance.CHARACTERS[ch]["ultCost"])
		b.target = victim
		var spent: bool = b._try_ult(1.0, true, fx)
		assert_true(spent, ch + ": ульта применена")
		assert_eq(b.ult, 0, ch + ": заряд потрачен")


func test_bots_without_ult_charge_do_not_cast() -> void:
	var b := _bot("sanek")
	b.ult = 0
	assert_false(b._try_ult(1.0, false, get_node("/root/Fx")), "без заряда ульты нет")


# ЧЕСТНО: у троих ульта не реализована — тест фиксирует это как ИЗВЕСТНОЕ, чтобы не забыть.
func test_known_bots_without_ultimate() -> void:
	for ch: String in ["max", "fafik", "sova"]:
		var b := _bot(ch)
		b.ult = int(Balance.CHARACTERS[ch]["ultCost"])
		assert_false(b._try_ult(1.0, false, get_node("/root/Fx")),
			ch + ": ульта бота пока не реализована (см. PARITY.md)")


# БЫЛО: плоский радиус 28 на всё — шаги слышны вдвое дальше канона, выстрел игрока не шумел.
func test_hearing_range_depends_on_loudness() -> void:
	var b := _bot("sanek", "B")
	b.global_position = Vector3.ZERO
	var enemy := _bot("max", "A")
	var mul := float(b.cfg()["hearMul"])
	# шаг за 20 м — слишком далеко (порог 14), выстрел оттуда же — слышно (порог 28)
	enemy.global_position = Vector3(0, 0, 20.0 * mul)
	b.heard_until = -99.0
	b._on_noise(false, enemy)
	assert_lt(b.heard_until, 0.0, "шаг за 20 м не слышен")
	b._on_noise(true, enemy)
	assert_gt(b.heard_until, 0.0, "выстрел за 20 м слышен")


func test_player_shot_makes_noise() -> void:
	# выстрел игрока обязан шуметь, иначе боты не реагируют на пальбу вовсе
	var src := FileAccess.get_file_as_string("res://src/core/weapon.gd")
	assert_true(src.contains("made_noise.emit(true)"), "выстрел эмитит громкий шум")
	var psrc := FileAccess.get_file_as_string("res://src/core/player.gd")
	assert_true(psrc.contains("signal made_noise(loud: bool)"), "сигнал несёт громкость")
