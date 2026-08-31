# Связность карты через NavigationServer (замена веб-валидатора):
# оба сайта достижимы с обоих спавнов по забейканному навмешу.
extends GutTest

var map: Node3D


func before_all() -> void:
	map = (load("res://scenes/maps/duel.tscn") as PackedScene).instantiate()
	add_child(map)
	# навигация синхронизируется на physics-кадрах — поллим пробный путь до готовности
	for i in 120:
		await wait_physics_frames(1)
		if _path(Vector3(0, 0, 19.5), Vector3(0, 0, -19.5)).size() > 1:
			break


func after_all() -> void:
	map.queue_free()


func _path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var nav_map: RID = map.get_node("Nav").get_navigation_map()
	return NavigationServer3D.map_get_path(nav_map, from, to, true)


func _assert_reachable(from: Vector3, to: Vector3, label: String) -> void:
	var path := _path(from, to)
	assert_gt(path.size(), 1, label + ": путь должен существовать")
	if path.size() > 0:
		var last := path[path.size() - 1]
		assert_lt(Vector2(last.x - to.x, last.z - to.z).length(), 2.5, label + ": путь доводит до цели")


func test_attack_spawn_to_sites() -> void:
	var spawn := Vector3(0, 0, 19.5)   # спавн атаки (duel)
	_assert_reachable(spawn, Vector3(-19, 0, -9), "атака → сайт A")
	_assert_reachable(spawn, Vector3(19, 0, -9), "атака → сайт B")


func test_defend_spawn_to_sites() -> void:
	var spawn := Vector3(0, 0, -19.5)  # спавн защиты (duel)
	_assert_reachable(spawn, Vector3(-19, 0, -9), "защита → сайт A")
	_assert_reachable(spawn, Vector3(19, 0, -9), "защита → сайт B")


func test_spawn_to_spawn() -> void:
	_assert_reachable(Vector3(0, 0, 19.5), Vector3(0, 0, -19.5), "спавн → спавн (мид)")
