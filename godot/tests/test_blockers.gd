# Сторожа блокирующих пробелов, найденных аудитом паритета перед v1.0.0.
# Каждый тест здесь ловит баг, который РЕАЛЬНО был в порте и делал механику нерабочей.
extends GutTest


func _player(ch := "artemiy") -> FpsPlayer:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	p.char_id = ch
	KitFactory.attach(p, ch)
	return p


# БЫЛО: капсула движения Col — первый шейп и на высоте головы шире сферы головы, поэтому
# part_at по индексу шейпа ВСЕГДА возвращал «body». Хедшоты не работали ни разу.
func test_headshot_zone_by_height() -> void:
	var p := _player()
	p.global_position = Vector3.ZERO
	assert_eq(p.part_at(0, 1.70), "head", "попадание на высоте 1.70 — голова")
	assert_eq(p.part_at(0, 1.55), "head", "1.55 — ещё голова")
	assert_eq(p.part_at(0, 1.10), "body", "1.10 — корпус")
	assert_eq(p.part_at(0, 0.40), "leg", "0.40 — ноги")


func test_headshot_zone_follows_body_position() -> void:
	# зона считается ОТНОСИТЕЛЬНО ног, иначе на возвышении хедшоты снова сломаются
	var p := _player()
	p.global_position = Vector3(0, 3.0, 0)
	assert_eq(p.part_at(0, 4.70), "head", "на платформе голова тоже голова")
	assert_eq(p.part_at(0, 3.40), "leg", "и ноги тоже ноги")


func test_bot_headshot_zone() -> void:
	var b: Bot = (load("res://scenes/bots/bot.tscn") as PackedScene).instantiate()
	add_child_autofree(b)
	b.global_position = Vector3.ZERO
	assert_eq(b.part_at(0, 1.70), "head", "бот: голова")
	assert_eq(b.part_at(0, 1.10), "body", "бот: корпус")


# БЫЛО: заряды выдавались только в Ability._ready, то есть один раз за матч.
func test_ability_charges_restored_each_round() -> void:
	var p := _player()
	var ab: Ability = p.get_node("Kit").get_child(0)
	var full := ab.charges
	assert_gt(full, 0, "заряды выданы на старте")
	ab.charges = 0
	p.round_reset()
	assert_eq(ab.charges, full, "новый раунд вернул заряды")


# БЫЛО: reset_loadout() не вызывался НИОТКУДА — купленное оружие и пустой резерв
# оставались до конца матча.
func test_loadout_reset_each_round() -> void:
	var p := _player()
	var rig: WeaponRig = p.get_node("WeaponRig")
	rig.give_weapon("vandal")
	assert_eq(rig.current_id, "vandal", "оружие выдано")
	p.round_reset()
	assert_eq(rig.current_id, "classic", "новый раунд — снова стартовый пистолет")
	assert_eq(String(rig.loadout["primary"]), "", "основной слот пуст")


# БЫЛО: стрелять и кастовать можно было мёртвым, в стане и на тяге.
func test_cannot_act_when_dead_or_stunned() -> void:
	var p := _player()
	assert_true(p.can_act(), "живой и свободный — может")
	p.dead = true
	assert_false(p.can_act(), "мёртвый не может")
	p.dead = false
	p.apply_stun(2.0)
	assert_false(p.can_act(), "в стане не может")


func test_cannot_act_while_pulled() -> void:
	var p := _player()
	p.force_pull(Vector3(5, 0, 5), 2.0, 6.0)
	assert_false(p.can_act(), "на тяге кокона/крюка не может")


# БЫЛО: CC переезжали в новый раунд.
func test_round_reset_clears_cc() -> void:
	var p := _player()
	p.apply_stun(5.0)
	p.apply_blind(5.0)
	p.apply_slow(0.5, 5.0)
	p.round_reset()
	assert_true(p.can_act(), "после раунд-ресета контроль снят")


# БЫЛО: в advance() для MATCH_END стоял `_: pass` — игра зависала после победного раунда.
func test_match_end_is_not_dead_end() -> void:
	var mt := Match.new()
	add_child_autofree(mt)
	mt.phase = Match.Phase.MATCH_END
	mt.score = { "A": 5, "B": 2 }
	mt.round_no = 9
	mt.deadline = mt.now() + 0.1
	mt.advance(0.2)
	assert_ne(mt.phase, Match.Phase.MATCH_END, "матч не заперся навсегда")
	assert_eq(mt.round_no, 1, "начался новый матч с первого раунда")
	assert_eq(int(mt.score["A"]), 0, "счёт обнулён")
