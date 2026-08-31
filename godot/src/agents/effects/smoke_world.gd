# Дымовой мир (autoload Smokes): единый список дымов для LOS ботов, пассивок Геры
# и «Развеятеля». Логика — хост; визуал (сферы) — у всех через Fx.
# Дым: {id, pos: Vector3, r, until, team, stink} — team нужен Гере (свой/вражеский).
extends Node

var smokes: Array[Dictionary] = []
var no_smoke_zones: Array[Dictionary] = []  # «Развеятель»: {pos, r, until, team}
var _seq := 0


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(_dt: float) -> void:
	var t := now()
	smokes = smokes.filter(func(s: Dictionary) -> bool: return t < float(s["until"]))
	no_smoke_zones = no_smoke_zones.filter(func(z: Dictionary) -> bool: return t < float(z["until"]))


# хост: поставить дым (если не заблокирован Развеятелем врага)
func add_smoke(pos: Vector3, team: String, stink: bool) -> bool:
	for z in no_smoke_zones:
		if String(z["team"]) != team and Vector2(pos.x - (z["pos"] as Vector3).x, pos.z - (z["pos"] as Vector3).z).length() < float(z["r"]):
			return false  # анти-смок зона врага — дым не встаёт
	_seq += 1
	smokes.append({
		"id": _seq, "pos": pos, "r": float(Balance.ABILITY["SMOKE_R"]),
		"until": now() + float(Balance.ABILITY["SMOKE_TIME"]), "team": team, "stink": stink,
	})
	return true


# хост: «Развеятель» Геры — убрать вражеские дымы в радиусе + блок на новые
func dispel(pos: Vector3, team: String) -> Array[int]:
	var removed: Array[int] = []
	var r := float(Balance.ABILITY["GERA_DISPEL_R"])
	smokes = smokes.filter(func(s: Dictionary) -> bool:
		var enemy := String(s["team"]) != team
		var close := Vector2((s["pos"] as Vector3).x - pos.x, (s["pos"] as Vector3).z - pos.z).length() < r + float(s["r"]) * 0.5
		if enemy and close:
			removed.append(int(s["id"]))
			return false
		return true)
	no_smoke_zones.append({ "pos": pos, "r": r, "until": now() + float(Balance.ABILITY["GERA_DISPEL_BLOCK"]), "team": team })
	return removed


# сегмент проходит сквозь дым? (LOS ботов и разведки)
func seg_blocked(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		var c: Vector3 = s["pos"]
		var r := float(s["r"])
		# расстояние от центра сферы до отрезка
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		if (a + ab * t).distance_to(c) < r:
			return true
	return false


# точка в дыму? (пассивка Геры «Охотник за туманщиками»)
func point_in_smoke(p: Vector3) -> bool:
	for s in smokes:
		var c: Vector3 = s["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(s["r"]):
			return true
	return false
