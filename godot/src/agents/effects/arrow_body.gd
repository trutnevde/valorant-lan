# Тело разведстрелы Совы (у всех, стреляемое) — ТВИСТ: сбил в полёте → разведки не будет.
class_name ArrowBody
extends StaticBody3D

var cname := ""


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.22
	cs.shape = sph
	add_child(cs)


func part_at(_i: int) -> String:
	return "body"


func take_hit(_dmg: int, _part: String, _attacker: Node = null, _weapon := "") -> void:
	if NetHub.online() and not multiplayer.is_server():
		return  # решает хост
	var logic := get_tree().current_scene.get_node_or_null(cname + "_logic")
	if logic:
		logic.set("shot_down", true)