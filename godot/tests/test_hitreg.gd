# Hitreg-санити: детерминированные лучи в мишень с фикс. позиций → фикс. части тела.
# Годо-эквивалент web test/hitreg.mjs (та же разметка: голова y1.68, корпус y1.12, ноги y0.45).
extends GutTest

var dummy: TargetDummy
var world: Node3D


func before_all() -> void:
	world = Node3D.new()
	add_child(world)
	dummy = TargetDummy.new()
	dummy.position = Vector3(10, 0, 0)
	_add_shape(dummy, "Body", _box(Vector3(0.52, 0.9, 0.3)), Vector3(0, 1.12, 0))
	_add_shape(dummy, "Head", _sphere(0.2), Vector3(0, 1.68, 0))
	_add_shape(dummy, "Leg", _box(Vector3(0.42, 0.9, 0.26)), Vector3(0, 0.45, 0))
	world.add_child(dummy)


func after_all() -> void:
	world.queue_free()


func _add_shape(body: StaticBody3D, nm: String, shape: Shape3D, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = nm
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _cast(target: Vector3) -> Dictionary:
	var space := world.get_world_3d().direct_space_state
	var origin := Vector3(0, 1.6, 0)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + (target - origin).normalized() * 50.0)
	return space.intersect_ray(q)


func test_body_hit() -> void:
	await wait_physics_frames(2)
	var res := _cast(Vector3(10, 1.12, 0))
	assert_false(res.is_empty(), "луч в корпус должен попасть")
	assert_eq(dummy.part_at(res["shape"] as int), "body")


func test_head_hit() -> void:
	await wait_physics_frames(2)
	var res := _cast(Vector3(10, 1.68, 0))
	assert_false(res.is_empty(), "луч в голову должен попасть")
	assert_eq(dummy.part_at(res["shape"] as int), "head")


func test_leg_hit() -> void:
	await wait_physics_frames(2)
	var res := _cast(Vector3(10, 0.45, 0))
	assert_false(res.is_empty(), "луч в ноги должен попасть")
	assert_eq(dummy.part_at(res["shape"] as int), "leg")


func test_side_miss() -> void:
	await wait_physics_frames(2)
	var res := _cast(Vector3(10, 1.12, 6))
	assert_true(res.is_empty(), "луч в сторону должен промахнуться")


# ===== стрельба по НАСТОЯЩЕЙ мишени =====
# Тесты выше зелены даже на сломанном хитреге: у манекена нет капсулы движения. А у живого
# игрока она есть, идёт ПЕРВЫМ шейпом и на высоте головы шире сферы головы — луч всегда
# попадал в неё, и хедшот превращался в «body». Ниже стреляем по реальной сцене игрока.
func test_real_player_headshot_not_swallowed_by_move_capsule() -> void:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	p.position = Vector3(12, 0, 0)
	world.add_child(p)
	autofree(p)
	await wait_physics_frames(3)
	var space := world.get_world_3d().direct_space_state
	var origin := Vector3(0, 1.68, 0)
	var to := Vector3(12, 1.68, 0)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + (to - origin).normalized() * 60.0)
	var res := space.intersect_ray(q)
	assert_false(res.is_empty(), "луч в живого игрока должен попасть")
	var part: String = p.part_at(res["shape"] as int, (res["position"] as Vector3).y)
	assert_eq(part, "head", "по высоте это ГОЛОВА, даже если луч пришёлся в капсулу движения")
	# и урон должен быть хедшотный, а не корпусной
	var wd: Dictionary = Balance.WEAPONS["vandal"]
	var dmg := int(wd["head"]) if part == "head" else int(wd["dmg"])
	assert_eq(dmg, 160, "«Вандал» в голову — 160, а не 40")


func test_real_player_body_and_legs() -> void:
	var p: FpsPlayer = (load("res://scenes/agents/player.tscn") as PackedScene).instantiate()
	p.position = Vector3(14, 0, 0)
	world.add_child(p)
	autofree(p)
	await wait_physics_frames(3)
	assert_eq(p.part_at(0, 14.0 * 0.0 + 1.15), "body", "грудь — корпус")
	assert_eq(p.part_at(0, 0.5), "leg", "голень — ноги")
