# Камера вьюмодели: второй проход рендера ТОЛЬКО для рук и ствола (слой VIEW_LAYER) с узким
# FOV, как в классических FPS. Стволы настоящего размера при этом не закрывают пол-экрана,
# а руки не проваливаются в стены — вьюмодель рисуется поверх мира в своём SubViewport
# (прозрачный фон, тот же World3D: свет, тени, туман и тонмап общие).
#
# Каждый кадр копирует положение основной камеры игрока и её качество (MSAA, масштаб —
# их меняет клавиша P через Quality), чтобы два прохода не расходились.
class_name ViewmodelCamera
extends Camera3D

const FOV_VIEW := 55.0
const VIEW_LAYER := 2

var _main: Camera3D
var _vp: SubViewport


func _ready() -> void:
	fov = FOV_VIEW
	near = 0.01
	far = 12.0
	cull_mask = VIEW_LAYER
	process_priority = 100  # после движения игрока в этом же кадре
	_vp = get_parent() as SubViewport
	current = true


# камера своего игрока ищется лениво: _ready детей идёт раньше @onready родителя-игрока
func _find_main() -> Camera3D:
	var n: Node = self
	while n != null and not (n is FpsPlayer):
		n = n.get_parent()
	return n.get_node_or_null("Head/Camera3D") as Camera3D if n else null


func _process(_dt: float) -> void:
	if _main == null:
		_main = _find_main()
		if _main == null:
			return
	# вьюмодель — только пока мир смотрит глазами игрока (обзорная камера пруфов/спектатора — без неё)
	var active := get_tree().root.get_camera_3d()
	var mine := active == _main
	var layer := _vp.get_parent() as CanvasItem if _vp else null
	if layer and layer.visible != mine:
		layer.visible = mine
	if not mine:
		return
	global_transform = _main.global_transform
	if _vp:
		var root := get_tree().root
		if _vp.msaa_3d != root.msaa_3d:
			_vp.msaa_3d = root.msaa_3d
		if _vp.screen_space_aa != root.screen_space_aa:
			_vp.screen_space_aa = root.screen_space_aa
		if _vp.scaling_3d_scale != root.scaling_3d_scale:
			_vp.scaling_3d_scale = root.scaling_3d_scale
