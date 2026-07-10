# Сова C «Шок-стрела» — стрела-разряд с ТВИСТОМ: рикошет от стены (отражение по нормали).
class_name SovaShock
extends Ability


func _init() -> void:
	char_id = "sova"
	key = "C"


func cast() -> void:
	var origin := player.eye_pos()
	var dir := player.aim_dir()
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 30.0)
	q.exclude = [player.get_rid()]
	var res := space.intersect_ray(q)
	var to := origin + dir * 30.0
	if not res.is_empty():
		# рикошет: отражаемся от поверхности и летим дальше (web-твист)
		var hit: Vector3 = res["position"]
		var nrm: Vector3 = res["normal"]
		var refl := dir.bounce(nrm).normalized()
		var remain := maxf(2.0, 30.0 - origin.distance_to(hit))
		var q2 := PhysicsRayQueryParameters3D.create(hit + refl * 0.06, hit + refl * remain)
		var res2 := space.intersect_ray(q2)
		to = (res2["position"] as Vector3) if not res2.is_empty() else hit + refl * remain
	to.y = maxf(0.0, to.y)
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/sova_arrow.gd",
		"fx": origin.x, "fy": origin.y, "fz": origin.z,
		"tx": to.x, "ty": to.y, "tz": to.z,
		"mode": "shock", "team": player.team,
		"owner_path": String(player.get_path()),
		"cname": "Arrow_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()],
	})
