# «Мясной крюк» Дениса (хост): кокон тащит жертву к Денису COCOON_TIME секунд;
# союзники жертвы могут отстрелить кокон (COCOON_HP). Дотащил — разделал.
# Кокон-щит спавнится видимым у всех через Fx (имя детерминировано), урон решает хост.
extends Node

var data := {}  # {victim_path, by_path, cname}
var shield_hp := 150
var _life := 0.0


func _ready() -> void:
	shield_hp = int(Balance.ABILITY["COCOON_HP"])
	var victim := get_node_or_null(NodePath(String(data["victim_path"])))
	if victim == null:
		queue_free()
		return
	get_node("/root/Fx").call("apply_damage", victim,
		int(Balance.ABILITY["COCOON_HIT_DMG"]), get_node_or_null(NodePath(String(data["by_path"]))), "hook")


func _physics_process(dt: float) -> void:
	_life += dt
	var victim := get_node_or_null(NodePath(String(data["victim_path"]))) as Node3D
	var denis := get_node_or_null(NodePath(String(data["by_path"]))) as Node3D
	var fx := get_node("/root/Fx")
	if victim == null or denis == null or int(victim.get("hp")) <= 0 or int(denis.get("hp")) <= 0:
		_free_cocoon()
		return
	if _life >= float(Balance.ABILITY["COCOON_TIME"]):
		# дотащил — разделал
		fx.call("apply_damage", victim, 9999, denis, "hook")
		_free_cocoon()
		return
	# тянем жертву к Денису
	if victim is Bot:
		var d := denis.global_position - victim.global_position
		d.y = 0.0
		if d.length() > 1.6:
			(victim as Node3D).global_position += d.normalized() * 9.0 * dt
	elif victim is FpsPlayer:
		var n := NetHub.node()
		if NetHub.online() and n and (victim as Node).get_multiplayer_authority() != 1:
			n.rpc_id((victim as Node).get_multiplayer_authority(), "force_pull_self", denis.global_position, 0.3, 9.0)
		else:
			(victim as FpsPlayer).force_pull(denis.global_position, 0.3, 9.0)
	# щит-кокон следует за жертвой (визуал-нода у всех; хост двигает свою, клиенты — свои по синку жертвы)
	var shield := get_tree().current_scene.get_node_or_null(String(data["cname"])) as Node3D
	if shield:
		shield.global_position = victim.global_position + Vector3(0, 1.1, 0)


func take_shield_hit(dmg: int) -> void:
	shield_hp -= dmg
	if shield_hp <= 0:
		_free_cocoon()  # союзники отстрелили — жертва свободна


func _free_cocoon() -> void:
	get_node("/root/Fx").call("_fx_broadcast", "clone_gone", { "cname": String(data["cname"]) })
	queue_free()
