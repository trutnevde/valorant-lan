# Компайл-безопасный доступ к сетевому синглтону Net (autoload).
# Прямой идентификатор Net не резолвится в --check-only и в -s скриптах (там автолоады
# не грузятся) — class_name NetHub резолвится всегда, ноду ищем в рантайме.
class_name NetHub


static func node() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null:
		return null
	return ml.root.get_node_or_null("Net")


static func online() -> bool:
	var n := node()
	return n != null and bool(n.call("is_online"))


static func is_host() -> bool:
	var n := node()
	return n == null or bool(n.call("is_host"))


static func report_hit(target: Node, dmg: int, part: String, attacker: Node = null, weapon := "") -> void:
	var n := node()
	if n:
		n.rpc_id(1, "report_hit", target.get_path(), dmg, part,
			attacker.get_path() if attacker else NodePath(), weapon)
