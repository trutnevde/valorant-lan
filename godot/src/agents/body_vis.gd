# BodyVis — силуэт бойца из примитивов: торс, голова, руки, ноги, наплечники.
#
# ЧЕСТНО (правило 8 миграции): риггованных CC0-моделей персонажей в репозитории НЕТ —
# public/assets/models/characters пуст, в манифесте characterModels: {}, лежит только
# заглушка _demo.glb. Имитировать «настоящих персонажей» нечем, поэтому вместо капсулы
# делаем ближайшее достижимое: читаемый низкополигональный силуэт с опознанием команды и
# агента. Появятся модели и AnimationTree — этот скрипт заменяется целиком.
#
# Опознание: тело красится в цвет КОМАНДЫ (мгновенное «свой/чужой» — важнее всего в бою),
# наплечники и голова — в цвет АГЕНТА из Balance.CHARACTERS (кто именно передо мной).
extends Node3D

@export var team := ""
@export var char_id := ""


func _ready() -> void:
	# владелец (Bot/FpsPlayer) — источник правды по команде и агенту
	var owner_node := get_parent()
	if owner_node:
		if team == "" and owner_node.get("team") != null:
			team = String(owner_node.get("team"))
		if char_id == "" and owner_node.get("char_id") != null:
			char_id = String(owner_node.get("char_id"))
	build()


func build() -> void:
	for c in get_children():
		c.queue_free()
	var team_col := Color(0.30, 0.55, 0.85) if team == "A" else Color(0.85, 0.35, 0.30)
	var accent := team_col
	var card: Dictionary = Balance.CHARACTERS.get(char_id, {})
	if card.has("color"):
		accent = Color(String(card["color"]))

	var body_mat := _mat(team_col, 0.75)
	var accent_mat := _mat(accent, 0.55)
	var dark_mat := _mat(team_col.darkened(0.55), 0.85)

	# торс: слегка сплюснутый бокс — плечи шире бёдер, силуэт читается с любой стороны
	_box(Vector3(0.52, 0.62, 0.30), Vector3(0, 1.24, 0), body_mat)
	# таз
	_box(Vector3(0.44, 0.24, 0.28), Vector3(0, 0.86, 0), dark_mat)
	# голова + «шлем» цветом агента
	_box(Vector3(0.24, 0.26, 0.24), Vector3(0, 1.70, 0), body_mat)
	_box(Vector3(0.27, 0.10, 0.27), Vector3(0, 1.80, 0), accent_mat)
	# наплечники — главный опознавательный знак агента
	for sx: float in [-0.34, 0.34]:
		_box(Vector3(0.16, 0.18, 0.26), Vector3(sx, 1.46, 0), accent_mat)
	# руки
	for ax: float in [-0.33, 0.33]:
		_box(Vector3(0.13, 0.46, 0.15), Vector3(ax, 1.10, 0), dark_mat)
	# ноги
	for lx: float in [-0.13, 0.13]:
		_box(Vector3(0.17, 0.76, 0.20), Vector3(lx, 0.38, 0), dark_mat)
	# «грудная пластина» — тёмный акцент, чтобы перед отличался от спины
	_box(Vector3(0.34, 0.26, 0.06), Vector3(0, 1.30, -0.17), accent_mat)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.0
	return m


func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	mi.position = pos
