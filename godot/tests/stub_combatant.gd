# Стаб бойца для тестов матча: team/hp/экономика/кит-поля + утиный интерфейс.
extends Node3D

var team := "A"
var hp := 100
var credits := 0
var kills := 0
var deaths := 0
var ult := 0
var char_id := "max"
var last_weapon := ""


func round_reset() -> void:
	hp = 100


func give_weapon(id: String) -> void:
	last_weapon = id
