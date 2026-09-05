extends Node3D
# model_gallery — галерея моделей для выбора ассетов: --dir=res://... (все .obj/.fbx/.glb в папке)
# в ряд, каждая вписана в 1 м. Запуск через agent_eyes: --scene=res://tools/model_gallery.tscn --dir=...
func _ready() -> void:
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.substr(6)
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		var e := f.get_extension().to_lower()
		if e in ["obj", "fbx", "glb", "gltf"]:
			files.append(f)
	files.sort()
	var x := 0.0
	for f in files:
		var res = load(dir.path_join(f))
		var n: Node3D = null
		if res is PackedScene:
			n = (res as PackedScene).instantiate() as Node3D
		elif res is Mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = res
			n = mi
		if n == null:
			print("GAL пропуск ", f)
			continue
		var holder := Node3D.new()
		add_child(holder)
		holder.add_child(n)
		var box := WeaponModels.local_aabb(holder)
		var s := 1.0 / maxf(0.001, box.size[box.size.max_axis_index()])
		n.scale = Vector3.ONE * s
		n.position = -(box.position + box.size * 0.5) * s
		holder.position = Vector3(x, 0, 0)
		x += 1.3
		var mats: Array = []
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for si in m.mesh.get_surface_count() if m.mesh else 0:
				var mat := m.get_active_material(si)
				mats.append("tex" if (mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture) else ("col" if mat else "none"))
		print("GAL ", f, " size=", box.size, " mats=", mats.slice(0, 6))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.33, 0.38)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment = e
	add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(-0.7, 0.6, 0)
	add_child(l)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var mid := (x - 1.3) * 0.5
	cam.position = Vector3(mid, 0.35, maxf(2.5, x * 0.72))
	cam.look_at(Vector3(mid, 0, 0), Vector3.UP)
	cam.current = true
