# Денис X «Мясной крюк» (УЛЬТА): попал по врагу — кокон тащит его к Денису 2.6с;
# союзники жертвы могут отстрелить кокон (150 HP). Дотащил — разделал.
class_name DenisHook
extends Ability


func _init() -> void:
	char_id = "denis"
	key = "X"


func can_cast() -> bool:
	return _target() != null


func _target() -> Node:
	var origin := player.eye_pos()
	var dir := player.aim_dir()
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * float(Balance.ABILITY["COCOON_RANGE"]))
	q.exclude = [player.get_rid()]
	var res := space.intersect_ray(q)
	if res.is_empty():
		return null
	var c := res["collider"] as Node
	if c.is_in_group("combatants") and String(c.get("team")) != player.team and int(c.get("hp")) > 0:
		return c
	return null


func cast() -> void:
	var victim := _target()
	if victim == null:
		return
	get_node("/root/Fx").call("cast", "cocoon", {
		"victim_path": String(victim.get_path()),
		"by_path": String(player.get_path()),
		"cname": "Cocoon_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()],
	})
