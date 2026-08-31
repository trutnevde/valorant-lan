# Вспышка (логика, хост): летит FLASH_SPEED, взводится FLASH_FUSE, на попе слепит
# смотрящих — формула web abilities.js: k=(dot-0.3)/0.7, dur=0.4+k*(MAX_BLIND-0.4), LOS, <40м.
extends Node

var data := {}  # {fx,fy,fz, dx,dy,dz, owner_path}


func _ready() -> void:
	var fuse := float(Balance.ABILITY["FLASH_FUSE"])
	get_tree().create_timer(fuse).timeout.connect(_pop)


func _pop() -> void:
	var from := Vector3(data["fx"], data["fy"], data["fz"])
	var dir := Vector3(data["dx"], data["dy"], data["dz"])
	var pop := from + dir * float(Balance.ABILITY["FLASH_SPEED"]) * float(Balance.ABILITY["FLASH_FUSE"])
	var hits: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		var node := c as Node3D
		if node == null or int(node.get("hp")) <= 0:
			continue
		var eye := node.global_position + Vector3(0, 1.6, 0)
		var to := pop - eye
		var dist := to.length()
		if dist > 40.0 or dist < 0.1:
			continue
		var look := -node.global_transform.basis.z
		var dot := to.normalized().dot(look)
		if dot < 0.3:
			continue  # не смотрит — не слепнет
		if not _los(eye, pop, node):
			continue
		var k := (dot - 0.3) / 0.7
		hits.append({ "node": node, "dur": 0.4 + k * (float(Balance.ABILITY["FLASH_MAX_BLIND"]) - 0.4) })
	var fx := get_node("/root/Fx")
	fx.call("blind_targets", pop, hits)
	queue_free()


func _los(from: Vector3, to: Vector3, exclude_node: Node3D) -> bool:
	var space := (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if exclude_node is CollisionObject3D:
		q.exclude = [(exclude_node as CollisionObject3D).get_rid()]
	var res := space.intersect_ray(q)
	return res.is_empty()
