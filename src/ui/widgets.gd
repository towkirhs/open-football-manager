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
