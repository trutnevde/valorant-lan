# Щит-кокон (видим и стреляем у всех): урон пересылается хостовой логике кокона.
class_name CocoonShield
extends StaticBody3D

var cname := ""


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.85
	cs.shape = sph
	add_child(cs)
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.85
	mesh.height = 1.7
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.75, 0.35, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	add_child(m)


func part_at(_i: int) -> String:
	return "body"


func take_hit(dmg: int, _part: String, _attacker: Node = null, _weapon := "") -> void:
	if NetHub.online() and not multiplayer.is_server():
		return  # решает хост (урон приходит через report_hit по пути этой ноды)
	var logic := get_tree().current_scene.get_node_or_null(cname + "_logic")
	if logic:
		logic.call("take_shield_hit", dmg)
