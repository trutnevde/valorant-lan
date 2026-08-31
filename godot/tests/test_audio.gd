# G8: звук — шины, регистрация окклюзии, one-shot.
extends GutTest


func test_buses_exist() -> void:
	for b: String in ["Master", "SFX", "Steps", "Voice", "UI", "Muffled", "Reverb"]:
		assert_true(AudioServer.get_bus_index(b) >= 0, "шина " + b)


func test_muffled_has_lowpass() -> void:
	var mi := AudioServer.get_bus_index("Muffled")
	var found := false
	for e in AudioServer.get_bus_effect_count(mi):
		if AudioServer.get_bus_effect(mi, e) is AudioEffectLowPassFilter:
			found = true
	assert_true(found, "Muffled несёт low-pass")


func test_register_sets_group_and_bus() -> void:
	var p := AudioStreamPlayer3D.new()
	add_child_autofree(p)
	get_node("/root/Ears").call("register", p, "Steps")
	assert_eq(p.bus, "Steps", "домашняя шина проставлена")
	assert_true(p.is_in_group("spatial_sfx"), "в группе окклюзии")
	assert_eq(String(p.get_meta("home_bus")), "Steps")


func test_one_shot_spawns_and_autofrees() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var stream := load("res://assets/audio/pop.ogg") as AudioStream
	get_node("/root/Ears").call("one_shot", parent, Vector3(1, 0, 2), stream, "SFX", 1.0, -3.0)
	assert_eq(parent.get_child_count(), 1, "звук-нода создана")
	var sp := parent.get_child(0) as AudioStreamPlayer3D
	assert_not_null(sp, "это AudioStreamPlayer3D")
	assert_true(sp.is_in_group("spatial_sfx"), "зарегистрирован в окклюзии")
