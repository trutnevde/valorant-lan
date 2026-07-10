# FX (autoload): маршрутизация способностей — авторитет-паритет вебу.
# Клиент кастует → RPC хосту → хост поднимает ЛОГИКУ эффекта (урон/хил/CC — только он)
# и бродкастит ВИЗУАЛ всем. Офлайн — то же самое напрямую без сети.
extends Node


func cast(kind: String, data: Dictionary) -> void:
	if NetHub.online() and not multiplayer.is_server():
		rpc_id(1, "_cast_srv", kind, data)
	else:
		_spawn_logic(kind, data)
		_fx_broadcast(kind, data)


@rpc("any_peer", "reliable")
func _cast_srv(kind: String, data: Dictionary) -> void:
	if not NetHub.is_host():
		return
	_spawn_logic(kind, data)
	_fx_broadcast(kind, data)


func _fx_broadcast(kind: String, data: Dictionary) -> void:
	if NetHub.online():
		_fx.rpc(kind, data)
	else:
		_fx(kind, data)


# ===== логика (ТОЛЬКО хост/офлайн): урон, хил, слепота =====
func _spawn_logic(kind: String, data: Dictionary) -> void:
	match kind:
		"flash":
			var orb: Node = (load("res://src/agents/effects/flash_orb.gd") as GDScript).new()
			orb.set("data", data)
			get_tree().current_scene.add_child(orb)
		"fire_zone", "fire_wall":
			var z: Node = (load("res://src/agents/effects/fire_zone.gd") as GDScript).new()
			z.set("data", data)
			z.set("is_wall", kind == "fire_wall")
			get_tree().current_scene.add_child(z)
		"ult_mark":
			# метка живёт на ХОСТОВОЙ копии игрока — смерть решает хост (try_second_wind)
			var p := get_node_or_null(NodePath(String(data.get("owner_path", ""))))
			if p:
				p.set("ult_mark_pos", Vector3(data["x"], 0.1, data["z"]))
				p.set("ult_mark_until", Time.get_ticks_msec() / 1000.0 + float(Balance.ABILITY["PHOENIX_ULT_TIME"]))
		_:
			pass


# ===== визуал (у всех) =====
@rpc("authority", "reliable", "call_local")
func _fx(kind: String, data: Dictionary) -> void:
	match kind:
		"clone_decoy":
			# клон-обманка видим ВСЕМ: копия на каждом пире, одинаковое имя → одинаковый путь
			# (выстрел клиента репортится хосту по пути — хостовая копия решает поп-стан)
			var c: Node = (load("res://src/agents/effects/clone_decoy.gd") as GDScript).new()
			c.set("data", data)
			c.name = String(data.get("cname", "Clone_x"))
			get_tree().current_scene.add_child(c)
		"clone_gone", "clone_gone_req":
			# клон исчез (лопнул/истёк/отозван) — убрать копию у всех
			var gone := get_tree().current_scene.get_node_or_null(String(data["cname"]))
			if gone:
				gone.queue_free()
		"clone_move":
			# рокировка: клон встаёт на место игрока
			var cm := get_tree().current_scene.get_node_or_null(String(data["cname"])) as Node3D
			if cm:
				cm.global_position = Vector3(data["x"], 0, data["z"])
				cm.set("data", (cm.get("data") as Dictionary).merged({ "mode": "stand" }, true))
		"flash":
			_vis_orb(data, Color(1.0, 0.95, 0.7))
		"fire_zone":
			_vis_ring(Vector3(data["x"], 0.05, data["z"]), float(Balance.ABILITY["FIRE_ZONE_R"]), Color(1.0, 0.45, 0.15), float(Balance.ABILITY["FIRE_ZONE_TIME"]))
		"fire_wall":
			_vis_wall(data, Color(1.0, 0.45, 0.15), float(Balance.ABILITY["WALL_TIME"]))
		"ult_mark":
			_vis_ring(Vector3(data["x"], 0.05, data["z"]), 1.2, Color(1.0, 0.8, 0.2), float(Balance.ABILITY["PHOENIX_ULT_TIME"]))
		_:
			pass


# слепота: хост рассылает адресно (люди) и вешает на ботов
func blind_targets(pop_pos: Vector3, hits: Array) -> void:
	for h: Dictionary in hits:
		var node: Node = h["node"]
		var dur: float = h["dur"]
		if String(node.get("char_id")) == "fafik":
			dur *= 0.7  # пассивка Фафика «Батина закалка»: CC короче на 30%
		if node is Bot:
			(node as Bot).blind_until = Time.get_ticks_msec() / 1000.0 + dur
		elif node is FpsPlayer:
			if NetHub.online():
				var id := (node as Node).get_multiplayer_authority()
				_blind_client.rpc_id(id, dur)
			else:
				(node as FpsPlayer).apply_blind(dur)


func stun_target(node: Node, dur: float) -> void:
	if String(node.get("char_id")) == "fafik":
		dur *= 0.7  # «Батина закалка»
	if node is Bot:
		(node as Bot).stun_until = Time.get_ticks_msec() / 1000.0 + dur
	elif node is FpsPlayer:
		if NetHub.online():
			_stun_client.rpc_id((node as Node).get_multiplayer_authority(), dur)
		else:
			(node as FpsPlayer).apply_stun(dur)


@rpc("authority", "reliable", "call_local")
func _stun_client(dur: float) -> void:
	var p := _my_player()
	if p:
		p.apply_stun(dur)


func _my_player() -> FpsPlayer:
	var p := get_tree().current_scene.get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if p == null:
		for c in get_tree().get_nodes_in_group("combatants"):
			if c is FpsPlayer and (c as FpsPlayer).cam.current:
				return c as FpsPlayer
	return p as FpsPlayer


@rpc("authority", "reliable", "call_local")
func _blind_client(dur: float) -> void:
	var p := _my_player()
	if p:
		p.apply_blind(dur)


# урон/хил с онлайн-синком HP (эффекты живут только на хосте)
func apply_damage(node: Node, dmg: int, attacker: Node, weapon: String) -> void:
	if node.has_method("take_hit") and int(node.get("hp")) > 0:
		node.call("take_hit", dmg, "body", attacker, weapon)
		_sync(node)


func apply_heal(node: Node, amount: int) -> void:
	if not node.has_method("take_hit"):
		return
	var maxhp := int(Balance.RULES["BASE_HP"])
	var hp := int(node.get("hp"))
	if hp <= 0 or hp >= maxhp:
		return
	node.set("hp", mini(maxhp, hp + amount))
	if node.has_signal("hp_changed"):
		node.emit_signal("hp_changed", int(node.get("hp")))
	_sync(node)


func _sync(node: Node) -> void:
	if NetHub.online() and multiplayer.is_server():
		var n := NetHub.node()
		if n:
			n.rpc("_sync_hp", node.get_path(), int(node.get("hp")))


# ===== простые визуалы (грейбокс-уровень; красота — G10) =====
func _vis_orb(data: Dictionary, color: Color) -> void:
	var m := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.18
	sph.height = 0.36
	m.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = color
	mat.albedo_color = color
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	var from := Vector3(data["fx"], data["fy"], data["fz"])
	var dir := Vector3(data["dx"], data["dy"], data["dz"])
	m.global_position = from
	var fuse := float(Balance.ABILITY["FLASH_FUSE"])
	var tw := m.create_tween()
	tw.tween_property(m, "global_position", from + dir * float(Balance.ABILITY["FLASH_SPEED"]) * fuse, fuse)
	tw.tween_callback(m.queue_free)


func _vis_ring(pos: Vector3, r: float, color: Color, dur: float) -> void:
	var m := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = r - 0.15
	tor.outer_radius = r
	m.mesh = tor
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = color
	mat.albedo_color = color
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.tween_interval(dur)
	tw.tween_callback(m.queue_free)


func _vis_wall(data: Dictionary, color: Color, dur: float) -> void:
	var a := Vector3(data["ax"], 0, data["az"])
	var b := Vector3(data["bx"], 0, data["bz"])
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(a.distance_to(b), 2.4, 0.3)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = color
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = (a + b) * 0.5 + Vector3(0, 1.2, 0)
	m.look_at(m.global_position + (b - a).cross(Vector3.UP), Vector3.UP)
	var tw := m.create_tween()
	tw.tween_interval(dur)
	tw.tween_callback(m.queue_free)
