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
	# ФИЛЬТРЫ СПАНОВ (по умолчанию выключены!). Без них площадка ПОД сплошной коробкой
	# остаётся ходибельной: путь ведёт внутрь ящика, тело упирается — бот виснет.
	navmesh.filter_walkable_low_height_spans = true  # режет всё, где просвет < agent_height
	navmesh.filter_low_hanging_obstacles = true
	navmesh.filter_ledge_spans = true

	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, src, map_root)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
	# КАРВИНГ НУТРА СПЛОШНЫХ БОКСОВ. Recast растеризует боксы как оболочку: внутри
	# получается «комната» (пол на y~0.2, потолок — верх бокса), фильтр просвета её не
	# режет, и бот строит путь сквозь ящик, упираясь телом. Вырезаем такие полигоны по
	# solids_aabb из меты карты — детерминированно и проверяемо (tools/navcheck.gd).
	var carved := _carve_solids(navmesh, map_root)
	print("bake_navmesh: полигонов=", navmesh.get_polygon_count(), " (вырезано внутри боксов: ", carved, ")")
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


func _carve_solids(navmesh: NavigationMesh, map_root: Node) -> int:
	var meta = JSON.parse_string(String(map_root.get_meta("map_meta", "{}")))
	if not (meta is Dictionary) or not meta.has("solids_aabb"):
		return 0
	var solids: Array = meta["solids_aabb"]
	var verts := navmesh.get_vertices()
	var keep: Array = []
	var dropped := 0
	for i in navmesh.get_polygon_count():
		var poly := navmesh.get_polygon(i)
		var c := Vector3.ZERO
		var ymax := -1e9
		for vi in poly:
			c += verts[vi]
			ymax = maxf(ymax, verts[vi].y)
		c /= poly.size()
		var inside := false
		for w: Array in solids:
			var top: float = float(w[4]) if w.size() > 4 else 3.0
			if ymax >= top - 0.3:
				continue                      # это верх бокса — законная площадка, не трогаем
			if not (c.x > float(w[0]) and c.x < float(w[2]) and c.z > float(w[1]) and c.z < float(w[3])):
				continue
			# режем ТОЛЬКО полигон целиком внутри бокса: иначе снесём полигон пола,
			# который просто огибает ящик (и рядом с ящиком образуется прореха)
			var all_in := true
			for vi2 in poly:
				var v := verts[vi2]
				if v.x < float(w[0]) - 0.05 or v.x > float(w[2]) + 0.05 or v.z < float(w[1]) - 0.05 or v.z > float(w[3]) + 0.05:
					all_in = false
					break
			if all_in:
				inside = true
				break
		if inside:
			dropped += 1
		else:
			keep.append(poly)
	if dropped == 0:
		return 0
	navmesh.clear_polygons()
	for poly: PackedInt32Array in keep:
		navmesh.add_polygon(poly)
	return dropped
