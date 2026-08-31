# Гера Q «Крюк-кошка» — грэпл: подтяг к поверхности (клиентское движение, LOS-якорь).
class_name GeraGrapple
extends Ability


func _init() -> void:
	char_id = "gera"
	key = "Q"


func can_cast() -> bool:
	return not _anchor().is_empty()


func _anchor() -> Dictionary:
	var origin := player.eye_pos()
	var dir := player.aim_dir()
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * float(Balance.ABILITY["GERA_GRAPPLE_RANGE"]))
	q.exclude = [player.get_rid()]
	return space.intersect_ray(q)


func cast() -> void:
	var res := _anchor()
	if res.is_empty():
		return
	var to: Vector3 = (res["position"] as Vector3) - player.aim_dir() * 0.8
	to.y = maxf(0.0, (res["position"] as Vector3).y)
	var dist := player.global_position.distance_to(to)
	player.force_pull(to, maxf(0.18, dist / float(Balance.ABILITY["GERA_GRAPPLE_SPEED"])), float(Balance.ABILITY["GERA_GRAPPLE_SPEED"]))
