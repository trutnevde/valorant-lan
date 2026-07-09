# Мишень на полигоне: три шейпа (голова/корпус/ноги) — та же разметка, что в веб-hitreg.
# Валится при 0 HP и встаёт через пару секунд.
class_name TargetDummy
extends StaticBody3D

var hp := 100
var _shape_part: Dictionary = {}  # shape_idx -> "head"|"body"|"leg"

signal died


func _ready() -> void:
	# порядок детей-CollisionShape3D фиксирован сценой: 0=body, 1=head, 2=leg
	var idx := 0
	for c in get_children():
		if c is CollisionShape3D:
			_shape_part[idx] = String(c.name).to_lower()
			idx += 1


func part_at(shape_idx: int) -> String:
	var nm: String = _shape_part.get(shape_idx, "body")
	if nm.contains("head"):
		return "head"
	if nm.contains("leg"):
		return "leg"
	return "body"


func take_hit(dmg: int, _part: String) -> void:
	hp -= dmg
	if hp <= 0:
		died.emit()
		hp = 100
		rotation.x = -PI / 2  # упала
		var tw := create_tween()
		tw.tween_interval(1.5)
		tw.tween_property(self, "rotation:x", 0.0, 0.25)  # встала
