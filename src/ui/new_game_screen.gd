extends Control
## Title screen: continue the saved career, or start a new one.
## By default you start at a random club in the lowest division; you can also pick any
## club by country and division, or take a random club anywhere.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const WorldLoader = preload("res://src/data/world_loader.gd")

var app = null
var _world: Dictionary = {}
var _use_custom: bool = false
var _selected: String = ""
var _start_btn: Button
var _detail: Label
var _grid: GridContainer
var _country: OptionButton
var _division: OptionButton
var _name: LineEdit
var _club_buttons: Dictionary = {}
var _divisions: Array = []


func _ready() -> void:
	_use_custom = WorldLoader.has_custom_world()
	_world = app.make_world(_use_custom)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := W.vbox(14)
	margin.add_child(root)

	var top := W.hbox(16)
	root.add_child(top)
	var titles := W.vbox(2)
	titles.add_child(W.label("Open Football Manager", 30, "text"))
	titles.add_child(W.label("Free, fair and open source. Win with tactics, not your wallet.", 15, "muted"))
	top.add_child(titles)
	top.add_child(W.spacer())
	var theme_label := W.label("Theme", 13, "muted")
	theme_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(theme_label)
	var themes := W.option(UiTheme.names(), UiTheme.names().find(UiTheme.current))
	themes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	themes.item_selected.connect(func(i): app.set_theme_name(UiTheme.names()[i]))
	top.add_child(themes)

	if app.season != null:
		root.add_child(_continue_card())

	var pick := W.panel()
	pick.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pick)
	var pv := W.vbox(12)
	pick.add_child(pv)
	var head := W.hbox(12)
	pv.add_child(head)
	head.add_child(W.label("New career", 20))
	head.add_child(W.spacer())
	head.add_child(W.label("Your name", 13, "muted"))
	_name = W.line_edit("Manager name", 180)
	head.add_child(_name)

	var world_row := W.hbox(10)
	pv.add_child(world_row)
	var wtext := "World: %s, %d clubs." % [_world.get("name", "World"), _world["clubs"].size()]
	if _world.get("fictional", true):
		wtext += " All clubs and players are fictional."
	world_row.add_child(W.label(wtext, 14, "muted"))
	world_row.add_child(W.spacer())
	if WorldLoader.has_custom_world():
		var toggle := CheckBox.new()
		toggle.text = "Use my world file"
		toggle.button_pressed = _use_custom
		toggle.toggled.connect(_on_world_toggled)
		world_row.add_child(toggle)

	var quick := W.hbox(10)
	pv.add_child(quick)
	var lowest := W.button("Random club, lowest division", true)
	lowest.custom_minimum_size = Vector2(260, 42)
	lowest.pressed.connect(_pick_lowest)
	quick.add_child(lowest)
	var anywhere := W.button("Random club anywhere")
	anywhere.custom_minimum_size = Vector2(200, 42)
	anywhere.pressed.connect(_pick_anywhere)
	quick.add_child(anywhere)
	quick.add_child(W.spacer())
	quick.add_child(W.label("Or choose:", 14, "muted"))
	_country = OptionButton.new()
	quick.add_child(_country)
	_division = OptionButton.new()
	quick.add_child(_division)
	var countries: Array = _world["countries"].filter(func(c): return c.get("playable", false))
	for c in countries:
		_country.add_item(c["name"])
		_country.set_item_metadata(_country.item_count - 1, c["id"])
	_country.item_selected.connect(func(_i): _fill_divisions())
	_division.item_selected.connect(func(_i): _fill_clubs())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

	var bottom := W.hbox(12)
	pv.add_child(bottom)
	_detail = W.label("Pick a club, or press one of the random buttons.", 15, "muted")
	bottom.add_child(_detail)
	bottom.add_child(W.spacer())
	_start_btn = W.button("Start career", true)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_start)
	bottom.add_child(_start_btn)

	if _country.item_count > 0:
		_fill_divisions()


func _continue_card() -> Control:
	var cont := W.panel()
	var row := W.hbox(16)
	cont.add_child(row)
	var s = app.season
	var club = s.user_club()
	row.add_child(W.shield(club, 44))
	var info := W.vbox(2)
	info.add_child(W.label("Continue your career with %s" % club.name, 18))
	var l = s.user_league()
	var where := "Season %d/%02d  ·  %s" % [s.year, (s.year + 1) % 100, s.today().get("label", "Season over")]
	if l != null:
		where += "  ·  %s in the %s" % [W.ordinal(l.position_of(club.id)), l.name]
	info.add_child(W.label(where, 14, "muted"))
	row.add_child(info)
	row.add_child(W.spacer())
	var cbtn := W.button("Continue", true)
	cbtn.pressed.connect(app.continue_career)
	row.add_child(cbtn)
	return cont


func _on_world_toggled(on: bool) -> void:
	_use_custom = on
	_world = app.make_world(on)
	_selected = ""
	_country.clear()
	for c in _world["countries"].filter(func(c): return c.get("playable", false)):
		_country.add_item(c["name"])
		_country.set_item_metadata(_country.item_count - 1, c["id"])
	_fill_divisions()


func _fill_divisions() -> void:
	_division.clear()
	var cid: String = _country.get_item_metadata(_country.selected)
	_divisions = _world["leagues"].filter(func(l): return l["country"] == cid)
	_divisions.sort_custom(func(a, b): return int(a["tier"]) < int(b["tier"]))
	for l in _divisions:
		_division.add_item(l["name"])
	_division.select(_divisions.size() - 1)
	_fill_clubs()


func _fill_clubs() -> void:
	W.clear_children(_grid)
	_club_buttons = {}
	if _divisions.is_empty():
		return
	var lid: String = _divisions[_division.selected]["id"]
	var clubs: Array = _world["clubs"].filter(func(c): return c.league == lid)
	clubs.sort_custom(func(a, b): return a.reputation < b.reputation)
	for c in clubs:
		_grid.add_child(_club_card(c))


func _club_card(c) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := W.hbox(10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := W.shield(c, 34)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sh)
	var info := W.vbox(0)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(W.label(c.name, 15))
	info.add_child(W.label("Squad %.0f  ·  %s" % [c.average_overall(), W.money(c.cash)], 12, "muted"))
	row.add_child(info)
	b.add_child(row)
	b.pressed.connect(func(): _select(c))
	_club_buttons[c.id] = b
	return b


func _select(c) -> void:
	_selected = c.id
	for k in _club_buttons:
		_club_buttons[k].button_pressed = (k == c.id)
	var league := ""
	for l in _world["leagues"]:
		if l["id"] == c.league:
			league = l["name"]
	_detail.text = "%s (%s): squad %.0f, %s in the bank, stadium %d seats." % [c.name, league, c.average_overall(), W.money(c.cash), c.stadium]
	if app.season != null:
		_detail.text += "  Starting replaces your saved career."
	_start_btn.disabled = false


func _pick_lowest() -> void:
	var cid: String = _country.get_item_metadata(_country.selected) if _country.item_count > 0 else ""
	var pool: Array = []
	# The lowest division of the chosen country.
	_division.select(_divisions.size() - 1)
	_fill_clubs()
	var lid: String = _divisions[_divisions.size() - 1]["id"] if not _divisions.is_empty() else ""
	pool = _world["clubs"].filter(func(c): return c.league == lid)
	if pool.is_empty():
		pool = _world["clubs"].filter(func(c): return c.country == cid and c.league != "")
	_select(pool[app.rng.randi_range(0, pool.size() - 1)])


func _pick_anywhere() -> void:
	var pool: Array = _world["clubs"].filter(func(c): return c.league != "")
	var c = pool[app.rng.randi_range(0, pool.size() - 1)]
	for i in _country.item_count:
		if _country.get_item_metadata(i) == c.country:
			_country.select(i)
	_fill_divisions()
	for i in _divisions.size():
		if _divisions[i]["id"] == c.league:
			_division.select(i)
	_fill_clubs()
	_select(c)


func _start() -> void:
	if _selected != "":
		app.start_career(_world, _selected, _name.text)
