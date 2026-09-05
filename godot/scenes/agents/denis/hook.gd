# Денис X «Мясной крюк» (УЛЬТА): попал по врагу — кокон тащит его к Денису 2.6с;
# союзники жертвы могут отстрелить кокон (150 HP). Дотащил — разделал.
class_name DenisHook
extends Ability


func _init() -> void:
	char_id = "denis"
	key = "X"


# Промахнуться МОЖНО — раньше can_cast() требовал мгновенного попадания рейкастом, и
# ульта просто не тратилась без цели. Крюк теперь снаряд, у ошибки есть цена.
func cast() -> void:
	var eye := player.eye_pos()
	var dir := player.aim_dir()
	get_node("/root/Fx").call("cast", "generic", {
		"logic": "res://src/agents/effects/hook_projectile.gd",
		"fx": eye.x, "fy": eye.y, "fz": eye.z,
		"dx": dir.x, "dy": dir.y, "dz": dir.z,
		"by_path": String(player.get_path()),
		"cname": "Cocoon_%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()],
	})
