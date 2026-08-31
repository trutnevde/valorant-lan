# Проверка звуковой инфраструктуры G8 (headless):
#   godot --headless --path . -s res://tools/audiocheck.gd
# Убеждаемся, что шины из default_bus_layout.tres поднялись и Muffled несёт low-pass.
extends SceneTree


func _initialize() -> void:
	var want := ["Master", "SFX", "Steps", "Voice", "UI", "Muffled", "Reverb"]
	var have: Array = []
	for i in AudioServer.bus_count:
		have.append(AudioServer.get_bus_name(i))
	var fails: Array = []
	for b in want:
		if not have.has(b):
			fails.append("нет шины " + b)
	# Muffled должна иметь low-pass, Reverb — reverb
	var mi := AudioServer.get_bus_index("Muffled")
	if mi >= 0:
		var has_lpf := false
		for e in AudioServer.get_bus_effect_count(mi):
			if AudioServer.get_bus_effect(mi, e) is AudioEffectLowPassFilter:
				has_lpf = true
		if not has_lpf:
			fails.append("Muffled без low-pass")
	var ri := AudioServer.get_bus_index("Reverb")
	if ri >= 0:
		var has_rev := false
		for e in AudioServer.get_bus_effect_count(ri):
			if AudioServer.get_bus_effect(ri, e) is AudioEffectReverb:
				has_rev = true
		if not has_rev:
			fails.append("Reverb без reverb-эффекта")
	print("audiocheck: шины=", have)
	if fails.is_empty():
		print("audiocheck: OK — все шины и эффекты на месте")
		quit(0)
	else:
		print("audiocheck: FAIL — ", fails)
		quit(1)
