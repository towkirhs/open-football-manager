extends Control
## Match screen (first playable piece).
## Pick your club and an opponent, set formation, style and mentality, then watch the
## match play out as a text feed. At half-time the match stops so you can change tactics.
## The opponent can be run by an AI manager, who picks tactics and may react at half-time.

const Tactics = preload("res://src/sim/tactics.gd")
const MatchEngine = preload("res://src/sim/match_engine.gd")
const Lineup = preload("res://src/sim/lineup.gd")
const AiManager = preload("res://src/sim/ai_manager.gd")
const WorldLoader = preload("res://src/data/world_loader.gd")

const SAMPLE := "res://data/sample/sample_league.json"
const SPEEDS := {"Slow": 0.8, "Normal": 0.4, "Fast": 0.12}

const BG := Color("#0f1a14")
const PANEL := Color("#16251c")
const ACCENT := Color("#2fbf71")
const TEXT := Color("#e8f5ec")
const MUTED := Color("#8aa597")

var clubs: Array = []
var rng := RandomNumberGenerator.new()
var engine = null
var away_ai = null
var timer: Timer

var home_ui := {}
var away_ui := {}
var score_label: Label
var clock_label: Label
var info_label: Label
var feed: RichTextLabel
var start_btn: Button
var continue_btn: Button
var speed_opt: OptionButton
var ai_check: CheckBox


func _ready() -> void:
	rng.randomize()
	clubs = WorldLoader.load_league(SAMPLE)["clubs"]
	_build_ui()
	timer = Timer.new()
	timer.wait_time = SPEEDS["Normal"]
	timer.timeout.connect(_on_tick)
	add_child(timer)
	if clubs.size() < 2:
		info_label.text = "No sample league found. Run tools/make_sample_league.gd first."
		start_btn.disabled = true


# ---------------------------------------------------------------- layout

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	home_ui = _side_panel("YOUR CLUB", 0)
	row.add_child(home_ui["panel"])

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 10)
	row.add_child(center)

	score_label = _label("Pick clubs and press Kick off", 26, TEXT)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(score_label)

	clock_label = _label("0'", 18, ACCENT)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(clock_label)

	info_label = _label("", 14, MUTED)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(info_label)

	var feed_panel := _panel()
	feed_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(feed_panel)
	feed = RichTextLabel.new()
	feed.bbcode_enabled = true
	feed.scroll_following = true
	feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed.add_theme_color_override("default_color", TEXT)
	feed.add_theme_font_size_override("normal_font_size", 15)
	feed.add_theme_font_size_override("bold_font_size", 15)
	feed_panel.add_child(feed)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	center.add_child(buttons)

	start_btn = _button("Kick off")
	start_btn.pressed.connect(_on_start)
	buttons.add_child(start_btn)

	continue_btn = _button("Start second half")
	continue_btn.visible = false
	continue_btn.pressed.connect(_on_continue)
	buttons.add_child(continue_btn)

	buttons.add_child(_label("Speed", 14, MUTED))
	speed_opt = OptionButton.new()
	for k in SPEEDS:
		speed_opt.add_item(k)
	speed_opt.select(1)
	speed_opt.item_selected.connect(func(i): timer.wait_time = SPEEDS[speed_opt.get_item_text(i)])
	buttons.add_child(speed_opt)

	away_ui = _side_panel("OPPONENT", 1)
	row.add_child(away_ui["panel"])
	ai_check = CheckBox.new()
	ai_check.text = "AI manager picks tactics"
	ai_check.button_pressed = true
	ai_check.add_theme_color_override("font_color", TEXT)
	ai_check.toggled.connect(func(on): _set_side_enabled(away_ui, not on, true))
	away_ui["box"].add_child(ai_check)
	_set_side_enabled(away_ui, false, true)


func _side_panel(title: String, default_index: int) -> Dictionary:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(270, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label(title, 13, MUTED))

	var club := OptionButton.new()
	for c in clubs:
		club.add_item("%s (%.0f)" % [c.name, c.average_overall()])
	if clubs.size() > default_index:
		club.select(default_index)
	box.add_child(club)

	box.add_child(_label("Formation", 13, MUTED))
	var formation := OptionButton.new()
	for f in Tactics.formation_names():
		formation.add_item(f)
	box.add_child(formation)

	box.add_child(_label("Playing style", 13, MUTED))
	var style := OptionButton.new()
	for s in Tactics.STYLE_NAMES:
		style.add_item(s)
	style.select(Tactics.Style.POSSESSION)
	box.add_child(style)

	var hint := _label("", 12, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	style.item_selected.connect(func(i): hint.text = _style_hint(i))
	hint.text = _style_hint(style.selected)

	box.add_child(_label("Mentality", 13, MUTED))
	var mentality := OptionButton.new()
	for m in Tactics.MENTALITY_NAMES:
		mentality.add_item(m)
	mentality.select(Tactics.Mentality.BALANCED)
	box.add_child(mentality)

	var stats := _label("", 13, TEXT)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(stats)

	return {"panel": panel, "box": box, "club": club, "formation": formation, "style": style,
		"mentality": mentality, "stats": stats, "hint": hint}


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


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate()
	hover.bg_color = ACCENT.lightened(0.15)
	b.add_theme_stylebox_override("hover", hover)
	var off := sb.duplicate()
	off.bg_color = PANEL.lightened(0.08)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_color_override("font_color", BG)
	b.add_theme_color_override("font_hover_color", BG)
	return b


func _set_side_enabled(ui: Dictionary, enabled: bool, tactics_only: bool = false) -> void:
	if not tactics_only:
		ui["club"].disabled = not enabled
	ui["formation"].disabled = not enabled
	ui["style"].disabled = not enabled
	ui["mentality"].disabled = not enabled


func _tactics_from(ui: Dictionary):
	var t = Tactics.new()
	t.formation = ui["formation"].get_item_text(ui["formation"].selected)
	t.style = ui["style"].selected
	t.mentality = ui["mentality"].selected
	t.familiarity = 0.85
	return t


func _show_tactics(ui: Dictionary, t) -> void:
	var forms: Array = Tactics.formation_names()
	ui["formation"].select(forms.find(t.formation))
	ui["style"].select(t.style)
	ui["hint"].text = _style_hint(t.style)
	ui["mentality"].select(t.mentality)


# ---------------------------------------------------------------- match flow

func _on_start() -> void:
	var hi: int = home_ui["club"].selected
	var ai_idx: int = away_ui["club"].selected
	if hi == ai_idx:
		info_label.text = "Pick two different clubs."
		return
	var home_club = clubs[hi]
	var away_club = clubs[ai_idx]
	var ht = _tactics_from(home_ui)
	var at = _tactics_from(away_ui)
	away_ai = null
	if ai_check.button_pressed:
		away_ai = AiManager.new()
		away_ai.setup_random(rng)
		at = away_ai.pick_tactics(ht.style if rng.randf() < away_ai.adaptiveness else -1, rng)
		_show_tactics(away_ui, at)

	var hl = Lineup.new()
	hl.auto_pick(home_club.players, ht.formation)
	var al = Lineup.new()
	al.auto_pick(away_club.players, at.formation)
	engine = MatchEngine.new()
	engine.setup(home_club.name, hl, ht, away_club.name, al, at, rng)
	if away_ai != null:
		engine.set_ai(1, away_ai)

	feed.clear()
	feed.append_text("[color=#8aa597]%s (%s) vs %s (%s)[/color]\n" % [home_club.name, ht.describe(), away_club.name, at.describe()])
	_post_lineups(hl, al)
	info_label.text = _matchup_text(ht, at)
	_set_side_enabled(home_ui, false)
	_set_side_enabled(away_ui, false)
	ai_check.disabled = true
	start_btn.disabled = true
	home_ui["stats"].text = ""
	away_ui["stats"].text = ""
	_refresh_score()
	timer.start()


func _on_tick() -> void:
	if engine == null:
		return
	for ev in engine.step():
		_post_event(ev)
	_refresh_score()
	if engine.is_half_time():
		timer.stop()
		info_label.text = "Half-time. Change your formation, style or mentality, then start the second half."
		_set_side_enabled(home_ui, true, true)
		continue_btn.visible = true
	elif engine.finished:
		timer.stop()
		_post_summary()
		start_btn.disabled = false
		_set_side_enabled(home_ui, true)
		ai_check.disabled = false
		_set_side_enabled(away_ui, not ai_check.button_pressed, ai_check.button_pressed)
		away_ui["club"].disabled = false


func _on_continue() -> void:
	var t = _tactics_from(home_ui)
	if not t.same_as(engine.home.tactics):
		var keep: float = engine.home.tactics.familiarity if t.style == engine.home.tactics.style else 0.75
		t.familiarity = keep
		engine.set_tactics(0, t)
		feed.append_text("[color=#2fbf71]You change tactics: %s.[/color]\n" % t.describe())
	_show_tactics(away_ui, engine.away.tactics)
	info_label.text = _matchup_text(engine.home.tactics, engine.away.tactics)
	_set_side_enabled(home_ui, false)
	continue_btn.visible = false
	engine.resume()
	timer.start()


func _refresh_score() -> void:
	score_label.text = engine.score_text()
	clock_label.text = "%d'" % engine.minute()
	var r: Dictionary = engine.result()
	home_ui["stats"].text = "Shots %d (%d on target)\nPossession %d%%" % [r["home_shots"], r["home_on_target"], r["home_possession"]]
	away_ui["stats"].text = "Shots %d (%d on target)\nPossession %d%%" % [r["away_shots"], r["away_on_target"], 100 - r["home_possession"]]


func _matchup_text(ht, at) -> String:
	match Tactics.matchup(ht.style, at.style):
		1:
			return "Your %s has the edge over their %s." % [Tactics.STYLE_NAMES[ht.style], Tactics.STYLE_NAMES[at.style]]
		-1:
			return "Their %s has the edge over your %s." % [Tactics.STYLE_NAMES[at.style], Tactics.STYLE_NAMES[ht.style]]
	return "Neither style has a clear edge."


func _post_lineups(hl, al) -> void:
	for pair in [[hl, engine.home.name], [al, engine.away.name]]:
		var names: Array = []
		for slot in pair[0].slots:
			if slot["player"] != null:
				names.append("%s %s" % [slot["role"], slot["player"].name.get_slice(" ", 1)])
		feed.append_text("[color=#8aa597]%s: %s[/color]\n" % [pair[1], ", ".join(names)])
	feed.append_text("\n")


func _post_event(ev: Dictionary) -> void:
	var t: String = ev["text"]
	match ev["type"]:
		"goal":
			feed.append_text("[b][color=#2fbf71]%d'  %s[/color][/b]\n" % [ev["minute"], t])
		"chance":
			feed.append_text("[color=#8aa597]%d'  %s[/color]\n" % [ev["minute"], t])
		"yellow":
			feed.append_text("[color=#f2c14e]%d'  %s[/color]\n" % [ev["minute"], t])
		"red", "injury":
			feed.append_text("[color=#ef5350]%d'  %s[/color]\n" % [ev["minute"], t])
		"half_time", "full_time":
			feed.append_text("\n[b]%s[/b]\n\n" % t)
		_:
			feed.append_text("%d'  %s\n" % [ev["minute"], t])


func _post_summary() -> void:
	var r: Dictionary = engine.result()
	feed.append_text("[b]Player ratings[/b]\n")
	for pair in [[engine.home, "Your team"], [engine.away, "Opponent"]]:
		var side = pair[0]
		var rows: Array = []
		for id in side.played:
			rows.append([id, float(r["ratings"].get(id, 6.0))])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		var parts: Array = []
		for row in rows.slice(0, 3):
			parts.append("%s %.1f" % [_player_name(side, row[0]), row[1]])
		feed.append_text("%s best: %s\n" % [pair[1], ", ".join(parts)])
	info_label.text = "Full-time. Change anything and kick off again."


func _player_name(side, id: String) -> String:
	for p in side.lineup.players_on_pitch() + side.lineup.bench:
		if p.id == id:
			return p.name
	# Players taken off are no longer in the lineup; look them up in the squad.
	for c in clubs:
		if c.name == side.name:
			for p in c.players:
				if p.id == id:
					return p.name
	return id
