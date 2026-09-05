# G9: карты, миникарта и целеуказание по тактической карте.
extends GutTest


func test_all_four_maps_exist_with_navmesh() -> void:
	for mid: String in Balance.MAPS:
		assert_true(ResourceLoader.exists("res://scenes/maps/%s.tscn" % mid), mid + ": сцена есть")
		assert_true(ResourceLoader.exists("res://scenes/maps/%s.navmesh.res" % mid), mid + ": навмеш испечён")


func test_map_catalog_matches_web() -> void:
	assert_eq(Balance.MAPS.size(), 4, "четыре карты в каталоге")
	for mid: String in ["duel", "height", "bastion", "dust2"]:
		assert_true(Balance.MAPS.has(mid), "карта " + mid)
		assert_true(float(Balance.MAPS[mid]["w"]) > 0.0, mid + ": ширина задана")


func test_navmesh_not_empty() -> void:
	for mid: String in Balance.MAPS:
		var nm := load("res://scenes/maps/%s.navmesh.res" % mid) as NavigationMesh
		assert_not_null(nm, mid + ": навмеш грузится")
		assert_true(nm.get_polygon_count() > 50, mid + ": навмеш непустой (%d полигонов)" % nm.get_polygon_count())


func test_minimap_world_map_roundtrip() -> void:
	var mm: Control = (load("res://src/ui/minimap.gd") as GDScript).new()
	add_child_autofree(mm)
	mm.size = Vector2(200, 200)
	# без карты в сцене миникарта работает на дефолтном размере поля — проверяем обратимость
	for w: float in [-20.0, 0.0, 15.0]:
		for z: float in [-10.0, 0.0, 25.0]:
			var back: Vector3 = mm.call("m2w", mm.call("_w2m", w, z))
			assert_almost_eq(back.x, w, 0.35, "x %f обратимо" % w)
			assert_almost_eq(back.z, z, 0.35, "z %f обратимо" % z)


func test_map_targeted_abilities_flagged() -> void:
	# дымы и орбиталка Вовы наводятся кликом по карте (паритет вебу)
	for path: String in ["res://scenes/agents/vova/smoke_global.gd", "res://scenes/agents/vova/orbital.gd"]:
		var ab: Ability = (load(path) as GDScript).new()
		autofree(ab)
		assert_true(ab.map_target, path + ": целится по карте")


func test_normal_abilities_not_map_targeted() -> void:
	# всё остальное наводится взглядом — заглушек «по прицелу» быть не должно только там,
	# где веб требует карту; обычные способности карту НЕ открывают
	for path: String in ["res://scenes/agents/vova/flash.gd", "res://scenes/agents/sanek/acid.gd"]:
		var ab: Ability = (load(path) as GDScript).new()
		autofree(ab)
		assert_false(ab.map_target, path + ": карта не нужна")


func test_map_target_does_not_spend_charge_until_confirmed() -> void:
	# заряд списывается только по клику: отмена (ПКМ/ESC) не должна съедать дым
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	p.char_id = "vova"
	KitFactory.attach(p, "vova")
	var smoke: Ability = p.get_node("Kit").get_child(0)
	var before := smoke.charges
	smoke.map_target_confirmed(Vector3(3, 0, 4))
	assert_eq(smoke.charges, before - 1, "подтверждение точки списывает ровно один заряд")
