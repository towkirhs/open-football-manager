extends RefCounted
## Small builders shared by the screens, so they all look alike.

const UiTheme = preload("res://src/ui/ui_theme.gd")


static func label(text: String, size: int = 15, color_key: String = "text") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UiTheme.c(color_key))
	return l


static func wrap_label(text: String, size: int = 14, color_key: String = "muted") -> Label:
	var l := label(text, size, color_key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func heading(text: String) -> Label:
	return label(text.to_upper(), 12, "muted")


static func button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.theme_type_variation = "AccentButton"
		b.custom_minimum_size = Vector2(150, 42)
	else:
		b.custom_minimum_size = Vector2(0, 38)
	return b


static func panel(color_key: String = "panel") -> PanelContainer:
	var p := PanelContainer.new()
	if color_key != "panel":
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.c(color_key)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(16)
		p.add_theme_stylebox_override("panel", sb)
	return p


static func vbox(separation: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	if selected >= 0 and selected < items.size():
		o.select(selected)
	return o


## A simple club shield: the club's colours with its short name. No real badges.
static func shield(club, size: int = 44) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(club.colours[0])
	sb.border_color = Color(club.colours[1])
	sb.set_border_width_all(maxi(2, size / 16))
	sb.corner_radius_top_left = size / 6
	sb.corner_radius_top_right = size / 6
	sb.corner_radius_bottom_left = size / 2
	sb.corner_radius_bottom_right = size / 2
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(size, size * 1.12)
	var l := Label.new()
	l.text = club.short_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", maxi(9, size / 4))
	l.add_theme_color_override("font_color", Color(club.colours[1]))
	p.add_child(l)
	return p


## A table with column titles. widths: Array of minimum widths (0 = expand).
static func table(titles: Array, widths: Array = []) -> Tree:
	var t := Tree.new()
	t.columns = titles.size()
	t.column_titles_visible = true
	t.hide_root = true
	t.select_mode = Tree.SELECT_ROW
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in titles.size():
		t.set_column_title(i, titles[i])
		t.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i < widths.size() and int(widths[i]) == 0 else HORIZONTAL_ALIGNMENT_CENTER)
		if i < widths.size() and int(widths[i]) > 0:
			t.set_column_expand(i, false)
			t.set_column_custom_minimum_width(i, int(widths[i]))
		else:
			t.set_column_expand(i, true)
	t.create_item()
	return t


## Adds a row; numbers and short values are centred. Returns the row.
static func row(t: Tree, values: Array, color_key: String = "", bg_key: String = "") -> TreeItem:
	var it := t.create_item(t.get_root())
	for i in values.size():
		it.set_text(i, str(values[i]))
		if t.is_column_expanding(i):
			it.set_text_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		else:
			it.set_text_alignment(i, HORIZONTAL_ALIGNMENT_CENTER)
		if color_key != "":
			it.set_custom_color(i, UiTheme.c(color_key))
		if bg_key != "":
			it.set_custom_bg_color(i, UiTheme.c(bg_key))
	return it


static func clear_children(n: Node) -> void:
	for ch in n.get_children():
		n.remove_child(ch)
		ch.queue_free()


static func money(v: int) -> String:
	var neg := v < 0
	var a: int = absi(v)
	var s := ""
	if a >= 1000000:
		s = "€%.1fM" % (a / 1000000.0)
	elif a >= 1000:
		s = "€%dK" % roundi(a / 1000.0)
	else:
		s = "€%d" % a
	return ("-" + s) if neg else s


static func spin(min_v: float, max_v: float, value: float, step: float = 1.0, prefix: String = "", suffix: String = "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.prefix = prefix
	s.suffix = suffix
	s.allow_greater = false
	s.custom_minimum_size = Vector2(160, 0)
	return s


static func line_edit(placeholder: String, width: int = 160) -> LineEdit:
	var l := LineEdit.new()
	l.placeholder_text = placeholder
	l.custom_minimum_size = Vector2(width, 0)
	return l


## A pop-up card over the whole screen. Returns {"root", "body", "close"}; add content to body.
static func modal(host: Control, title: String, width: int = 560) -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card := panel()
	card.custom_minimum_size = Vector2(width, 0)
	center.add_child(card)
	var v := vbox(12)
	card.add_child(v)
	var head := hbox(10)
	v.add_child(head)
	head.add_child(label(title, 20))
	head.add_child(spacer())
	var close := button("Close")
	close.custom_minimum_size = Vector2(90, 34)
	close.pressed.connect(root.queue_free)
	head.add_child(close)
	var body := vbox(10)
	v.add_child(body)
	host.add_child(root)
	return {"root": root, "body": body, "close": close}


## Section heading with a thin rule.
static func section(text: String) -> Control:
	var v := vbox(4)
	v.add_child(heading(text))
	return v


## A small value card: caption on top, big value below.
static func stat(caption: String, value: String, color_key: String = "text", width: int = 110) -> Control:
	var box := panel("panel2")
	box.custom_minimum_size = Vector2(width, 0)
	var v := vbox(0)
	box.add_child(v)
	var cap := label(caption, 11, "muted")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var val := label(value, 20, color_key)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	return box


static func scroll_box() -> Array:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return [sc, v]


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
