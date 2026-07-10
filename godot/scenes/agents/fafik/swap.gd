# Фафик E «Рокировка» — пускает бегущего клона; повторное E — мгновенный обмен местами.
# Ввод обрабатываем сами (re-press не тратит заряд) — базовый цикл Ability не подходит.
class_name FafikSwap
extends Ability

var _clone_name := ""
var _cast_at := -99.0


func _init() -> void:
	char_id = "fafik"
	key = "E"


func _physics_process(_dt: float) -> void:
	if player == null or player.dead:
		return
	if not Input.is_action_just_pressed("ability_e"):
		return
	var alive := _clone_alive()
	if alive:
		_do_swap(alive)
	elif charges > 0 and can_cast():
		charges -= 1
		cast()
		used.emit(charges)


func _clone_alive() -> Node3D:
	if _clone_name == "" or _now() - _cast_at > float(Balance.ABILITY["SWAP_LIFE"]):
		return null
	return get_tree().current_scene.get_node_or_null(_clone_name) as Node3D


func cast() -> void:
	var fwd := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	_clone_name = "Clone_swap_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()]
	_cast_at = _now()
	get_node("/root/Fx").call("cast", "clone_decoy", {
		"x": player.global_position.x, "z": player.global_position.z,
		"dirx": fwd.x, "dirz": fwd.z,
		"mode": "run", "life": float(Balance.ABILITY["SWAP_LIFE"]),
		"max_run": float(Balance.ABILITY["SWAP_DECOY_RANGE"]),
		"owner_path": String(player.get_path()),
		"cname": _clone_name,
	})


func _do_swap(clone: Node3D) -> void:
	# блинк: меняемся местами с клоном (движение клиент-авторитарно)
	var my_pos := player.global_position
	player.global_position = clone.global_position
	player.velocity = Vector3.ZERO
	# клон встаёт туда, где был игрок, и остаётся приманкой
	get_node("/root/Fx").call("cast", "clone_move", {
		"cname": _clone_name, "x": my_pos.x, "z": my_pos.z,
	})
	_clone_name = ""
