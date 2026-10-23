extends Control
## Live match. The match plays out as a text feed; it stops at half-time so you can
## change formation, style or mentality. At full-time, Continue returns to the club.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Tactics = preload("res://src/sim/tactics.gd")
const Lineup = preload("res://src/sim/lineup.gd")

const SPEEDS := {"Slow": 0.8, "Normal": 0.4, "Fast": 0.12}

var app = null
var engine = null
## 0 when the human's club is at home, 1 when away.
var user_side: int = 0

var _timer: Timer
var _score: Label
var _clock: Label
var _info: Label
var _feed: RichTextLabel
var _main_btn: Button
var _skip_btn: Button
var _formation: OptionButton
var _style: OptionButton
var _mentality: OptionButton
var _hint: Label
var _my_stats: Label
var _their_stats: Label
var _their_tactics: Label
var _state: String = "playing"


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var row := W.hbox(14)
	margin.add_child(row)

	row.add_child(_my_panel())

	var center := W.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	_score = W.label("", 26)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_score)
	_clock = W.label("0'", 18, "accent")
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_clock)
	_info = W.wrap_label("", 14, "muted")
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_info)

	var feed_panel := W.panel()
	feed_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(feed_panel)
	_feed = RichTextLabel.new()
	_feed.bbcode_enabled = true
	_feed.scroll_following = true
	_feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_feed.add_theme_font_size_override("normal_font_size", 15)
	_feed.add_theme_font_size_override("bold_font_size", 15)
	feed_panel.add_child(_feed)

	var buttons := W.hbox(10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(buttons)
	_main_btn = W.button("Pause", true)
	_main_btn.pressed.connect(_on_main_button)
	buttons.add_child(_main_btn)
	_skip_btn = W.button("Skip to result")
	_skip_btn.custom_minimum_size = Vector2(140, 42)
	_skip_btn.pressed.connect(_skip)
	buttons.add_child(_skip_btn)
	buttons.add_child(W.label("Speed", 13, "muted"))
	var speed := W.option(SPEEDS.keys(), 1)
	speed.item_selected.connect(func(i): _timer.wait_time = SPEEDS[SPEEDS.keys()[i]])
	buttons.add_child(speed)

	row.add_child(_their_panel())

	_timer = Timer.new()
	_timer.wait_time = SPEEDS["Normal"]
	_timer.timeout.connect(_tick)
	add_child(_timer)

	_feed.append_text("[color=%s]%s  vs  %s[/color]\n" % [UiTheme.hex("muted"), _side(0).tactics.describe(), _side(1).tactics.describe()])
	_post_lineup(_me())
	_post_lineup(_them())
	_feed.append_text("\n")
	_set_tactics_enabled(false)
	_info.text = _matchup_text()
	_refresh()
	_timer.start()


func _me():
	return engine.home if user_side == 0 else engine.away


func _them():
	return engine.away if user_side == 0 else engine.home


func _side(i: int):
	return engine.home if i == 0 else engine.away


# ---------------------------------------------------------------- panels

func _my_panel() -> Control:
	var p := W.panel()
	p.custom_minimum_size = Vector2(260, 0)
	var v := W.vbox(8)
	p.add_child(v)
	v.add_child(W.heading("Your team"))
	v.add_child(W.label(_me().name, 17))
	v.add_child(W.label("Formation", 13, "muted"))
	var forms: Array = Tactics.formation_names()
	_formation = W.option(forms, forms.find(_me().tactics.formation))
	v.add_child(_formation)
	v.add_child(W.label("Playing style", 13, "muted"))
	_style = W.option(Tactics.STYLE_NAMES, _me().tactics.style)
	_style.item_selected.connect(func(_i): _hint.text = _style_hint(_style.selected))
	v.add_child(_style)
	_hint = W.wrap_label(_style_hint(_me().tactics.style), 12)
	v.add_child(_hint)
	v.add_child(W.label("Mentality", 13, "muted"))
	_mentality = W.option(Tactics.MENTALITY_NAMES, _me().tactics.mentality)
	v.add_child(_mentality)
	v.add_child(HSeparator.new())
	_my_stats = W.label("", 14)
	v.add_child(_my_stats)
	return p


func _their_panel() -> Control:
	var p := W.panel()
	p.custom_minimum_size = Vector2(260, 0)
	var v := W.vbox(8)
	p.add_child(v)
	v.add_child(W.heading("Opponent"))
	v.add_child(W.label(_them().name, 17))
	_their_tactics = W.wrap_label("", 14, "text")
	v.add_child(_their_tactics)
	v.add_child(HSeparator.new())
	_their_stats = W.label("", 14)
	v.add_child(_their_stats)
	return p


func _style_hint(style: int) -> String:
	var strong: Array = []
	var weak: Array = []
	for other in 5:
		var m := Tactics.matchup(style, other)
		if m == 1:
			strong.append(Tactics.STYLE_NAMES[other])
		elif m == -1:
			weak.append(Tactics.STYLE_NAMES[other])
	return "Strong vs %s. Weak vs %s." % [", ".join(strong), ", ".join(weak)]


func _set_tactics_enabled(on: bool) -> void:
	_formation.disabled = not on
	_style.disabled = not on
	_mentality.disabled = not on


func _matchup_text() -> String:
	var mine: int = _me().tactics.style
	var theirs: int = _them().tactics.style
	match Tactics.matchup(mine, theirs):
		1:
			return "Your %s has the edge over their %s." % [Tactics.STYLE_NAMES[mine], Tactics.STYLE_NAMES[theirs]]
		-1:
			return "Their %s has the edge over your %s." % [Tactics.STYLE_NAMES[theirs], Tactics.STYLE_NAMES[mine]]
	return "Neither style has a clear edge."


# ---------------------------------------------------------------- flow

func _tick() -> void:
	for ev in engine.step():
		_post(ev)
	_refresh()
	if engine.is_half_time():
		_timer.stop()
		_state = "half_time"
		_info.text = "Half-time. Change your formation, style or mentality, then start the second half."
		_set_tactics_enabled(true)
		_main_btn.text = "Start second half"
	elif engine.finished:
		_full_time()


func _on_main_button() -> void:
	match _state:
		"playing":
			_timer.stop()
			_state = "paused"
			_main_btn.text = "Resume"
		"paused":
			_timer.start()
			_state = "playing"
			_main_btn.text = "Pause"
		"half_time":
			_apply_half_time_changes()
			engine.resume()
			_state = "playing"
			_main_btn.text = "Pause"
			_info.text = _matchup_text()
			_timer.start()
		"done":
			app.finish_match(engine)


func _apply_half_time_changes() -> void:
	var cur = _me().tactics
	var t = Tactics.new()
	t.formation = _formation.get_item_text(_formation.selected)
	t.style = _style.selected
	t.mentality = _mentality.selected
	# Switching to a different style mid-match costs some familiarity.
	t.familiarity = cur.familiarity if t.style == cur.style else 0.75
	_set_tactics_enabled(false)
	if not t.same_as(cur):
		engine.set_tactics(user_side, t)
		_feed.append_text("[color=%s]You change tactics: %s.[/color]\n" % [UiTheme.hex("accent"), t.describe()])
		# The formation change also needs a new shape on the pitch.
		if t.formation != cur.formation:
			_reshape(t.formation)


## Moves the players still on the pitch into the new formation's roles.
## A side that is down to ten men keeps an empty slot.
func _reshape(formation: String) -> void:
	var side = _me()
	var on_pitch: Array = []
	for slot in side.lineup.slots:
		var p = slot["player"]
		if p != null and not side.sent_off.has(p.id) and not side.injured.has(p.id):
			on_pitch.append(p)
	var fresh = Lineup.new()
	fresh.auto_pick(on_pitch, formation, 0)
	side.lineup.formation = formation
	side.lineup.slots = fresh.slots


func _skip() -> void:
	_timer.stop()
	if engine.is_half_time():
		_apply_half_time_changes()
	while not engine.finished:
		if engine.is_half_time():
			engine.resume()
		for ev in engine.step():
			_post(ev)
	_refresh()
	_full_time()


func _full_time() -> void:
	_timer.stop()
	_state = "done"
	_main_btn.text = "Continue"
	_skip_btn.disabled = true
	_set_tactics_enabled(false)
	var me = _me()
	var them = _them()
	if me.goals > them.goals:
		_info.text = "Full-time. A win!"
	elif me.goals < them.goals:
		_info.text = "Full-time. A defeat."
	else:
		_info.text = "Full-time. A draw."
	_post_ratings()


func _refresh() -> void:
	_score.text = engine.score_text()
	_clock.text = "%d'" % engine.minute()
	var r: Dictionary = engine.result()
	var poss_home: int = r["home_possession"]
	var mine := "home" if user_side == 0 else "away"
	var theirs := "away" if user_side == 0 else "home"
	_my_stats.text = "Shots %d (%d on target)\nPossession %d%%" % [r[mine + "_shots"], r[mine + "_on_target"], poss_home if user_side == 0 else 100 - poss_home]
	_their_stats.text = "Shots %d (%d on target)\nPossession %d%%" % [r[theirs + "_shots"], r[theirs + "_on_target"], 100 - poss_home if user_side == 0 else poss_home]
	_their_tactics.text = "%s\n%s, %s" % [_them().tactics.formation, Tactics.STYLE_NAMES[_them().tactics.style], Tactics.MENTALITY_NAMES[_them().tactics.mentality]]


# ---------------------------------------------------------------- feed

func _post_lineup(side) -> void:
	var names: Array = []
	for slot in side.lineup.slots:
		if slot["player"] != null:
			var parts: PackedStringArray = slot["player"].name.split(" ")
			names.append("%s %s. %s" % [slot["role"], parts[0].left(1), parts[parts.size() - 1]])
	_feed.append_text("[color=%s]%s: %s[/color]\n" % [UiTheme.hex("muted"), side.name, ", ".join(names)])


func _post(ev: Dictionary) -> void:
	var t: String = ev["text"]
	var mine: bool = ev["side"] == ("home" if user_side == 0 else "away")
	match ev["type"]:
		"goal":
			var col := UiTheme.hex("good") if mine else UiTheme.hex("bad")
			_feed.append_text("[b][color=%s]%d'  %s[/color][/b]\n" % [col, ev["minute"], t])
		"chance":
			_feed.append_text("[color=%s]%d'  %s[/color]\n" % [UiTheme.hex("muted"), ev["minute"], t])
		"yellow":
			_feed.append_text("[color=%s]%d'  %s[/color]\n" % [UiTheme.hex("warn"), ev["minute"], t])
		"red", "injury":
			_feed.append_text("[color=%s]%d'  %s[/color]\n" % [UiTheme.hex("bad"), ev["minute"], t])
		"half_time", "full_time":
			_feed.append_text("\n[b]%s[/b]\n\n" % t)
		"tactics":
			_feed.append_text("[color=%s]%d'  %s[/color]\n" % [UiTheme.hex("accent") if mine else UiTheme.hex("warn"), ev["minute"], t])
		_:
			_feed.append_text("%d'  %s\n" % [ev["minute"], t])


func _post_ratings() -> void:
	var r: Dictionary = engine.result()
	_feed.append_text("[b]Player ratings[/b]\n")
	for side in [_me(), _them()]:
		var rows: Array = []
		for id in side.played:
			rows.append([id, float(r["ratings"].get(id, 6.0))])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		var parts: Array = []
		for row in rows.slice(0, 3):
			var p = app.season.player(row[0])
			parts.append("%s %.1f" % [p.name if p != null else row[0], row[1]])
		_feed.append_text("%s best: %s\n" % [side.name, ", ".join(parts)])
