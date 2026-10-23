extends RefCounted
## Colour themes. Every screen takes its colours from the current theme, and the
## Godot Theme built here styles buttons, dropdowns and tables to match.
## The chosen theme is saved in user://settings.json.

const SETTINGS_PATH := "user://settings.json"

const THEMES := {
	"Pitch green": {
		"bg": "#0f1a14", "panel": "#16251c", "panel2": "#1e3226", "line": "#2a4434",
		"accent": "#2fbf71", "on_accent": "#0b1a12", "text": "#e8f5ec", "muted": "#8aa597",
		"good": "#2fbf71", "warn": "#f2c14e", "bad": "#ef5350", "highlight": "#24402f",
	},
	"Midnight blue": {
		"bg": "#0d1321", "panel": "#151f33", "panel2": "#1d2a45", "line": "#2a3a5c",
		"accent": "#4ea8ff", "on_accent": "#08111f", "text": "#e6eefc", "muted": "#8d9bb8",
		"good": "#4cd18a", "warn": "#f2c14e", "bad": "#ff6b6b", "highlight": "#22385c",
	},
	"Royal purple": {
		"bg": "#140f1d", "panel": "#1e162c", "panel2": "#291f3d", "line": "#3a2c55",
		"accent": "#b388ff", "on_accent": "#140f1d", "text": "#efe8fb", "muted": "#a090bd",
		"good": "#69d49a", "warn": "#f5c451", "bad": "#ff6e7f", "highlight": "#33264d",
	},
	"Sunset": {
		"bg": "#19110e", "panel": "#251915", "panel2": "#32221c", "line": "#4a3128",
		"accent": "#ff8a50", "on_accent": "#1a0f0a", "text": "#fbece4", "muted": "#bb9a8b",
		"good": "#7bd389", "warn": "#ffd166", "bad": "#ff5c5c", "highlight": "#43291f",
	},
	"Classic light": {
		"bg": "#eef2ee", "panel": "#ffffff", "panel2": "#e4ebe5", "line": "#cfd9d1",
		"accent": "#1f8a52", "on_accent": "#ffffff", "text": "#17241c", "muted": "#5d7165",
		"good": "#1f8a52", "warn": "#b7791f", "bad": "#c62828", "highlight": "#d9efe1",
	},
}

static var current: String = "Pitch green"


static func c(key: String) -> Color:
	return Color(THEMES[current][key])


static func hex(key: String) -> String:
	return str(THEMES[current][key])


static func names() -> Array:
	return THEMES.keys()


static func load_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY and THEMES.has(str(d.get("theme", ""))):
		current = str(d["theme"])


static func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"theme": current}))


static func _box(color: Color, radius: int = 8, margin: float = 10.0, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb


## A Godot Theme for the current colours. Set it on the root control; children inherit it.
static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15

	t.set_color("font_color", "Label", c("text"))

	# Plain buttons (secondary actions)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var col := c("panel2")
		match state:
			"hover": col = c("panel2").lightened(0.08)
			"pressed": col = c("highlight")
			"disabled": col = c("panel")
		var sb := _box(col, 8, 12.0, c("line") if state != "focus" else c("accent"))
		if state == "focus":
			sb.bg_color = Color.TRANSPARENT
			sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
		t.set_stylebox(state, "OptionButton", sb)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "Button", c("text"))
		t.set_color(k, "OptionButton", c("text"))
	t.set_color("font_pressed_color", "Button", c("accent"))
	t.set_color("font_disabled_color", "Button", c("muted"))
	t.set_color("font_disabled_color", "OptionButton", c("muted"))
	t.set_color("font_pressed_color", "OptionButton", c("text"))

	# Primary button: AccentButton
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", _box(c("accent"), 8, 16.0))
	t.set_stylebox("hover", "AccentButton", _box(c("accent").lightened(0.12), 8, 16.0))
	t.set_stylebox("pressed", "AccentButton", _box(c("accent").darkened(0.12), 8, 16.0))
	t.set_stylebox("disabled", "AccentButton", _box(c("panel2"), 8, 16.0))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "AccentButton", c("on_accent"))
	t.set_color("font_disabled_color", "AccentButton", c("muted"))

	# Tab buttons: TabButton (toggle)
	t.set_type_variation("TabButton", "Button")
	t.set_stylebox("normal", "TabButton", _box(Color.TRANSPARENT, 8, 14.0))
	t.set_stylebox("hover", "TabButton", _box(c("panel2"), 8, 14.0))
	t.set_stylebox("pressed", "TabButton", _box(c("highlight"), 8, 14.0))
	t.set_stylebox("hover_pressed", "TabButton", _box(c("highlight"), 8, 14.0))
	t.set_color("font_color", "TabButton", c("muted"))
	t.set_color("font_pressed_color", "TabButton", c("accent"))
	t.set_color("font_hover_pressed_color", "TabButton", c("accent"))
	t.set_color("font_hover_color", "TabButton", c("text"))

	# Dropdown menus
	t.set_stylebox("panel", "PopupMenu", _box(c("panel2"), 6, 6.0, c("line")))
	t.set_stylebox("hover", "PopupMenu", _box(c("highlight"), 4, 6.0))
	t.set_color("font_color", "PopupMenu", c("text"))
	t.set_color("font_hover_color", "PopupMenu", c("accent"))
	t.set_color("font_disabled_color", "PopupMenu", c("muted"))

	# Tables
	t.set_stylebox("panel", "Tree", _box(c("panel"), 8, 4.0))
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("selected", "Tree", _box(c("highlight"), 4, 2.0))
	t.set_stylebox("selected_focus", "Tree", _box(c("highlight"), 4, 2.0))
	t.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("title_button_normal", "Tree", _box(c("panel2"), 0, 6.0))
	t.set_stylebox("title_button_hover", "Tree", _box(c("highlight"), 0, 6.0))
	t.set_stylebox("title_button_pressed", "Tree", _box(c("highlight"), 0, 6.0))
	t.set_color("font_color", "Tree", c("text"))
	t.set_color("font_selected_color", "Tree", c("text"))
	t.set_color("title_button_color", "Tree", c("muted"))
	t.set_color("guide_color", "Tree", c("line"))
	t.set_constant("v_separation", "Tree", 6)
	t.set_constant("draw_guides", "Tree", 0)

	t.set_color("font_color", "CheckBox", c("text"))
	t.set_color("font_hover_color", "CheckBox", c("text"))
	t.set_color("font_pressed_color", "CheckBox", c("text"))
	t.set_color("default_color", "RichTextLabel", c("text"))
	t.set_stylebox("panel", "PanelContainer", _box(c("panel"), 10, 16.0))
	return t
