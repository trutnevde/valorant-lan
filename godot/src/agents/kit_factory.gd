# Сборка кита агента из компонентов-способностей (правило 4).
# Реализованы дуэлянты (G6a): Артемий, Макс, Фафик. Остальные — G6b/G6c.
class_name KitFactory

const KITS := {
	"max": [
		"res://scenes/agents/max/dash.gd", "res://scenes/agents/max/launch.gd",
		"res://scenes/agents/max/boost.gd", "res://scenes/agents/max/knives.gd",
	],
	"artemiy": [
		"res://scenes/agents/artemiy/flash.gd", "res://scenes/agents/artemiy/fireball.gd",
		"res://scenes/agents/artemiy/firewall.gd", "res://scenes/agents/artemiy/second_wind.gd",
	],
	"fafik": [
		"res://scenes/agents/fafik/tapok.gd", "res://scenes/agents/fafik/twin.gd",
		"res://scenes/agents/fafik/swap.gd", "res://scenes/agents/fafik/clones.gd",
	],
}


static func attach(player: Node, char_id: String) -> void:
	if not KITS.has(char_id):
		return  # агент без кита в порте (пока) — только стрельба
	var kit := Node.new()
	kit.name = "Kit"
	player.add_child(kit)
	for path: String in KITS[char_id]:
		var comp: Node = (load(path) as GDScript).new()
		comp.name = String(path.get_file().get_basename()).capitalize().replace(" ", "")
		kit.add_child(comp)
