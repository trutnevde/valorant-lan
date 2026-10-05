# Проба навмеша: точки внутри сплошного блока не должны лежать НИ В ОДНОМ полигоне
# нижнего яруса (y<1). Если лежат — навмеш «дырявый», боты пойдут в стену.
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
	var map_id := "bastion"
	var x0 := -6.0; var x1 := 6.0; var z0 := -5.5; var z1 := 3.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): map_id = a.substr(6)
		elif a.begins_with("--box="):
			var p := a.substr(6).split(",")
			x0 = float(p[0]); z0 = float(p[1]); x1 = float(p[2]); z1 = float(p[3])
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
	var bad := 0; var total := 0
	var x := x0 + 0.5
	while x < x1 - 0.4:
		var z := z0 + 0.5
		while z < z1 - 0.4:
			total += 1
			for p: Dictionary in polys:
				if float(p["y"]) < 1.0 and _pt_in_poly(x, z, p["f"]):
					bad += 1
					break
			z += 1.0
		x += 1.0
	print("%s: точек внутри блока=%d, попало в нижний навмеш=%d %s" % [map_id, total, bad, "ДЫРА" if bad > 0 else "чисто"])
	quit(0)
