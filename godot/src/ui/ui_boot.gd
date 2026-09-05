# Ui (autoload): тема на корневом окне наследуется всеми Control — лобби, HUD, магазин,
# скорборд разом перестают быть серыми дефолтами Godot.
extends Node


func _ready() -> void:
	get_tree().root.theme = UiTheme.build()
