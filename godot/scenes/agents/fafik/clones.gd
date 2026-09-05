# Фафик X «Клоны бати» (УЛЬТА): 5 клонов бегут к отмеченной точке, сам без стрельбы;
# повторное X — распустить и вернуть стрельбу. Лопнутый клон станит по области.
# Цель задаётся кликом по тактической карте (map_target), как в вебе — G9 закрыл заглушку
# «по точке прицела». Повторное X при активной ульте распускает клонов без карты.
class_name FafikClones
extends Ability

var active := false
var _clone_names: Array[String] = []


func _init() -> void:
	char_id = "fafik"
	key = "X"


func _physics_process(_dt: float) -> void:
	if player == null or player.dead:
		return
	if not Input.is_action_just_pressed("ability_x"):
		return
	if active:
		_dismiss()
		return
	var cost := int(Balance.CHARACTERS[char_id]["ultCost"])
	if player.ult < cost:
		return
	# цель — клик по тактической карте (паритет вебу); ульта спишется в подтверждении
	var hud := player.get_node_or_null("HUD")
	if hud and hud.has_method("request_map_target"):
		hud.call("request_map_target", self)
		return
	player.ult = 0
	cast()
	used.emit(charges)


func cast() -> void:
	active = true
	var target := ground_point(40.0)
	var fx := get_node("/root/Fx")
	var base := player.global_position
	for i in int(Balance.ABILITY["CLONES_COUNT"]):
		var ang := (i - 2) * 0.25  # веер
		var dir := (target - base).normalized().rotated(Vector3.UP, ang)
		var cname := "Clone_ult_%d_%d" % [multiplayer.get_unique_id(), i]
		_clone_names.append(cname)
		fx.call("cast", "clone_decoy", {
			"x": base.x + dir.x * 1.2, "z": base.z + dir.z * 1.2,
			"dirx": dir.x, "dirz": dir.z,
			"mode": "run", "life": float(Balance.ABILITY["CLONES_TIME"]),
			"speed": float(Balance.ABILITY["CLONES_SPEED"]),
			"owner_path": String(player.get_path()),
			"cname": cname,
		})
	# сам — «клон»: стрелять нельзя
	var rig := player.get_node("WeaponRig") as WeaponRig
	rig.set_physics_process(false)
	var vm := player.get_node_or_null("Head/Viewmodel") as Node3D
	if vm:
		vm.visible = false


func _dismiss() -> void:
	active = false
	var fx := get_node("/root/Fx")
	for cname in _clone_names:
		fx.call("cast", "clone_gone_req", { "cname": cname })
	_clone_names.clear()
	var rig := player.get_node("WeaponRig") as WeaponRig
	rig.set_physics_process(true)
	var vm := player.get_node_or_null("Head/Viewmodel") as Node3D
	if vm:
		vm.visible = true
