# Ears — 3D-аудио сцены (движковые системы, не самопал):
#  • ОККЛЮЗИЯ: раз в ~70мс раскастим от источника к слушателю (камере); стена (group
#    "map_solid") или дым (Smokes.seg_blocked) между ними → источник уходит на шину "Muffled"
#    (low-pass 620 Гц −4дБ), иначе возвращается на домашнюю шину. Дёшево: тик 14 Гц.
#  • РЕВЕРБ-ЗОНЫ: на сайтах спавним Area3D с reverb_bus_enabled → выстрелы внутри гулкие.
# Регистрация: Ears.register(player3d, home_bus, emitter_body). Транзиентные звуки Fx
# сами снимаются по finished.
extends Node

const TICK := 0.07
var _acc := 0.0


func _process(delta: float) -> void:
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	_update_occlusion()


func register(p: AudioStreamPlayer3D, home_bus := "SFX", emitter: Node = null) -> void:
	p.set_meta("home_bus", home_bus)
	p.bus = home_bus
	if emitter and emitter is CollisionObject3D:
		p.set_meta("body_rid", (emitter as CollisionObject3D).get_rid())
	if not p.is_in_group("spatial_sfx"):
		p.add_to_group("spatial_sfx")


# одноразовый позиционный звук (способности, грунты) — снимается сам
func one_shot(parent: Node, pos: Vector3, stream: AudioStream, home_bus := "SFX", pitch := 1.0, vol_db := 0.0) -> void:
	if parent == null or stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.max_distance = 60.0
	p.unit_size = 6.0
	parent.add_child(p)
	p.global_position = pos + Vector3(0, 1.2, 0)
	register(p, home_bus)
	p.finished.connect(p.queue_free)
	p.play()


func _update_occlusion() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var listener := cam.global_position
	var space := cam.get_world_3d().direct_space_state
	var smokes := get_node_or_null("/root/Smokes")
	var listener_rid := _listener_rid(cam)
	for n in get_tree().get_nodes_in_group("spatial_sfx"):
		var p := n as AudioStreamPlayer3D
		if p == null or not p.playing:
			continue
		var home := String(p.get_meta("home_bus", "SFX"))
		var src := p.global_position
		var occ := false
		if smokes and bool(smokes.call("seg_blocked", src, listener)):
			occ = true
		elif src.distance_to(listener) > 0.8:
			var q := PhysicsRayQueryParameters3D.create(src, listener)
			var excl: Array[RID] = []
			if p.has_meta("body_rid"):
				excl.append(p.get_meta("body_rid"))
			if listener_rid != RID():
				excl.append(listener_rid)
			q.exclude = excl
			var res := space.intersect_ray(q)
			if not res.is_empty():
				var c = res.get("collider")
				if c and (c as Node).is_in_group("map_solid"):
					occ = true
		var want := "Muffled" if occ else home
		if p.bus != want:
			p.bus = want


func _listener_rid(cam: Camera3D) -> RID:
	var n: Node = cam.get_parent()
	while n:
		if n is CollisionObject3D:
			return (n as CollisionObject3D).get_rid()
		n = n.get_parent()
	return RID()


# реверб-зоны из меты карты (site_a/site_b) — гулкость закрытых точек
func setup_reverb_zones(map_root: Node, meta: Dictionary) -> void:
	for key in ["site_a", "site_b"]:
		if not meta.has(key):
			continue
		var arr: Array = meta[key]
		var area := Area3D.new()
		area.reverb_bus_enabled = true
		area.reverb_bus_name = "Reverb"
		area.reverb_bus_amount = 0.7
		area.reverb_bus_uniformity = 0.6
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(11, 6, 11)
		shape.shape = box
		area.add_child(shape)
		map_root.add_child(area)
		area.global_position = Vector3(float(arr[0]), 3.0, float(arr[1]))
