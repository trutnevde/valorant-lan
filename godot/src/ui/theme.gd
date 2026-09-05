# Тема интерфейса — палитра веба («ночной патч» style.css): тёмное стекло, бирюзовый
# акцент, красный урона, золото денег. Строится кодом и вешается на корень UI, чтобы
# все Label/Button/Panel/ItemList/OptionButton разом перестали быть серыми дефолтами Godot.
class_name UiTheme

const BG := Color("#0f1923")
const BG0 := Color("#0a111c")
const GLASS := Color(16.0 / 255.0, 26.0 / 255.0, 40.0 / 255.0, 0.78)
const BORDER := Color(1, 1, 1, 0.09)
const RED := Color("#ff4655")
const TEAL := Color("#14d3c0")
const GOLD := Color("#e8c14d")
const INK := Color("#eaeef3")
const MUTED := Color(0.62, 0.68, 0.74)

static var _theme: Theme


static func build() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	# --- панели: стекло со скруглением и тонкой рамкой ---
	var panel := _glass(GLASS, BORDER, 14)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	# --- кнопки ---
	var btn := _glass(Color(0.10, 0.16, 0.24, 0.9), BORDER, 10)
	btn.content_margin_left = 16
	btn.content_margin_right = 16
	btn.content_margin_top = 8
	btn.content_margin_bottom = 8
	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.12, 0.22, 0.30, 0.95)
	btn_hover.border_color = TEAL.darkened(0.2)
	var btn_press := btn.duplicate() as StyleBoxFlat
	btn_press.bg_color = TEAL.darkened(0.55)
	btn_press.border_color = TEAL
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, btn_hover)
		t.set_stylebox("pressed", cls, btn_press)
		t.set_stylebox("focus", cls, btn_hover)
		t.set_color("font_color", cls, INK)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_font_size("font_size", cls, 16)
	# --- поля ввода ---
	var edit := _glass(Color(0.06, 0.10, 0.16, 0.9), BORDER, 8)
	edit.content_margin_left = 12
	edit.content_margin_top = 8
	edit.content_margin_bottom = 8
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = TEAL
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_font_size("font_size", "LineEdit", 16)
	# --- списки ---
	t.set_stylebox("panel", "ItemList", _glass(Color(0.06, 0.10, 0.16, 0.85), BORDER, 10))
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_stylebox("selected", "ItemList", _glass(TEAL.darkened(0.6), TEAL, 6))
	t.set_stylebox("selected_focus", "ItemList", _glass(TEAL.darkened(0.6), TEAL, 6))
	t.set_font_size("font_size", "ItemList", 16)
	# --- подписи ---
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	# --- выпадающие меню ---
	t.set_stylebox("panel", "PopupMenu", _glass(Color(0.08, 0.13, 0.20, 0.97), BORDER, 10))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", _glass(TEAL.darkened(0.6), Color.TRANSPARENT, 6))
	# --- вариации: акцентная кнопка, заголовок, приглушённая подпись ---
	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	var prim := _glass(TEAL.darkened(0.45), TEAL, 10)
	prim.content_margin_top = 10
	prim.content_margin_bottom = 10
	var prim_hover := prim.duplicate() as StyleBoxFlat
	prim_hover.bg_color = TEAL.darkened(0.3)
	t.set_stylebox("normal", "PrimaryButton", prim)
	t.set_stylebox("hover", "PrimaryButton", prim_hover)
	t.set_stylebox("pressed", "PrimaryButton", prim_hover)
	t.set_stylebox("focus", "PrimaryButton", prim_hover)
	t.set_color("font_color", "PrimaryButton", Color.WHITE)
	t.set_font_size("font_size", "PrimaryButton", 17)
	t.add_type("Title")
	t.set_type_variation("Title", "Label")
	t.set_font_size("font_size", "Title", 30)
	t.set_color("font_color", "Title", Color.WHITE)
	t.add_type("Muted")
	t.set_type_variation("Muted", "Label")
	t.set_font_size("font_size", "Muted", 14)
	t.set_color("font_color", "Muted", MUTED)
	_theme = t
	return t


static func _glass(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	return sb
