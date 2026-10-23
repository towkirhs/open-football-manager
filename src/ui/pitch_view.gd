extends Control
## A football pitch with your eleven in formation. Click a player to choose who plays there.

signal slot_pressed(index: int)

const Tactics = preload("res://src/sim/tactics.gd")
const Lineup = preload("res://src/sim/lineup.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const GRASS_A := Color("#2d6a3e")
const GRASS_B := Color("#29613a")
const LINE := Color(1, 1, 1, 0.55)
const MAX_SLOT := Vector2(104, 58)
## Width to height of the drawn pitch. A little wider than a real pitch so names fit.
const PITCH_RATIO := 0.8

var lineup = null
var selected: int = -1
var _buttons: Array = []


func set_lineup(l, selected_index: int = -1) -> void:
	lineup = l
	selected = selected_index
	for b in _buttons:
		b.queue_free()
	_buttons = []
	if lineup == null:
		return
	for i in lineup.slots.size():
		var slot: Dictionary = lineup.slots[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = i == selected
		b.clip_text = true
		var p = slot["player"]
		var role: String = slot["role"]
		if p == null:
			b.text = "%s\n(empty)" % role
		else:
			var parts: PackedStringArray = p.name.split(" ")
			b.text = "%s  %d\n%s" % [role, Lineup.role_score(p, role), parts[parts.size() - 1]]
		_style_slot(b, p, role, i == selected)
		b.pressed.connect(func(): slot_pressed.emit(i))
		add_child(b)
		_buttons.append(b)
	_place()
	queue_redraw()


func _style_slot(b: Button, p, role: String, is_selected: bool) -> void:
	var border := Color(1, 1, 1, 0.35)
	if p != null and p.fitness < 75.0:
		border = UiTheme.c("warn")
	# Red: a player well out of position. (Related positions, like a winger at wing-back, are fine.)
	if p != null and Tactics.position_fit(p.position, role) < 0.8:
		border = UiTheme.c("bad")
	if is_selected:
		border = UiTheme.c("accent")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.55) if state != "hover" else Color(0, 0, 0, 0.7)
		sb.border_color = border
		sb.set_border_width_all(3 if is_selected else 2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		if state == "focus":
			sb.draw_center = false
			sb.border_color = Color.TRANSPARENT
		b.add_theme_stylebox_override(state, sb)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_font_size_override("font_size", 12)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


func _pitch_rect() -> Rect2:
	var ratio := PITCH_RATIO
	var h := size.y
	var w := h * ratio
	if w > size.x:
		w = size.x
		h = w / ratio
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)


func _place() -> void:
	if lineup == null:
		return
	var r := _pitch_rect()
	var pts: Array = Tactics.LAYOUT.get(lineup.formation, [])
	# Boxes shrink with the pitch so neighbours never overlap.
	var slot := Vector2(minf(MAX_SLOT.x, r.size.x * 0.21), minf(MAX_SLOT.y, r.size.y * 0.085))
	for i in mini(_buttons.size(), pts.size()):
		var pos := Vector2(r.position.x + float(pts[i][0]) * r.size.x, r.position.y + float(pts[i][1]) * r.size.y)
		_buttons[i].custom_minimum_size = slot
		_buttons[i].size = slot
		_buttons[i].position = pos - slot * 0.5


func _draw() -> void:
	var r := _pitch_rect()
	var stripes := 10
	for i in stripes:
		var y := r.position.y + r.size.y * i / stripes
		draw_rect(Rect2(r.position.x, y, r.size.x, r.size.y / stripes + 1), GRASS_A if i % 2 == 0 else GRASS_B)
	var lw := 2.0
	draw_rect(r, LINE, false, lw)
	var mid_y := r.position.y + r.size.y * 0.5
	draw_line(Vector2(r.position.x, mid_y), Vector2(r.end.x, mid_y), LINE, lw)
	draw_arc(Vector2(r.position.x + r.size.x * 0.5, mid_y), r.size.x * 0.135, 0, TAU, 48, LINE, lw)
	# Penalty and goal areas at both ends
	for top in [true, false]:
		var bw := r.size.x * 0.59
		var bh := r.size.y * 0.157
		var gw := r.size.x * 0.27
		var gh := r.size.y * 0.052
		var bx := r.position.x + (r.size.x - bw) * 0.5
		var gx := r.position.x + (r.size.x - gw) * 0.5
		var by: float = r.position.y if top else r.end.y - bh
		var gy: float = r.position.y if top else r.end.y - gh
		draw_rect(Rect2(bx, by, bw, bh), LINE, false, lw)
		draw_rect(Rect2(gx, gy, gw, gh), LINE, false, lw)
