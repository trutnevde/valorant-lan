# FX (autoload): маршрутизация способностей — авторитет-паритет вебу.
# Клиент кастует → RPC хосту → хост поднимает ЛОГИКУ эффекта (урон/хил/CC — только он)
# и бродкастит ВИЗУАЛ всем. Офлайн — то же самое напрямую без сети.
extends Node


func cast(kind: String, data: Dictionary) -> void:
	if NetHub.online() and not multiplayer.is_server():
		rpc_id(1, "_cast_srv", kind, data)
	else:
		if _spawn_logic(kind, data):
			_fx_broadcast(kind, data)


@rpc("any_peer", "reliable")
func _cast_srv(kind: String, data: Dictionary) -> void:
	if not NetHub.is_host():
		return
	if _spawn_logic(kind, data):
		_fx_broadcast(kind, data)


func _fx_broadcast(kind: String, data: Dictionary) -> void:
	if NetHub.online():
		_fx.rpc(kind, data)
	else:
		_fx(kind, data)


# ===== логика (ТОЛЬКО хост/офлайн): урон, хил, слепота. false = каст отклонён =====
func _spawn_logic(kind: String, data: Dictionary) -> bool:
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
		"smoke":
			# дым валидирует хост («Развеятель» мог заблокировать зону)
			var sw := get_node("/root/Smokes")
			if not bool(sw.call("add_smoke", Vector3(data["x"], 0, data["z"]), String(data["team"]), bool(data.get("stink", false)))):
				return false
			data["id"] = sw.get("_seq")
		"dispel":
			var sw2 := get_node("/root/Smokes")
			var removed: Array = sw2.call("dispel", Vector3(data["x"], 0, data["z"]), String(data["team"]))
			data["removed"] = removed
		"generic":
			var g: Node = (load(String(data["logic"])) as GDScript).new()
			g.set("data", data)
			if data.has("cname"):
				g.name = String(data["cname"]) + "_logic"
			get_tree().current_scene.add_child(g)
		"cocoon":
			var cl: Node = (load("res://src/agents/effects/cocoon.gd") as GDScript).new()
			cl.set("data", data)
			cl.name = String(data["cname"]) + "_logic"
			get_tree().current_scene.add_child(cl)
		"levit":
			var lv: Node = (load("res://src/agents/effects/levit.gd") as GDScript).new()
			lv.set("data", data)
			get_tree().current_scene.add_child(lv)
		_:
			pass
	return true


# ===== визуал (у всех) =====
@rpc("authority", "reliable", "call_local")
func _fx(kind: String, data: Dictionary) -> void:
	if get_tree().current_scene == null:
		return  # headless-тесты без сцены — визуал некуда вешать
	_fx_sound(kind, data)
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
		"smoke":
			# клиенты ведут локальный список (Охотник Геры, HUD); хост уже добавил в логике
			var sw := get_node("/root/Smokes")
			if NetHub.online() and not multiplayer.is_server():
				(sw.get("smokes") as Array).append({
					"id": int(data["id"]), "pos": Vector3(data["x"], 0, data["z"]),
					"r": float(Balance.ABILITY["SMOKE_R"]),
					"until": Time.get_ticks_msec() / 1000.0 + float(Balance.ABILITY["SMOKE_TIME"]),
					"team": String(data["team"]), "stink": bool(data.get("stink", false)),
				})
			_vis_smoke(int(data["id"]), Vector3(data["x"], 0, data["z"]), bool(data.get("stink", false)))
		"dispel":
			var sw3 := get_node("/root/Smokes")
			var ids: Array = data.get("removed", [])
			if NetHub.online() and not multiplayer.is_server():
				var lst: Array = sw3.get("smokes")
				sw3.set("smokes", lst.filter(func(s: Dictionary) -> bool: return not ids.has(int(s["id"]))))
			for sid in ids:
				var v := get_tree().current_scene.get_node_or_null("SmokeVis_%d" % int(sid))
				if v:
					v.queue_free()
			_vis_ring(Vector3(data["x"], 0.1, data["z"]), float(Balance.ABILITY["GERA_DISPEL_R"]), Color(0.37, 0.88, 0.82), 1.2)
		"reveal":
			# подсветка врагов МОЕЙ команде (маркер сквозь стены)
			var me := _my_player()
			if me and String(data["team"]) == me.team:
				for tp in (data["targets"] as Array):
					var tgt := get_node_or_null(NodePath(String(tp))) as Node3D
					if tgt:
						_vis_reveal(tgt, float(data["dur"]))
		"corpse":
			_vis_corpse(Vector3(data["x"], 0, data["z"]))
		"turret_body":
			var tb := TurretBody.new()
			tb.name = String(data["cname"])
			tb.cname = String(data["cname"])
			get_tree().current_scene.add_child(tb)
			tb.global_position = Vector3(data["x"], 0, data["z"])
		"trap_vis":
			# сигналку видит только СВОЯ команда (врагам — сюрприз)
			var me2 := _my_player()
			if me2 and String(data["team"]) == me2.team:
				var tm := MeshInstance3D.new()
				tm.name = String(data["cname"]) + "_vis"
				var cyl2 := CylinderMesh.new()
				cyl2.top_radius = 0.3
				cyl2.bottom_radius = 0.3
				cyl2.height = 0.06
				tm.mesh = cyl2
				var tmat := StandardMaterial3D.new()
				tmat.albedo_color = Color(0.9, 0.8, 0.3)
				tmat.emission_enabled = true
				tmat.emission = Color(0.9, 0.8, 0.3)
				tm.material_override = tmat
				get_tree().current_scene.add_child(tm)
				tm.global_position = Vector3(data["x"], 0.05, data["z"])
		"chicken":
			var ch := MeshInstance3D.new()
			ch.name = String(data["cname"])
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.3, 0.35, 0.4)
			ch.mesh = bm2
			var cmat := StandardMaterial3D.new()
			cmat.albedo_color = Color(1.0, 0.85, 0.2)
			ch.material_override = cmat
			get_tree().current_scene.add_child(ch)
			ch.global_position = Vector3(data["x"], 0.2, data["z"])
		"chicken_move":
			var chm := get_tree().current_scene.get_node_or_null(String(data["cname"])) as Node3D
			if chm:
				chm.global_position = Vector3(data["x"], 0.2, data["z"])
		"banquet_dome":
			_vis_ring(Vector3(data["x"], 0.05, data["z"]), float(Balance.ABILITY["BANQUET_R"]), Color(0.95, 0.25, 0.2), float(Balance.ABILITY["BANQUET_TIME"]))
		"orbital_beam":
			_vis_ring(Vector3(data["x"], 0.05, data["z"]), float(Balance.ABILITY["ORBITAL_R"]), Color(1.0, 0.3, 0.15), float(Balance.ABILITY["ORBITAL_DELAY"]) + float(Balance.ABILITY["ORBITAL_DUR"]))
		"fire_zone_vis_acid":
			_vis_ring(Vector3(data["x"], 0.05, data["z"]), float(Balance.ABILITY["ACID_R"]), Color(0.75, 0.85, 0.25), float(Balance.ABILITY["ACID_TIME"]))
		"fire_zone_vis_horseshoe":
			_vis_ring(Vector3(data["x"], 0.05, data["z"]), float(Balance.ABILITY["HORSESHOE_R"]), Color(0.72, 0.6, 0.45), float(Balance.ABILITY["HORSESHOE_TIME"]))
		"ira_corpse_vis":
			_vis_ring(Vector3(data["x"], 0.05, data["z"]), float(Balance.ABILITY["IRA_CORPSE_R"]), Color(0.53, 1.0, 0.63), float(Balance.ABILITY["IRA_CORPSE_TIME"]))
		"crispy_vis":
			_vis_wall({ "ax": data["ax"], "az": data["az"], "bx": data["bx"], "bz": data["bz"] }, Color(0.94, 0.75, 0.4), float(Balance.ABILITY["CRISPY_TIME"]))
		"stampede_vis":
			_vis_wall({ "ax": data["fx"], "az": data["fz"], "bx": float(data["fx"]) + float(data["dx"]) * float(Balance.ABILITY["STAMPEDE_LEN"]), "bz": float(data["fz"]) + float(data["dz"]) * float(Balance.ABILITY["STAMPEDE_LEN"]) }, Color(0.72, 0.55, 0.3), 1.0)
		"cocoon":
			# щит-кокон у всех (стреляемый; урон решает хост)
			var sh := CocoonShield.new()
			sh.name = String(data["cname"])
			sh.cname = String(data["cname"])
			get_tree().current_scene.add_child(sh)
			var v := get_node_or_null(NodePath(String(data["victim_path"]))) as Node3D
			if v:
				sh.global_position = v.global_position + Vector3(0, 1.1, 0)
		"flash":
			_vis_orb(data, Color(1.0, 0.95, 0.7))
		"levit":
			_vis_dome(Vector3(data["x"], 0, data["z"]))
		"generic":
			var lg := String(data.get("logic", ""))
			if lg.contains("sova_arrow"):
				_vis_arrow(data)
				if bool(data.get("shootable", false)):
					# сбиваемая разведстрела: стреляемое тело летит вместе с визуалом
					var ab := ArrowBody.new()
					ab.name = String(data["cname"])
					ab.cname = String(data["cname"])
					get_tree().current_scene.add_child(ab)
					var afrom := Vector3(data["fx"], data["fy"], data["fz"])
					var ato := Vector3(data["tx"], data["ty"], data["tz"])
					ab.global_position = afrom
					var atw := ab.create_tween()
					atw.tween_property(ab, "global_position", ato, clampf(afrom.distance_to(ato) * 0.018, 0.12, 0.8))
					atw.tween_callback(ab.queue_free)
			elif lg.contains("scent"):
				_vis_ring(Vector3(data["x"], 0.08, data["z"]), 1.0, Color(0.55, 0.75, 0.3), float(Balance.ABILITY["SCENT_LIFE"]))
			elif lg.contains("vortex"):
				_vis_ring(Vector3(float(data["fx"]) + float(data["dx"]) * 6.0, 0.1, float(data["fz"]) + float(data["dz"]) * 6.0), 2.0, Color(0.37, 0.88, 0.82), float(Balance.ABILITY["GERA_VORTEX_TIME"]))
			elif lg.contains("fury"):
				_vis_wall({ "ax": data["fx"], "az": data["fz"], "bx": float(data["fx"]) + float(data["dx"]) * float(Balance.ABILITY["SOVA_FURY_LEN"]), "bz": float(data["fz"]) + float(data["dz"]) * float(Balance.ABILITY["SOVA_FURY_LEN"]) }, Color(0.6, 0.9, 1.0), 1.2)
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


# ===== позиционный звук способностей (бродкаст через _fx → слышат все пиры) =====
const _FX_SND := {
	"smoke": "whoosh", "dispel": "zap", "flash": "pop", "cocoon": "whoosh2",
	"levit": "energy", "turret_body": "slam", "trap_vis": "confirm", "chicken": "pop",
	"banquet_dome": "buff", "orbital_beam": "boom", "crispy_vis": "slam",
	"stampede_vis": "slam", "fire_zone_vis_acid": "energy", "fire_zone_vis_horseshoe": "slam",
	"ira_corpse_vis": "buff", "corpse": "hurt", "reveal": "confirm",
}
var _snd_cache := {}


func _fx_sound(kind: String, data: Dictionary) -> void:
	if not _FX_SND.has(kind):
		return
	var name: String = _FX_SND[kind]
	if not _snd_cache.has(name):
		_snd_cache[name] = load("res://assets/audio/%s.ogg" % name)
	var pos := Vector3.ZERO
	if data.has("x") and data.has("z"):
		pos = Vector3(float(data["x"]), 0, float(data["z"]))
	elif data.has("fx") and data.has("fz"):
		pos = Vector3(float(data["fx"]), float(data.get("fy", 0.0)), float(data["fz"]))
	elif data.has("ax") and data.has("az"):
		pos = Vector3(float(data["ax"]), 0, float(data["az"]))
	get_node("/root/Ears").call("one_shot", get_tree().current_scene, pos, _snd_cache[name], "SFX", 1.0, -3.0)


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


func _vis_smoke(id: int, pos: Vector3, stink: bool) -> void:
	var m := MeshInstance3D.new()
	m.name = "SmokeVis_%d" % id
	var sph := SphereMesh.new()
	var r := float(Balance.ABILITY["SMOKE_R"])
	sph.radius = r
	sph.height = r * 2.0
	m.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.48, 0.24, 0.96) if stink else Color(0.6, 0.65, 0.7, 0.96)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # непрозрачен и изнутри (глухой дым)
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = pos + Vector3(0, r * 0.55, 0)
	var tw := m.create_tween()
	tw.tween_interval(float(Balance.ABILITY["SMOKE_TIME"]))
	tw.tween_callback(m.queue_free)


func _vis_dome(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var sph := SphereMesh.new()
	var r := float(Balance.ABILITY["GERA_ULT_R"])
	sph.radius = r
	sph.height = r * 2.0
	m.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.37, 0.88, 0.82, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = pos + Vector3(0, r * 0.4, 0)
	var tw := m.create_tween()
	tw.tween_interval(float(Balance.ABILITY["GERA_ULT_TIME"]))
	tw.tween_callback(m.queue_free)


func _vis_arrow(data: Dictionary) -> void:
	var from := Vector3(data["fx"], data["fy"], data["fz"])
	var to := Vector3(data["tx"], data["ty"], data["tz"])
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = 0.55
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.62, 0.91, 1.0)
	mat.albedo_color = Color(0.62, 0.91, 1.0)
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = from
	if from.distance_to(to) > 0.01:
		m.look_at(to, Vector3.UP)
		m.rotate_object_local(Vector3.RIGHT, PI / 2)
	var travel := clampf(from.distance_to(to) * 0.018, 0.12, 0.8)
	var tw := m.create_tween()
	tw.tween_property(m, "global_position", to, travel)
	tw.tween_interval(1.2)  # стрела торчит в точке попадания
	tw.tween_callback(m.queue_free)


func _vis_corpse(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.4
	m.mesh = cap
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.1, 0.1)
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = pos + Vector3(0, 0.3, 0)
	m.rotation.x = PI / 2
	var tw := m.create_tween()
	tw.tween_interval(float(Balance.ABILITY["CORPSE_LIFE"]))
	tw.tween_callback(m.queue_free)


func _vis_reveal(target: Node3D, dur: float) -> void:
	var m := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.16
	sph.height = 0.32
	m.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.28, 0.33)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.28, 0.33)
	mat.no_depth_test = true  # сквозь стены — это и есть подсветка
	m.material_override = mat
	target.add_child(m)
	m.position = Vector3(0, 2.15, 0)
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
