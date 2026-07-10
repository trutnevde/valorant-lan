# HoT-тикер (хост): реген цели rate HP/с до истечения (Кровопир Дениса).
extends Node

var data := {}  # {target_path, rate, dur}
var _life := 0.0
var _acc := 0.0


func _physics_process(dt: float) -> void:
	_life += dt
	if _life >= float(data["dur"]):
		queue_free()
		return
	var target := get_node_or_null(NodePath(String(data["target_path"])))
	if target == null or int(target.get("hp")) <= 0:
		queue_free()
		return
	_acc += float(data["rate"]) * dt
	if _acc >= 1.0:
		var whole := int(_acc)
		_acc -= whole
		get_node("/root/Fx").call("apply_heal", target, whole)
