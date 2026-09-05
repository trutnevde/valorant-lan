# Миникарта G9 — схематичная (2D _draw, дёшево, без второго рендера):
# стены из map_meta, сайты, союзники, свой маркер-стрелка, шип. Плюс:
#  • свои дымы всегда; для Геры — ещё и ВРАЖЬИ дымы (пассивка «Барометр»);
#  • подсвеченные враги (Радар Санька / реванулы) из Fx.revealed_positions();
#  • подсвеченные враги (реванулы) из Fx.
extends Control

var player: FpsPlayer
var _walls: Array = []
var _sites := {}
var _sw := 60.0
var _sd := 60.0


func setup(p: FpsPlayer) -> void:
	player = p
	_load_meta()


func _load_meta() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var raw := "{}"
	if scene.has_meta("map_meta"):
		raw = scene.get_meta("map_meta")
	else:
		for c in scene.get_children():
			if c.has_meta("map_meta"):
				raw = c.get_meta("map_meta")
				break
	var meta = JSON.parse_string(raw)
	if meta is Dictionary:
		_walls = meta.get("walls_aabb", [])
		_sw = float(meta.get("size_w", 60.0))
		_sd = float(meta.get("size_d", 60.0))
		if meta.has("site_a"):
			_sites["A"] = meta["site_a"]
		if meta.has("site_b"):
			_sites["B"] = meta["site_b"]


func _process(_dt: float) -> void:
	if player != null:
		queue_redraw()


func _w2m(wx: float, wz: float) -> Vector2:
	var u := (wx + _sw * 0.5) / _sw
	var v := (wz + _sd * 0.5) / _sd
	return Vector2(clampf(u, 0, 1) * size.x, clampf(v, 0, 1) * size.y)


func _draw() -> void:
	if player == null:
		return
	# фон
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.09, 0.72))
	# сайты
	for key in _sites:
		var s: Array = _sites[key]
		var c := _w2m(float(s[0]), float(s[1]))
		draw_rect(Rect2(c - Vector2(11, 11), Vector2(22, 22)), Color(0.55, 0.42, 0.15, 0.4))
		draw_string(ThemeDB.fallback_font, c - Vector2(4, -5), key, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1, 0.9, 0.6))
	# стены
	for wl in _walls:
		var a := _w2m(float(wl[0]), float(wl[1]))
		var b := _w2m(float(wl[2]), float(wl[3]))
		draw_rect(Rect2(a, b - a), Color(0.30, 0.34, 0.40, 0.95))
	# дымы: свои всегда; для Геры — и вражьи (Барометр)
	var smokes := get_node_or_null("/root/Smokes")
	if smokes:
		for sm: Dictionary in (smokes.get("smokes") as Array):
			var pos: Vector3 = sm["pos"]
			var enemy := String(sm["team"]) != player.team
			if enemy and player.char_id != "gera":
				continue
			var col := Color(0.95, 0.55, 0.2, 0.7) if enemy else Color(0.7, 0.75, 0.8, 0.5)
			draw_circle(_w2m(pos.x, pos.z), 6.0, col)
	# шип
	var mt := Match.find(get_tree())
	if mt:
		var sp: Vector3 = mt.spike_planted_at
		if sp != Vector3.INF:
			draw_circle(_w2m(sp.x, sp.z), 4.0, Color(1.0, 0.3, 0.2))
		elif mt.spike_carrier and is_instance_valid(mt.spike_carrier):
			var cp: Vector3 = (mt.spike_carrier as Node3D).global_position
			draw_circle(_w2m(cp.x, cp.z), 3.0, Color(0.9, 0.7, 0.2))
	# союзники
	for c in get_tree().get_nodes_in_group("combatants"):
		var n := c as Node3D
		if n == null or n == player or int(n.get("hp")) <= 0:
			continue
		if String(n.get("team")) == player.team:
			draw_circle(_w2m(n.global_position.x, n.global_position.z), 3.0, Color(0.35, 0.8, 1.0))
	# подсвеченные враги
	var fx := get_node_or_null("/root/Fx")
	if fx:
		for ep: Vector3 in fx.call("revealed_positions"):
			draw_circle(_w2m(ep.x, ep.z), 3.5, Color(1.0, 0.25, 0.3))
	# свой маркер-стрелка (по yaw)
	var me := _w2m(player.global_position.x, player.global_position.z)
	var fwd := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var mfwd := (_w2m(player.global_position.x + fwd.x, player.global_position.z + fwd.z) - me).normalized()
	if mfwd == Vector2.ZERO:
		mfwd = Vector2.UP
	var mperp := Vector2(-mfwd.y, mfwd.x)
	draw_colored_polygon(PackedVector2Array([
		me + mfwd * 7.0, me - mfwd * 4.0 + mperp * 4.0, me - mfwd * 4.0 - mperp * 4.0,
	]), Color(1, 1, 1))
