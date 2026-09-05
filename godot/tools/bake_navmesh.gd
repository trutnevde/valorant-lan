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
	_mark_solid_volumes(map_root, src)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
	print("bake_navmesh: полигонов после бейка=", navmesh.get_polygon_count())
	if navmesh.get_polygon_count() == 0:
		push_error("bake_navmesh: пустой навмеш")
		quit(1)
		return
	if not _keep_reachable(navmesh, map_root):
		quit(1)
		return
	print("bake_navmesh: полигонов=", navmesh.get_polygon_count())

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


# Recast растеризует ПОВЕРХНОСТИ, а не объёмы. У сплошного бокса нижняя грань ложится в
# хайтфилд как обычный «пол», а ближайший спан над ней — верхняя грань того же бокса, в
# 2.6 м выше. Просвет больше роста агента, поэтому низкий спан не отфильтровывается, и
# внутри платформы остаётся ходибельный «этаж». У широких тел (центральный бастион 12×9,
# платформа «Высоты») он переживает эрозию и становится ОСТРОВОМ навмеша внутри стены:
# NavigationServer прокладывал по нему путь, бот упирался в бок платформы и стоял там,
# пока не срабатывал watchdog (это и были застревания в ботматче).
# Лечим движковым API: объём каждого сплошного бокса помечаем препятствием. Верхнюю грань
# не трогаем (обрезаем на клетку ниже), чтобы крыши платформ остались ходибельными.
func _mark_solid_volumes(map_root: Node, src: NavigationMeshSourceGeometryData3D) -> void:
	const TOP_KEEP := 0.16  # чуть больше cell_height: верхний спан остаётся ходибельным
	var marked := 0
	for n in map_root.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		var body := cs.get_parent() as StaticBody3D
		if body == null or not body.is_in_group("map_solid"):
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			push_warning("bake_navmesh: не бокс, объём не помечен: " + String(body.name))
			continue
		var t := cs.global_transform
		var e := box.size * 0.5
		var top := t.origin.y + e.y
		if top <= 0.05:
			continue  # пол карты — его верхняя грань и есть земля, резать нечего
		var bottom := t.origin.y - e.y - 0.2  # с запасом вниз, чтобы поймать нижнюю грань
		var height := (top - TOP_KEEP) - bottom
		if height <= 0.0:
			continue
		var outline := PackedVector3Array()
		for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			outline.append(t * Vector3(s.x * e.x, 0.0, s.y * e.z))
		# carve=false — препятствие эродируется на agent_radius, как и сама геометрия,
		# то есть привычный отступ путей от углов сохраняется
		src.add_projected_obstruction(outline, bottom, height, false)
		marked += 1
	print("bake_navmesh: помечено сплошных объёмов=", marked)


# Крыши ящиков и парапеты, куда пешком не подняться, Recast всё равно делает ходибельными —
# получаются ОСТРОВА навмеша, оторванные от пола. Беда не в самих островах, а в том, что
# NavigationServer проецирует на них цели: центр сайта на «Бастионе» лежит внутри ящика, а
# центр карты — внутри центральной платформы, и ближайшим полигоном к такой точке
# оказывается КРЫША. Путь целиком укладывался на остров-крышу, бот на земле шёл на первую
# путевую точку — то есть прямо в бок платформы, — и стоял там до watchdog.
# Оставляем в навмеше только область, связную со спавнами: тогда любая цель проецируется
# на пол, по которому бот действительно может дойти.
func _keep_reachable(navmesh: NavigationMesh, map_root: Node) -> bool:
	var verts := navmesh.get_vertices()
	var polys: Array[PackedInt32Array] = []
	for i in navmesh.get_polygon_count():
		polys.append(navmesh.get_polygon(i))

	# вершины склеиваем по позиции: бейк дублирует их на стыках полигонов
	var by_pos := {}
	var canon := PackedInt32Array()
	canon.resize(verts.size())
	for i in verts.size():
		var k := "%.3f_%.3f_%.3f" % [verts[i].x, verts[i].y, verts[i].z]
		if not by_pos.has(k):
			by_pos[k] = i
		canon[i] = int(by_pos[k])

	# соседство по общему ребру
	var edges := {}
	for p in polys.size():
		var idx := polys[p]
		for e in idx.size():
			var a := canon[idx[e]]
			var b := canon[idx[(e + 1) % idx.size()]]
			var ek := "%d_%d" % [mini(a, b), maxi(a, b)]
			if not edges.has(ek):
				edges[ek] = []
			(edges[ek] as Array).append(p)

	var adj := {}
	for ek in edges:
		var side: Array = edges[ek]
		for i in side.size():
			for j in range(i + 1, side.size()):
				if not adj.has(side[i]):
					adj[side[i]] = []
				if not adj.has(side[j]):
					adj[side[j]] = []
				(adj[side[i]] as Array).append(side[j])
				(adj[side[j]] as Array).append(side[i])

	# центроиды — по ним ищем стартовые полигоны под спавнами
	var mid := PackedVector3Array()
	mid.resize(polys.size())
	for p in polys.size():
		var c := Vector3.ZERO
		for k in polys[p]:
			c += verts[k]
		mid[p] = c / float(polys[p].size())

	var spawns: Array[Vector3] = []
	for grp in ["spawn_attack", "spawn_defend"]:
		for n in map_root.find_children("*", "Marker3D", true, false):
			if (n as Node).is_in_group(grp):
				spawns.append((n as Marker3D).global_position)
	if spawns.is_empty():
		push_error("bake_navmesh: на карте нет спавнов — не от чего считать связность")
		return false

	var keep := {}
	for sp in spawns:
		# полигон под спавном: сначала тот, внутрь которого точка попадает по XZ
		# (полигоны крупные, до их центроида может быть далеко), иначе — ближайший
		var best := -1
		var bd := INF
		for p in polys.size():
			var flat := PackedVector2Array()
			for k in polys[p]:
				flat.append(Vector2(verts[k].x, verts[k].z))
			var dy := absf(mid[p].y - sp.y)
			var d := mid[p].distance_to(sp)
			if Geometry2D.is_point_in_polygon(Vector2(sp.x, sp.z), flat) and dy < 2.0:
				d = dy
			if d < bd:
				bd = d
				best = p
		if best < 0 or bd > 6.0:
			push_error("bake_navmesh: спавн %s дальше 6 м от навмеша (d=%.2f)" % [sp, bd])
			return false
		if keep.has(best):
			continue
		var stack := [best]
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			if keep.has(cur):
				continue
			keep[cur] = true
			for q in (adj.get(cur, []) as Array):
				if not keep.has(q):
					stack.append(q)

	var dropped := polys.size() - keep.size()
	if keep.size() < polys.size() / 2:
		push_error("bake_navmesh: связная область меньше половины навмеша (%d из %d) — карта распалась" % [keep.size(), polys.size()])
		return false
	navmesh.clear_polygons()
	for p in polys.size():
		if keep.has(p):
			navmesh.add_polygon(polys[p])
	print("bake_navmesh: отброшено недостижимых полигонов=", dropped)
	return true
