# Мишень для netcheck: hp + take_hit (утиный интерфейс урона).
extends Node

var hp := 100

signal hp_changed(hp: int)


func take_hit(dmg: int, _part: String) -> void:
	hp -= dmg
	hp_changed.emit(hp)
