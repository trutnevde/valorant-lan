# Бейк навмеша карты headless (система движка, не самопал):
#   godot --headless --path . -s res://tools/bake_navmesh.gd -- --map=duel
# Читает scenes/maps/<map>.tscn, бейкает NavigationMesh по геометрии, сохраняет .navmesh.res
# и прописывает его в NavigationRegion3D сцены.
extends SceneTree


func _initialize() -> void:
	var map_id := "duel"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			map_id = arg.substr(6)
	var scene_path := "res://scenes/maps/%s.tscn" % map_id
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("bake_navmesh: не загрузилась " + scene_path)
		quit(1)
		return
	var map_root := packed.instantiate()
	root.add_child(map_root)
	await process_frame  # нода должна войти в дерево до парсинга геометрии
	await process_frame

	var navmesh := NavigationMesh.new()
	# агент = капсула из Balance (0.38) + ЗАПАС 0.14: пути держат отступ от углов стен,
	# иначе боты срезают угол впритык и скребут его (RVO против угла = стак)
	navmesh.agent_radius = float(Balance.MOVE["RADIUS"]) + 0.14
	navmesh.agent_height = float(Balance.MOVE["HEIGHT"])
	navmesh.agent_max_climb = float(Balance.MOVE["STEP_UP"])
	navmesh.agent_max_slope = 60.0
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.15
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS

	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, src, map_root)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
	print("bake_navmesh: полигонов=", navmesh.get_polygon_count())
	if navmesh.get_polygon_count() == 0:
		push_error("bake_navmesh: пустой навмеш")
		quit(1)
		return

	var res_path := "res://scenes/maps/%s.navmesh.res" % map_id
	var err := ResourceSaver.save(navmesh, res_path)
	if err != OK:
		push_error("bake_navmesh: сохранение упало err=" + str(err))
		quit(1)
		return

	# прописать ресурс в NavigationRegion3D сцены и пересохранить .tscn
	var nav := map_root.get_node("Nav") as NavigationRegion3D
	nav.navigation_mesh = load(res_path)
	if map_root.get_parent():
		map_root.get_parent().remove_child(map_root)
	var repacked := PackedScene.new()
	repacked.pack(map_root)
	err = ResourceSaver.save(repacked, scene_path)
	print("bake_navmesh: ", "OK " + res_path if err == OK else "FAIL пересохранение err=" + str(err))
	quit(0 if err == OK else 1)
