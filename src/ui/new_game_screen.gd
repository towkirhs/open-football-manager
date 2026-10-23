extends Control
## Title screen: continue the saved career or start a new one by picking a club.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var app = null
var _clubs: Array = []
var _selected: String = ""
var _start_btn: Button
var _detail: Label
var _club_buttons: Dictionary = {}


func _ready() -> void:
	_clubs = app.load_league()["clubs"]
	_clubs.sort_custom(func(a, b): return a.average_overall() < b.average_overall())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var root := W.vbox(16)
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
	themes.item_selected.connect(func(i): app.set_theme_name(UiTheme.names()[i]))
	themes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(themes)

	if app.season != null:
		var cont := W.panel("panel")
		var row := W.hbox(16)
		cont.add_child(row)
		var club = app.season.user_club()
		row.add_child(W.shield(club, 44))
		var info := W.vbox(2)
		info.add_child(W.label("Continue your career with %s" % club.name, 18))
		var where := "Season %d/%02d, week %d of %d, %s in the table" % [app.season.year, (app.season.year + 1) % 100,
			mini(app.season.week + 1, app.season.total_weeks()), app.season.total_weeks(), app.season.ordinal(app.season.position_of(club.id))]
		info.add_child(W.label(where, 14, "muted"))
		row.add_child(info)
		row.add_child(W.spacer())
		var cbtn := W.button("Continue", true)
		cbtn.pressed.connect(app.continue_career)
		row.add_child(cbtn)
		root.add_child(cont)

	var pick := W.panel("panel")
	pick.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pick)
	var pv := W.vbox(12)
	pick.add_child(pv)
	var head := W.hbox(12)
	pv.add_child(head)
	head.add_child(W.label("New career: pick your club", 18))
	head.add_child(W.spacer())
	var random_btn := W.button("Random club")
	random_btn.pressed.connect(_pick_random)
	head.add_child(random_btn)
	pv.add_child(W.wrap_label("Clubs are sorted from weakest to strongest. Starting small is the real challenge: out-think bigger clubs with the right tactics. All clubs and players here are fictional."))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for c in _clubs:
		grid.add_child(_club_card(c))

	var bottom := W.hbox(12)
	pv.add_child(bottom)
	_detail = W.label("No club selected.", 15, "muted")
	bottom.add_child(_detail)
	bottom.add_child(W.spacer())
	_start_btn = W.button("Start career", true)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_start)
	bottom.add_child(_start_btn)


func _club_card(c) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := W.hbox(10)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	info.add_child(W.label("Squad %.0f  %s" % [c.average_overall(), _stars(c.average_overall())], 12, "muted"))
	row.add_child(info)
	b.add_child(row)
	b.pressed.connect(func(): _select(c.id))
	_club_buttons[c.id] = b
	return b


func _stars(avg: float) -> String:
	var n := clampi(roundi((avg - 64.0) / 4.0) + 1, 1, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)


func _select(id: String) -> void:
	_selected = id
	for k in _club_buttons:
		_club_buttons[k].button_pressed = (k == id)
	var c = null
	for cl in _clubs:
		if cl.id == id:
			c = cl
	_detail.text = "%s: squad strength %.0f, %d players." % [c.name, c.average_overall(), c.players.size()]
	if app.season != null:
		_detail.text += "  Starting will replace your saved career."
	_start_btn.disabled = false


func _pick_random() -> void:
	_select(_clubs[app.rng.randi_range(0, _clubs.size() - 1)].id)


func _start() -> void:
	if _selected != "":
		app.start_career(_selected)
