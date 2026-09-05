# Оружейное ядро: hitscan, разброс/отдача/спад урона — паритет 1:1 с web weapons.js.
# Числа стволов только из Balance.WEAPONS. RNG инъектируемый (детерминизм для GUT).
class_name WeaponRig
extends Node3D

const ADS_SPEED := 10.0        # скорость входа в прицел (web: aimT lerp)
const HEAD_Y := 1.5            # верх капсулы мишени — метки part на шейпах решают точнее

@onready var player: FpsPlayer = get_parent() as FpsPlayer
@onready var shot_sfx: AudioStreamPlayer3D = $ShotSfx
@onready var dry_sfx: AudioStreamPlayer = $DrySfx
@onready var reload_sfx: AudioStreamPlayer = $ReloadSfx
@onready var hit_sfx: AudioStreamPlayer = $HitSfx

var rng := RandomNumberGenerator.new()
var current_id := "classic"
var loadout := { "primary": "", "sidearm": "classic" }  # слоты (web-паритет)
var ammo := {}                # id -> {mag, reserve}
var last_shot := -99.0
var spray_idx := 0
var reloading_until := -1.0
var ready_at := 0.0
var vkick_pos := 0.0          # толчок вьюмодели
var vkick_rot := 0.0

var _shot_streams := {}       # sample -> AudioStream
# «Стальные перья» Макса: 5 ножей 70/150, 12с; килл обновляет
var knives_count := 0
var knives_until := 0.0

signal fired
signal hit_target(part: String, dmg: int)


func start_knives() -> void:
	knives_count = int(Balance.ABILITY["KNIVES_COUNT"])
	knives_until = _now() + float(Balance.ABILITY["KNIVES_TIME"])


func knives_active() -> bool:
	return knives_count > 0 and _now() < knives_until

const SHOT_SAMPLE := {
	"classic": "gun_pistol", "ghost": "gun_pistol", "frenzy": "gun_pistol",
	"stinger": "gun_pistol", "spectre": "gun_pistol",
	"sheriff": "gun_magnum", "guardian": "gun_magnum", "marshal": "gun_magnum",
	"bucky": "gun_heavy", "judge": "gun_heavy", "shorty": "gun_heavy", "operator": "gun_heavy", "outlaw": "gun_heavy",
	"ares": "gun_rifle", "odin": "gun_rifle", "bulldog": "gun_rifle", "phantom": "gun_rifle", "vandal": "gun_rifle",
}


func _ready() -> void:
	rng.randomize()
	for s in ["gun_pistol", "gun_magnum", "gun_heavy", "gun_rifle"]:
		_shot_streams[s] = load("res://assets/audio/%s.wav" % s)
	dry_sfx.stream = load("res://assets/audio/ui_click.wav")
	get_node("/root/Ears").call("register", shot_sfx, "SFX", player)  # окклюзия выстрела
	equip(current_id)


func w() -> Dictionary:
	return Balance.WEAPONS[current_id]


# покупка/выдача: кладёт в слот по типу и берёт в руки (свежий боезапас)
func give_weapon(id: String) -> void:
	var wd: Dictionary = Balance.WEAPONS.get(id, {})
	if wd.is_empty():
		return
	loadout["primary" if String(wd["slot"]) == "primary" else "sidearm"] = id
	ammo[id] = { "mag": int(wd["mag"]), "reserve": int(wd["reserve"]) }
	equip(id)


func reset_loadout() -> void:
	loadout = { "primary": "", "sidearm": "classic" }
	ammo.clear()
	equip("classic")


func equip(id: String) -> void:
	# Смена ствола ОТМЕНЯЕТ перезарядку — иначе это бесплатный мгновенный релоад в один
	# хоткей: жмёшь 2 и 1, и магазин полон без ожидания.
	reloading_until = -1.0
	current_id = id
	if not ammo.has(id) and not bool(w().get("melee", false)):
		ammo[id] = { "mag": int(w()["mag"]), "reserve": int(w()["reserve"]) }
	ready_at = _now() + float(Balance.weapon_feel(id)["equip"])
	spray_idx = 0
	player.weapon_speed = float(Balance.weapon_feel(id)["speed"])


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(dt: float) -> void:
	# ADS: зум + замедление (adsFov из web weapons.js:134)
	var want_ads := Input.is_action_pressed("ads") and reloading_until < _now()
	player.aim_t = clampf(player.aim_t + (1.0 if want_ads else -1.0) * dt * ADS_SPEED, 0.0, 1.0)
	var target_fov := lerpf(player.BASE_FOV, _ads_fov(), player.aim_t)
	player.cam.fov = target_fov

	# вьюмодель-кик затухает
	vkick_pos = maxf(0.0, vkick_pos - dt * 0.14)
	vkick_rot = maxf(0.0, vkick_rot - dt * 0.25)
	var vm := get_node_or_null("../Head/Viewmodel") as Node3D
	if vm:
		vm.position.z = 0.0 + vkick_pos
		vm.rotation.x = vkick_rot

	if reloading_until > 0.0 and _now() >= reloading_until:
		reloading_until = -1.0
		var a: Dictionary = ammo[current_id]
		var need := int(w()["mag"]) - int(a["mag"])
		var take := mini(need, int(a["reserve"]))
		a["mag"] = int(a["mag"]) + take
		a["reserve"] = int(a["reserve"]) - take

	if Input.is_action_pressed("fire"):
		try_shoot(Input.is_action_just_pressed("fire"))
	if Input.is_action_just_pressed("reload"):
		reload()
	# слоты: 1 — основное, 2 — пистолет, 3 — нож (web-паритет)
	if Input.is_action_just_pressed("slot1") and loadout["primary"] != "":
		equip(String(loadout["primary"]))
	elif Input.is_action_just_pressed("slot2"):
		equip(String(loadout["sidearm"]))
	elif Input.is_action_just_pressed("slot3"):
		equip("knife")


func _ads_fov() -> float:
	var wd := w()
	if bool(wd.get("scope", false)):
		return 22.0 if current_id == "operator" else 30.0
	match String(wd["cat"]):
		"pistol": return 62.0
		"shotgun": return 64.0
		_: return 55.0


func try_shoot(is_click: bool) -> void:
	var t := _now()
	# паритет web canAct (weapons.js:82): мёртвым, в закупке, в стане и на тяге не стреляют.
	# Раньше проверки не было — клик по кнопке в buy-меню одновременно жал на курок.
	if not player.can_act():
		return
	if reloading_until > _now() or t < ready_at:
		return
	# ножи Макса перекрывают обычное оружие (web weapons.js:147)
	if knives_active():
		if t - last_shot < 0.28:
			return
		last_shot = t
		knives_count -= 1
		_fire_knife()
		fired.emit()
		return
	var wd := w()
	if not bool(wd.get("auto", false)) and not is_click:
		return
	if t - last_shot < 60.0 / float(wd["rpm"]):
		return
	if not bool(wd.get("melee", false)):
		var a: Dictionary = ammo[current_id]
		if int(a["mag"]) <= 0:
			if is_click:
				dry_sfx.play()
				reload()
			return
		a["mag"] = int(a["mag"]) - 1
	if t - last_shot > 0.35:
		spray_idx = 0  # сброс спрея после паузы (web weapons.js:168)
	last_shot = t
	shoot()


func reload() -> void:
	var wd := w()
	if bool(wd.get("melee", false)) or reloading_until > _now():
		return
	var a: Dictionary = ammo[current_id]
	if int(a["mag"]) >= int(wd["mag"]) or int(a["reserve"]) <= 0:
		return
	reloading_until = _now() + float(wd["reload"])
	reload_sfx.stream = load("res://assets/audio/reload%d.wav" % (1 + randi() % 2))
	reload_sfx.play()


# разброс — формула web weapons.js spread() 1:1
func spread() -> float:
	var wd := w()
	var s := float(wd["spread"])
	if player.crouch:
		s *= 0.65
	var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var cat := String(wd["cat"])
	var move_penalty := 5.0 if cat == "sniper" else (3.0 if cat == "rifle" else 2.2)
	s *= 1.0 + minf(1.0, h_speed / 6.2) * move_penalty
	if not player.is_on_floor():
		s *= 4.0
	if bool(wd.get("auto", false)) and spray_idx > 3:
		s *= 1.0 + minf(1.2, (spray_idx - 3) * 0.06)
	var ads_min := (float(wd["scopeSpread"]) / float(wd["spread"])) if bool(wd.get("scope", false)) else 0.4
	s *= (1.0 - player.aim_t * (1.0 - ads_min))
	return s


# отдача — формула web weapons.js applyRecoil() 1:1
func apply_recoil() -> void:
	var wd := w()
	var recoil := float(wd["recoil"])
	var idx := spray_idx
	var aim_reduce := 1.0 - player.aim_t * 0.28
	var kick := recoil * (0.68 if idx < 3 else 0.92) * (1.0 + minf(0.65, idx * 0.05)) * aim_reduce
	var drift := ((recoil * 0.5 * sin(idx * 0.65) + (rng.randf() - 0.5) * recoil * 0.28) if idx > 5 else ((rng.randf() - 0.5) * recoil * 0.13)) * aim_reduce
	player.punch_pitch += kick
	player.punch_yaw += drift
	player.pitch = minf(1.55, player.pitch + kick * 0.26)  # часть оседает в прицеле
	vkick_pos += 0.018 + recoil * 2.2
	vkick_rot += 0.03 + recoil * 3.4
	spray_idx += 1


func falloff_mult(dist: float) -> float:
	var wd := w()
	if not wd.has("falloffStart") or dist <= float(wd["falloffStart"]):
		return 1.0
	var k := minf(1.0, (dist - float(wd["falloffStart"])) / 25.0)
	return 1.0 - k * (1.0 - float(wd.get("falloffMin", 0.8)))


func shoot() -> void:
	var wd := w()
	var pellets := int(wd.get("pellets", 1))
	for i in pellets:
		_fire_ray()
	apply_recoil()
	_play_shot()
	fired.emit()
	player.made_noise.emit(true)  # выстрел громкий: боты его слышат за 28 м
	if NetHub.online():
		_remote_shot.rpc(current_id)  # остальные пиры слышат выстрел позиционно


@rpc("authority", "unreliable")
func _remote_shot(id: String) -> void:
	var sample: String = SHOT_SAMPLE.get(id, "gun_rifle")
	shot_sfx.stream = _shot_streams[sample]
	shot_sfx.pitch_scale = 0.95 + rng.randf() * 0.1
	shot_sfx.play()


func _fire_ray() -> void:
	var origin := player.eye_pos()
	var dir := player.aim_dir()
	var s := spread()
	# Разброс — ДИСК В ПЛОСКОСТИ ПРИЦЕЛА, а не куб по мировым осям: кубом разброс зависел
	# от того, куда смотришь (по диагонали мира он был шире), и по вертикали уводил иначе,
	# чем по горизонтали. Берём равномерную точку в круге и раскладываем по right/up камеры.
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	var ang := rng.randf() * TAU
	var rad := sqrt(rng.randf()) * s      # sqrt — иначе точки сгущаются к центру
	dir = (dir + right * (cos(ang) * rad) + up * (sin(ang) * rad)).normalized()
	var res := raycast(origin, dir, float(w().get("range", 200.0)) if bool(w().get("melee", false)) else 200.0)
	if res.is_empty():
		return
	var collider: Object = res["collider"]
	var dist := origin.distance_to(res["position"] as Vector3)
	_spawn_tracer(origin, res["position"] as Vector3)
	_spawn_decal(res["position"] as Vector3, res["normal"] as Vector3)
	if collider.has_method("part_at") and collider.has_method("take_hit"):
		var part: String = collider.call("part_at", res["shape"] as int, (res["position"] as Vector3).y)
		var wd := w()
		var base := float(wd["head"]) if part == "head" else (float(wd["leg"]) if part == "leg" else float(wd["dmg"]))
		var dmg := roundi(base * falloff_mult(dist))
		# пассивка Геры «Охотник за туманщиками»: +15% по врагу, стоящему в дыму
		if player.char_id == "gera" and collider is Node3D and bool(get_node("/root/Smokes").call("point_in_smoke", (collider as Node3D).global_position)):
			dmg = roundi(dmg * float(Balance.ABILITY["GERA_SMOKE_DMG_MUL"]))
		if NetHub.online():
			# паритет вебу: попадание считает клиент, ПРИМЕНЯЕТ хост
			NetHub.report_hit(collider as Node, dmg, part, player, current_id)
		else:
			collider.call("take_hit", dmg, part, player, current_id)
		hit_sfx.stream = load("res://assets/audio/%s.ogg" % ("ting" if part == "head" else "hit"))
		hit_sfx.play()
		hit_target.emit(part, dmg)


func _fire_knife() -> void:
	var origin := player.eye_pos()
	var dir := player.aim_dir()
	var res := raycast(origin, dir, 60.0)
	shot_sfx.stream = _shot_streams["gun_pistol"]
	shot_sfx.pitch_scale = 1.4
	shot_sfx.play()
	if res.is_empty():
		return
	var collider: Object = res["collider"]
	_spawn_tracer(origin, res["position"] as Vector3)
	if collider.has_method("part_at") and collider.has_method("take_hit"):
		var part: String = collider.call("part_at", res["shape"] as int, (res["position"] as Vector3).y)
		var dmg := int(Balance.ABILITY["KNIFE_HEAD"] if part == "head" else Balance.ABILITY["KNIFE_DMG"])
		if NetHub.online():
			NetHub.report_hit(collider as Node, dmg, part, player, "knives")
		else:
			collider.call("take_hit", dmg, part, player, "knives")
		hit_target.emit(part, dmg)


func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	q.exclude = [player.get_rid()]
	return space.intersect_ray(q)


func _play_shot() -> void:
	var sample: String = SHOT_SAMPLE.get(current_id, "gun_rifle")
	shot_sfx.stream = _shot_streams[sample]
	shot_sfx.pitch_scale = 0.95 + rng.randf() * 0.1
	shot_sfx.play()
	# дульная вспышка (G10): свет + сноп искр от ствола
	var vm := get_node_or_null("../Head/Viewmodel")
	var mpos := player.eye_pos() + player.aim_dir() * 0.6
	if vm and vm.has_method("muzzle_pos"):
		mpos = vm.call("muzzle_pos")  # из дула вьюмодели
	Vfx.muzzle(self, mpos, player.aim_dir())


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.6, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from + player.aim_dir().cross(Vector3.UP) * 0.08 - Vector3(0, 0.06, 0))
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	get_tree().current_scene.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(mi.queue_free)


func _spawn_decal(pos: Vector3, normal: Vector3) -> void:
	Vfx.impact(self, pos, normal)  # пыль/искры от поверхности (G10)
	var d := Decal.new()
	d.size = Vector3(0.12, 0.08, 0.12)
	d.modulate = Color(0.08, 0.08, 0.08, 0.9)
	d.texture_albedo = _dot_tex()
	get_tree().current_scene.add_child(d)
	d.global_position = pos + normal * 0.01
	if absf(normal.dot(Vector3.UP)) < 0.99:
		d.look_at(pos + normal, Vector3.UP)
		d.rotate_object_local(Vector3.RIGHT, -PI / 2)
	var tw := d.create_tween()
	tw.tween_interval(8.0)
	tw.tween_callback(d.queue_free)


static var _cached_dot: ImageTexture

static func _dot_tex() -> ImageTexture:
	if _cached_dot:
		return _cached_dot
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for x in 8:
		for y in 8:
			var dx := x - 3.5
			var dy := y - 3.5
			img.set_pixel(x, y, Color(0, 0, 0, 1.0 if dx * dx + dy * dy < 12.0 else 0.0))
	_cached_dot = ImageTexture.create_from_image(img)
	return _cached_dot
