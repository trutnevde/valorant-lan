extends SceneTree
func _pt_in_poly(px: float, pz: float, pts: PackedVector2Array) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		if ((pts[i].y > pz) != (pts[j].y > pz)) and (px < (pts[j].x - pts[i].x) * (pz - pts[i].y) / (pts[j].y - pts[i].y) + pts[i].x):
			inside = not inside
		j = i
	return inside
func _initialize() -> void:
	var nm: NavigationMesh = load("res://scenes/maps/height.navmesh.res")
	var verts := nm.get_vertices()
	for pt in [Vector2(0, -2), Vector2(3, 0), Vector2(-4, -3), Vector2(20, -6)]:
		var ys: Array = []
		for i in nm.get_polygon_count():
			var poly := nm.get_polygon(i)
			var flat := PackedVector2Array(); var ymax := -1e9
			for vi in poly:
				flat.append(Vector2(verts[vi].x, verts[vi].z)); ymax = maxf(ymax, verts[vi].y)
			if _pt_in_poly(pt.x, pt.y, flat): ys.append(snappedf(ymax, 0.01))
		print("точка (%.0f,%.0f) накрыта полигонами на высотах: %s" % [pt.x, pt.y, str(ys)])
	quit(0)
