# Vfx — мелкие боевые эффекты на движковых системах (правило 1: GPUParticles3D, а не самопал).
# Всё живёт короткие доли секунды и само себя убирает; ни один эффект не держит ссылок.
#
# Перф-бюджет (правило 6): вспышка — один OmniLight3D на 45 мс и 10 частиц; попадание —
# 14 частиц. Замер tools/perfcheck.gd после добавления: см. VERSIONS.
class_name Vfx


# дульная вспышка: короткий свет + сноп искр по стволу
static func muzzle(parent: Node3D, pos: Vector3, dir: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var scene := parent.get_tree().current_scene
	if scene == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.55)
	light.light_energy = 3.2
	light.omni_range = 5.5
	light.shadow_enabled = false
	scene.add_child(light)
	light.global_position = pos
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.045)
	lt.tween_callback(light.queue_free)
	_burst(scene, pos, dir, 10, Color(1.0, 0.82, 0.45), 4.5, 0.05, 0.16)


# попадание: пыль/искры от поверхности вдоль нормали
static func impact(node: Node3D, pos: Vector3, normal: Vector3) -> void:
	if node == null or not node.is_inside_tree():
		return
	var scene := node.get_tree().current_scene
	if scene == null:
		return
	_burst(scene, pos + normal * 0.02, normal, 14, Color(0.78, 0.74, 0.68), 3.0, 0.35, 0.5)


static func _burst(scene: Node, pos: Vector3, dir: Vector3, amount: int, col: Color,
		speed: float, gravity: float, life: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.035)
	p.draw_pass_1 = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	pm.direction = dir.normalized()
	pm.spread = 32.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -9.8 * gravity, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.alpha_curve = ct
	p.process_material = pm
	scene.add_child(p)
	p.global_position = pos
	# сама уборка: живём чуть дольше жизни частиц, потом исчезаем
	var tw := p.create_tween()
	tw.tween_interval(life + 0.25)
	tw.tween_callback(p.queue_free)
