extends Node3D
# viewmodel_stand — стенд вьюмодели: камера игрока в нуле, ствол + ArmsRig как в игре, без карты.
# Запуск: godot --path . res://tools/agent_eyes.tscn -- --scene=res://tools/viewmodel_stand.tscn --out=<png> \
# --gun=<id> --view=fps|iso|side|top|left --gs=<масштаб ствола> --gp=x,y,z --sh=x,y,z (плечи в пространстве головы)
func _ready() -> void:
	var view := "fps"
	var gun_id := "classic"
	var gs := 1.0
	var gp := Vector3.ZERO
	var sh := Vector3(0.0, -0.2, 0.05)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			view = arg.substr(7)
		elif arg.begins_with("--gun="):
			gun_id = arg.substr(6)
		elif arg.begins_with("--gs="):
			gs = float(arg.substr(5))
		elif arg.begins_with("--gp="):
			var v := arg.substr(5).split(",")
			gp = Vector3(float(v[0]), float(v[1]), float(v[2]))
		elif arg.begins_with("--sh="):
			var v := arg.substr(5).split(",")
			sh = Vector3(float(v[0]), float(v[1]), float(v[2]))
	var gun := WeaponModels.make(gun_id)
	var base := Viewmodel.place_for(WeaponModels.local_aabb(gun))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--base="):
			var v := arg.substr(7).split(",")
			base = Vector3(float(v[0]), float(v[1]), float(v[2]))
	var vm := Node3D.new()
	vm.name = "Viewmodel"
	vm.position = base
	add_child(vm)
	gun.scale = Vector3.ONE * gs
	gun.position = gp
	vm.add_child(gun)
	var arms := ArmsRig.new()
	arms.position = sh - base
	vm.add_child(arms)
	arms.build(false)
	arms.hold(gun)
	var box := WeaponModels.local_aabb(gun)
	print("STAND gun ", gun_id, " aabb lo=", box.position, " size=", box.size)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.36, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(-0.9, 0.4, 0)
	add_child(l)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.01
	add_child(cam)
	match view:
		"iso":
			cam.position = Vector3(0.9, 0.5, 0.3)
			cam.look_at(base + gp, Vector3.UP)
		"side":
			cam.position = Vector3(1.3, -0.1, -0.35)
			cam.look_at(base + gp, Vector3.UP)
		"left":
			cam.position = Vector3(-0.9, 0.1, -0.2)
			cam.look_at(base + gp, Vector3.UP)
		"top":
			cam.position = Vector3(0.1, 1.2, -0.3)
			cam.look_at(base + gp, Vector3(0, 0, -1))
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	var sk := arms.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for nm in ["upper_arm.R", "forearm.R", "forearm.R_end", "hand.R", "hand.L", "forearm.L_end"]:
		var bi := sk.find_bone(nm)
		print("STAND ", nm, " world=", (sk.global_transform * sk.get_bone_global_pose(bi)).origin)
	print("STAND WristR=", (arms.get_node("WristR") as Node3D).global_position, " WristL=", (arms.get_node("WristL") as Node3D).global_position)
