# Логика Кровопира (хост): авторитетная проверка трупа + мгновенный хил + HoT.
extends Node

var data := {}  # {owner_path, fed}


func _ready() -> void:
	var owner_node := get_node_or_null(NodePath(String(data["owner_path"]))) as Node3D
	var mt := Match.find(get_tree())
	if owner_node and mt and mt.corpse_near(owner_node.global_position, String(owner_node.get("team")), float(Balance.ABILITY["BLOODFEAST_R"])):
		var fed := bool(data.get("fed", false))
		var instant := int(Balance.ABILITY["BLOODFEAST_FED"] if fed else Balance.ABILITY["BLOODFEAST_INSTANT"])
		var rate := float(Balance.ABILITY["BLOODFEAST_HOT_FED"] if fed else Balance.ABILITY["BLOODFEAST_HOT"])
		var fx := get_node("/root/Fx")
		fx.call("apply_heal", owner_node, instant)
		var hot: Node = (load("res://src/agents/effects/hot.gd") as GDScript).new()
		hot.set("data", { "target_path": String(owner_node.get_path()), "rate": rate, "dur": float(Balance.ABILITY["BLOODFEAST_HOT_TIME"]) })
		get_tree().current_scene.add_child(hot)
	queue_free()
