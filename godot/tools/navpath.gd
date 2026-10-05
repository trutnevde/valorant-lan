# Печатает высотный профиль пути между двумя точками — видно, лезет ли путь на крышу.
extends SceneTree
func _initialize() -> void:
	var map_id := "height"
	var fx := 2.4; var fz := 3.4; var tx := 20.0; var tz := -6.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): map_id = a.substr(6)
		elif a.begins_with("--from="):
			var pf := a.substr(7).split(",")
			fx = float(pf[0]); fz = float(pf[1])
		elif a.begins_with("--to="):
			var pt2 := a.substr(5).split(",")
			tx = float(pt2[0]); tz = float(pt2[1])
	var map: Node3D = (load("res://scenes/maps/%s.tscn" % map_id) as PackedScene).instantiate()
	root.add_child(map)
	current_scene = map
	for i in 10: await physics_frame
	var agent := NavigationAgent3D.new()
	var body := CharacterBody3D.new()
	map.add_child(body)
	body.add_child(agent)
	body.global_position = Vector3(fx, 0.2, fz)
	await physics_frame
	agent.target_position = Vector3(tx, 0.2, tz)
	for i in 4: await physics_frame
	var _np := agent.get_next_path_position()  # форсируем расчёт
	for i in 2: await physics_frame
	var path := agent.get_current_navigation_path()
	var prof: Array = []
	for p in path: prof.append("%.1f/%.1f@%.1f" % [p.x, p.z, p.y])
	print("путь (%d точек): %s" % [path.size(), ", ".join(prof)])
	quit(0)
