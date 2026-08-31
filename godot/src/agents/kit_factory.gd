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
	"denis": [
		"res://scenes/agents/denis/bloodfeast.gd", "res://scenes/agents/denis/scent.gd",
		"res://scenes/agents/denis/smrad.gd", "res://scenes/agents/denis/hook.gd",
	],
	"sova": [
		"res://scenes/agents/sova/shock.gd", "res://scenes/agents/sova/mark.gd",
		"res://scenes/agents/sova/drone.gd", "res://scenes/agents/sova/fury.gd",
	],
	"gera": [
		"res://scenes/agents/gera/dispel.gd", "res://scenes/agents/gera/grapple.gd",
		"res://scenes/agents/gera/vortex.gd", "res://scenes/agents/gera/levitation.gd",
	],
	"vova": [
		"res://scenes/agents/vova/smoke_global.gd", "res://scenes/agents/vova/flash.gd",
		"res://scenes/agents/vova/veil.gd", "res://scenes/agents/vova/orbital.gd",
	],
	"sanek": [
		"res://scenes/agents/sanek/trap.gd", "res://scenes/agents/sanek/turret.gd",
		"res://scenes/agents/sanek/acid.gd", "res://scenes/agents/sanek/xray.gd",
	],
	"ira": [
		"res://scenes/agents/ira/scout.gd", "res://scenes/agents/ira/crispy.gd",
		"res://scenes/agents/ira/buffet.gd", "res://scenes/agents/ira/banquet.gd",
	],
	"koniliy": [
		"res://scenes/agents/koniliy/horseshoe.gd", "res://scenes/agents/koniliy/neigh.gd",
		"res://scenes/agents/koniliy/gallop.gd", "res://scenes/agents/koniliy/stampede.gd",
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
