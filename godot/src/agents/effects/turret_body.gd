# Тело турели (у всех, стреляемое): урон пересылается хостовой логике.
class_name TurretBody
extends StaticBody3D

var cname := ""


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.9, 0.5)
	cs.shape = box
	cs.position.y = 0.45
	add_child(cs)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.8, 0.45)
	m.mesh = bm
	m.position.y = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.72, 0.3)
	m.material_override = mat
	add_child(m)


func part_at(_i: int) -> String:
	return "body"


func take_hit(dmg: int, _part: String, _attacker: Node = null, _weapon := "") -> void:
	if NetHub.online() and not multiplayer.is_server():
		return
	var logic := get_tree().current_scene.get_node_or_null(cname + "_logic")
	if logic:
		logic.call("take_body_hit", dmg)
