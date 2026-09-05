# Вова C «Дым по карте» — ставится КЛИКОМ ПО ТАКТИЧЕСКОЙ КАРТЕ, как в вебе
# (G9 закрыл заглушку «по точке прицела»).
class_name VovaSmoke
extends Ability


func _init() -> void:
	char_id = "vova"
	key = "C"
	map_target = true


func cast() -> void:
	var p := ground_point(40.0)
	get_node("/root/Fx").call("cast", "smoke", { "x": p.x, "z": p.z, "team": player.team, "stink": false })
