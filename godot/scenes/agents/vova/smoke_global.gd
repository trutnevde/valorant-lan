# Вова C «Дым по карте». ⚠ Отклонение (честно): в вебе — клик по карте; карта-UI в порте
# появится в G9, пока дым ставится по точке прицела с большой дальностью (40м).
class_name VovaSmoke
extends Ability


func _init() -> void:
	char_id = "vova"
	key = "C"


func cast() -> void:
	var p := ground_point(40.0)
	get_node("/root/Fx").call("cast", "smoke", { "x": p.x, "z": p.z, "team": player.team, "stink": false })
