# Санити сети (2 headless-процесса): коннект → регистрация в реестре →
# клиент репортит хит → ХОСТ применяет → HP синкается обратно клиенту.
# Это и есть авторитет-петля G4 (паритет вебу).
#   сервер: godot --headless --path . -s res://tools/netcheck.gd -- --mode=server
#   клиент: godot --headless --path . -s res://tools/netcheck.gd -- --mode=client
extends SceneTree

const PORT := 27017
const TIMEOUT := 20.0

var mode := "server"
var dummy: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.substr(7)
	# в -s скриптах автолоады НЕ грузятся — поднимаем Net руками под тем же именем
	var net: Node = (load("res://src/net/net.gd") as GDScript).new()
	net.name = "Net"
	root.add_child(net)
	# одинаковая нода-мишень на обоих концах (одинаковый путь → _sync_hp находит её)
	dummy = Node.new()
	dummy.name = "NetDummy"
	dummy.set_script(load("res://tools/netcheck_dummy.gd"))
	root.add_child(dummy)
	await process_frame
	if mode == "server":
		_run_server()
	else:
		_run_client()


func _net() -> Node:
	return root.get_node("/root/Net")


func _run_server() -> void:
	var err: Error = _net().call("host", PORT)
	if err != OK:
		print("NETCHECK SRV: host FAIL ", err)
		quit(1)
		return
	print("NETCHECK SRV: hosted on ", PORT)
	var t0 := Time.get_ticks_msec()
	# ждём регистрацию клиента
	while (_net().get("players") as Dictionary).size() < 2:
		await process_frame
		if Time.get_ticks_msec() - t0 > TIMEOUT * 1000:
			print("NETCHECK SRV: TIMEOUT waiting client")
			quit(1)
			return
	print("NETCHECK SRV: client registered, players=", (_net().get("players") as Dictionary).size())
	# ждём применения хита (клиент зарепортит; хост применит к NetDummy)
	while int(dummy.get("hp")) >= 100:
		await process_frame
		if Time.get_ticks_msec() - t0 > TIMEOUT * 1000:
			print("NETCHECK SRV: TIMEOUT waiting hit")
			quit(1)
			return
	print("NETCHECK SRV: hit applied, hp=", dummy.get("hp"))
	await create_timer(1.0).timeout  # дать hp-синку долететь до клиента
	print("NETCHECK SRV: OK")
	quit(0)


func _run_client() -> void:
	await create_timer(1.0).timeout  # серверу время подняться
	var err: Error = _net().call("join", "127.0.0.1", PORT)
	if err != OK:
		print("NETCHECK CLI: join FAIL ", err)
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	while (_net().get("players") as Dictionary).size() < 2:
		await process_frame
		if Time.get_ticks_msec() - t0 > TIMEOUT * 1000:
			print("NETCHECK CLI: TIMEOUT register")
			quit(1)
			return
	print("NETCHECK CLI: registered, reporting hit")
	_net().rpc_id(1, "report_hit", dummy.get_path(), 30, "body", NodePath(), "")  # RPC не подставляет дефолты — все 5 аргументов
	# ждём, пока хост применит и синканёт hp обратно
	while int(dummy.get("hp")) != 70:
		await process_frame
		if Time.get_ticks_msec() - t0 > TIMEOUT * 1000:
			print("NETCHECK CLI: TIMEOUT hp sync, hp=", dummy.get("hp"))
			quit(1)
			return
	print("NETCHECK CLI: hp synced to 70 — authority loop works")
	print("NETCHECK CLI: OK")
	quit(0)
