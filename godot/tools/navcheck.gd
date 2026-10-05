# Проверка навмеша против коллизии: внутри СПЛОШНЫХ стен (walls_aabb из меты карты) не
# должно быть ходибельных полигонов нижнего яруса. Дыра = бот строит путь сквозь стену,
# упирается телом и виснет (застревание в ботматче).
#   godot --headless --path . -s res://tools/navcheck.gd -- --map=duel
extends SceneTree

func _pt_in_poly(px: float, pz: float, pts: PackedVector2Array) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		if ((pts[i].y > pz) != (pts[j].y > pz)) and \
			(px < (pts[j].x - pts[i].x) * (pz - pts[i].y) / (pts[j].y - pts[i].y) + pts[i].x):
			inside = not inside
		j = i
	return inside


func _initialize() -> void:
	var maps: Array = ["duel", "height", "bastion", "dust2"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): maps = [a.substr(6)]
	var bad_total := 0
	for map_id: String in maps:
		var packed: PackedScene = load("res://scenes/maps/%s.tscn" % map_id)
		var root_node := packed.instantiate()
		var meta = JSON.parse_string(String(root_node.get_meta("map_meta", "{}")))
		root_node.free()
		var walls: Array = meta.get("solids_aabb", meta.get("walls_aabb", []))
		var nm: NavigationMesh = load("res://scenes/maps/%s.navmesh.res" % map_id)
		var verts := nm.get_vertices()
		var polys: Array = []
		for i in nm.get_polygon_count():
			var poly := nm.get_polygon(i)
			var flat := PackedVector2Array()
			var ymax := -1e9
			for vi in poly:
				flat.append(Vector2(verts[vi].x, verts[vi].z))
				ymax = maxf(ymax, verts[vi].y)
			polys.append({ "f": flat, "y": ymax })
		var holes := 0
		var samples := 0
		for w: Array in walls:
			var top: float = float(w[4]) if w.size() > 4 else 3.0   # верх бокса: полигон НИЖЕ него = дыра
			var x := float(w[0]) + 0.6
			while x < float(w[2]) - 0.5:
				var z := float(w[1]) + 0.6
				while z < float(w[3]) - 0.5:
					samples += 1
					for p: Dictionary in polys:
						if float(p["y"]) < top - 0.3 and _pt_in_poly(x, z, p["f"]):
							holes += 1
							break
					z += 0.9
				x += 0.9
		bad_total += holes
		if OS.get_environment("NAVDBG") == "1":
			for w2: Array in walls:
				var t2: float = float(w2[4]) if w2.size() > 4 else 3.0
				var h2 := 0
				var xx := float(w2[0]) + 0.6
				while xx < float(w2[2]) - 0.5:
					var zz := float(w2[1]) + 0.6
					while zz < float(w2[3]) - 0.5:
						for p2: Dictionary in polys:
							if float(p2["y"]) < t2 - 0.3 and _pt_in_poly(xx, zz, p2["f"]):
								h2 += 1
								break
						zz += 0.9
					xx += 0.9
				if h2 > 0:
					print("   бокс x=%.1f..%.1f z=%.1f..%.1f h=%.1f -> дыр %d" % [w2[0], w2[2], w2[1], w2[3], t2, h2])
		print("%-8s стен=%d, проб=%d, дыр в навмеше=%d %s" % [map_id, walls.size(), samples, holes, "✖" if holes > 0 else "✓"])
	print("navcheck: " + ("OK — навмеш согласован с коллизией" if bad_total == 0 else "FAIL — дыр всего %d" % bad_total))
	quit(0 if bad_total == 0 else 1)
