extends Control
## The club hub: everything between matches.
## Tabs: Home (next match, tactics, table, news), Squad, League, Fixtures, Settings.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Tactics = preload("res://src/sim/tactics.gd")
const Lineup = preload("res://src/sim/lineup.gd")

const TABS := [["home", "Home"], ["squad", "Squad"], ["league", "League"], ["fixtures", "Fixtures"], ["settings", "Settings"]]
const POS_ORDER := ["GK", "CB", "FB", "DM", "CM", "AM", "WG", "ST"]

var app = null
var season = null
var _content: Control
var _tab_buttons: Dictionary = {}
var _squad_sort: int = 0
var _squad_desc: bool = true
var _results_week: int = -1


func _ready() -> void:
	season = app.season
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root := W.vbox(12)
	margin.add_child(root)
	root.add_child(_top_bar())
	root.add_child(_tab_bar())
	_content = W.vbox(12)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content)
	_open(app.hub_tab)


func _top_bar() -> Control:
	var bar := W.hbox(14)
	var club = season.user_club()
	bar.add_child(W.shield(club, 46))
	var names := W.vbox(0)
	names.add_child(W.label(club.name, 22))
	var wk: int = mini(season.week + 1, season.total_weeks())
	var sub := "%s  ·  Season %d/%02d  ·  Week %d of %d" % [season.league_name, season.year, (season.year + 1) % 100, wk, season.total_weeks()]
	names.add_child(W.label(sub, 13, "muted"))
	bar.add_child(names)
	bar.add_child(W.spacer())
	var pos: int = season.position_of(club.id)
	var t: Dictionary = season.table[club.id]
	var stat := W.vbox(0)
	var pos_label := W.label(season.ordinal(pos) if t["p"] > 0 else "–", 24, "accent")
	pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat.add_child(pos_label)
	var pts := W.label("%d pts from %d games" % [t["pts"], t["p"]], 13, "muted")
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat.add_child(pts)
	bar.add_child(stat)
	return bar


func _tab_bar() -> Control:
	var bar := W.hbox(6)
	var group := ButtonGroup.new()
	for tab in TABS:
		var b := Button.new()
		b.text = tab[1]
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "TabButton"
		b.custom_minimum_size = Vector2(96, 36)
		b.pressed.connect(func(): _open(tab[0]))
		_tab_buttons[tab[0]] = b
		bar.add_child(b)
	return bar


func _open(tab: String) -> void:
	app.hub_tab = tab
	if _tab_buttons.has(tab):
		_tab_buttons[tab].button_pressed = true
	W.clear_children(_content)
	match tab:
		"squad": _build_squad()
		"league": _build_league()
		"fixtures": _build_fixtures()
		"settings": _build_settings()
		_: _build_home()


# ---------------------------------------------------------------- Home

func _build_home() -> void:
	var cols := W.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)

	var left := W.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	cols.add_child(left)
	if season.is_finished():
		left.add_child(_season_over_card())
	else:
		left.add_child(_next_match_card())
	left.add_child(_last_result_card())

	var right := W.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_mini_table())
	right.add_child(_news_card())


func _next_match_card() -> Control:
	var card := W.panel()
	var v := W.vbox(10)
	card.add_child(v)
	var f: Dictionary = season.user_fixture()
	var opp_id: String = f["away"] if f["user_home"] else f["home"]
	var opp = season.club(opp_id)
	v.add_child(W.heading("Next match  ·  week %d" % (season.week + 1)))

	var row := W.hbox(14)
	v.add_child(row)
	row.add_child(W.shield(opp, 40))
	var info := W.vbox(2)
	info.add_child(W.label("%s  %s" % ["vs" if f["user_home"] else "at", opp.name], 20))
	var opp_pos: int = season.position_of(opp_id)
	var mgr = season.managers[opp_id]
	var played: bool = season.table[opp_id]["p"] > 0
	var line := "%s, squad %.0f" % [season.ordinal(opp_pos) if played else "Unranked", opp.average_overall()]
	line += "  ·  %s at home" % ("You are" if f["user_home"] else "They are")
	info.add_child(W.label(line, 13, "muted"))
	row.add_child(info)

	var usual: int = season.usual_style(opp_id)
	var scout := "Manager %s. " % mgr.name
	if usual >= 0:
		scout += "Lately they play %s." % Tactics.STYLE_NAMES[usual]
	else:
		scout += "No games yet; their usual style is unknown."
	v.add_child(W.wrap_label(scout, 14, "text"))

	v.add_child(W.heading("Your tactics"))
	var t = season.user_tactics
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	v.add_child(grid)
	var forms: Array = Tactics.formation_names()
	var fo := W.option(forms, forms.find(t.formation))
	var so := W.option(Tactics.STYLE_NAMES, t.style)
	var mo := W.option(Tactics.MENTALITY_NAMES, t.mentality)
	for o in [fo, so, mo]:
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(o)
	var hint := W.wrap_label("", 13, "muted")
	v.add_child(hint)
	var update := func():
		t.formation = forms[fo.selected]
		t.style = so.selected
		t.mentality = mo.selected
		hint.text = _tactic_hint(t.style, usual)
		app.save()
	fo.item_selected.connect(func(_i): update.call())
	so.item_selected.connect(func(_i): update.call())
	mo.item_selected.connect(func(_i): update.call())
	hint.text = _tactic_hint(t.style, usual)

	var buttons := W.hbox(10)
	v.add_child(buttons)
	var play := W.button("Play match", true)
	play.pressed.connect(app.play_match)
	buttons.add_child(play)
	var sim := W.button("Quick sim")
	sim.custom_minimum_size = Vector2(130, 42)
	sim.pressed.connect(app.quick_sim)
	buttons.add_child(sim)
	return card


func _tactic_hint(style: int, their_usual: int) -> String:
	var strong: Array = []
	var weak: Array = []
	for other in 5:
		var m := Tactics.matchup(style, other)
		if m == 1:
			strong.append(Tactics.STYLE_NAMES[other])
		elif m == -1:
			weak.append(Tactics.STYLE_NAMES[other])
	var text := "%s is strong vs %s, weak vs %s." % [Tactics.STYLE_NAMES[style], " and ".join(strong), " and ".join(weak)]
	if their_usual >= 0:
		match Tactics.matchup(style, their_usual):
			1: text += "  Good pick against their usual style."
			-1: text += "  Risky: their usual style beats this one."
	return text


func _season_over_card() -> Control:
	var card := W.panel()
	var v := W.vbox(10)
	card.add_child(v)
	var last: Dictionary = season.history[season.history.size() - 1]
	v.add_child(W.heading("Season over"))
	v.add_child(W.label("You finished %s with %d points." % [season.ordinal(int(last["user_position"])), int(last["user_points"])], 22))
	v.add_child(W.label("Champions: %s" % last["champion"], 15, "muted"))
	v.add_child(W.wrap_label("Ageing, transfers, promotion and relegation come in later updates. For now the next season starts with the same squads.", 13))
	var b := W.button("Start next season", true)
	b.pressed.connect(app.next_season)
	v.add_child(b)
	return card


func _last_result_card() -> Control:
	var card := W.panel()
	var v := W.vbox(8)
	card.add_child(v)
	v.add_child(W.heading("Recent results"))
	var shown := 0
	for w in range(season.results.size() - 1, -1, -1):
		var r: Dictionary = season.user_result(w)
		if r.is_empty():
			continue
		v.add_child(_result_line(w, r))
		shown += 1
		if shown >= 5:
			break
	if shown == 0:
		v.add_child(W.label("No games played yet.", 14, "muted"))
	return card


func _result_line(w: int, r: Dictionary) -> Control:
	var row := W.hbox(10)
	var user_home: bool = r["home"] == season.user_club_id
	var gf: int = r["hg"] if user_home else r["ag"]
	var ga: int = r["ag"] if user_home else r["hg"]
	var mark := "D"
	var key := "warn"
	if gf > ga:
		mark = "W"
		key = "good"
	elif gf < ga:
		mark = "L"
		key = "bad"
	var badge := W.label(mark, 15, key)
	badge.custom_minimum_size = Vector2(20, 0)
	row.add_child(badge)
	row.add_child(W.label("Wk %d" % (w + 1), 13, "muted"))
	row.add_child(W.label("%s %d-%d %s" % [season.club(r["home"]).name, r["hg"], r["ag"], season.club(r["away"]).name], 14))
	return row


func _mini_table() -> Control:
	var card := W.panel()
	var v := W.vbox(8)
	card.add_child(v)
	v.add_child(W.heading("League table"))
	var t := W.table(["#", "Club", "P", "GD", "Pts"], [34, 0, 40, 48, 48])
	t.size_flags_vertical = Control.SIZE_FILL
	t.scroll_vertical_enabled = false
	v.add_child(t)
	var order: Array = season.standings()
	var me: int = order.find(season.user_club_id)
	# The top four, plus your club and its neighbours.
	var rows := 0
	for i in order.size():
		var show_row: bool = i < 4 or absi(i - me) <= 1
		if not show_row:
			continue
		_table_row(t, i, order[i], false)
		rows += 1
	t.custom_minimum_size = Vector2(0, 40 + rows * 34)
	return card


func _table_row(t: Tree, i: int, id: String, full: bool) -> void:
	var row: Dictionary = season.table[id]
	var gd: int = row["gf"] - row["ga"]
	var vals: Array = [i + 1, season.club(id).name]
	if full:
		vals.append_array([row["p"], row["w"], row["d"], row["l"], row["gf"], row["ga"], ("+%d" % gd) if gd > 0 else str(gd), row["pts"], " ".join(row["form"])])
	else:
		vals.append_array([row["p"], ("+%d" % gd) if gd > 0 else str(gd), row["pts"]])
	var it := W.row(t, vals, "", "highlight" if id == season.user_club_id else "")
	if id == season.user_club_id:
		for c in vals.size():
			it.set_custom_color(c, UiTheme.c("accent"))


func _news_card() -> Control:
	var card := W.panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := W.vbox(6)
	card.add_child(v)
	v.add_child(W.heading("Inbox"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := W.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for n in season.news.slice(0, 12):
		var row := W.hbox(8)
		row.add_child(W.label("Wk %d" % n["week"], 12, "muted"))
		var l := W.wrap_label(n["text"], 14, "text")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		list.add_child(row)
	return card


# ---------------------------------------------------------------- Squad

func _build_squad() -> void:
	var club = season.user_club()
	var lineup = Lineup.new()
	lineup.auto_pick(club.players, season.user_tactics.formation)
	var starters := {}
	for p in lineup.players_on_pitch():
		starters[p.id] = true

	var head := W.hbox(10)
	head.add_child(W.label("%d players  ·  average %.1f" % [club.players.size(), club.average_overall()], 15))
	head.add_child(W.spacer())
	head.add_child(W.label("XI = picked for your %s. Click a column title to sort." % season.user_tactics.formation, 13, "muted"))
	_content.add_child(head)

	var titles := ["", "Pos", "Name", "Age", "Ovr", "Pot", "Fit", "Mor", "Status", "Apps", "Gls", "Ast", "Avg"]
	var t := W.table(titles, [34, 48, 0, 46, 50, 50, 50, 50, 90, 52, 48, 48, 52])
	_content.add_child(t)

	var rows: Array = []
	for p in club.players:
		var st: Dictionary = season.stats_for(p.id)
		var avg: float = st["rating_sum"] / st["apps"] if st["apps"] > 0 else 0.0
		rows.append({"p": p, "xi": starters.has(p.id), "pos": POS_ORDER.find(p.position), "avg": avg, "st": st})
	var keys := ["xi", "pos", "name", "age", "overall", "potential", "fitness", "morale", "injury", "apps", "goals", "assists", "avg"]
	var key: String = keys[_squad_sort]
	var by_column := func(a, b):
		var va = _sort_value(a, key)
		var vb = _sort_value(b, key)
		if va == vb:
			if a["pos"] != b["pos"]:
				return a["pos"] < b["pos"]
			return a["p"].overall > b["p"].overall
		return (va > vb) if _squad_desc else (va < vb)
	rows.sort_custom(by_column)

	for r in rows:
		var p = r["p"]
		var st: Dictionary = r["st"]
		var status := "Injured %dw" % p.injury_weeks if p.injury_weeks > 0 else "Fit"
		var vals := ["XI" if r["xi"] else "", p.position, p.name, p.age, p.overall, p.potential, roundi(p.fitness), roundi(p.morale), status,
			st["apps"], st["goals"], st["assists"], ("%.1f" % r["avg"]) if st["apps"] > 0 else "-"]
		var it := W.row(t, vals)
		if r["xi"]:
			it.set_custom_color(0, UiTheme.c("accent"))
		if p.injury_weeks > 0:
			it.set_custom_color(8, UiTheme.c("bad"))
		if p.fitness < 75:
			it.set_custom_color(6, UiTheme.c("warn"))

	t.column_title_clicked.connect(_on_squad_title_clicked)


func _on_squad_title_clicked(col: int, _btn: int) -> void:
	if col == _squad_sort:
		_squad_desc = not _squad_desc
	else:
		_squad_sort = col
		_squad_desc = col in [0, 4, 5, 6, 7, 9, 10, 11, 12]
	_open.call_deferred("squad")


func _sort_value(r: Dictionary, key: String):
	var p = r["p"]
	match key:
		"xi": return 1 if r["xi"] else 0
		"pos": return r["pos"]
		"name": return p.name
		"injury": return p.injury_weeks
		"apps", "goals", "assists": return r["st"][key]
		"avg": return r["avg"]
	return p.get(key)


# ---------------------------------------------------------------- League

func _build_league() -> void:
	var cols := W.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)

	var left := W.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	cols.add_child(left)
	left.add_child(W.heading(season.league_name))
	var t := W.table(["#", "Club", "P", "W", "D", "L", "GF", "GA", "GD", "Pts", "Form"], [34, 0, 40, 40, 40, 40, 44, 44, 48, 48, 110])
	left.add_child(t)
	var order: Array = season.standings()
	for i in order.size():
		_table_row(t, i, order[i], true)

	var right := W.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(W.heading("Top scorers"))
	var s := W.table(["Player", "Club", "Gls", "Ast"], [0, 54, 46, 46])
	right.add_child(s)
	var scorers: Array = season.top_scorers(15)
	for r in scorers:
		var it := W.row(s, [r["name"], r["club"], r["goals"], r["assists"]])
		if season.player(r["id"]) in season.user_club().players:
			for c in 4:
				it.set_custom_color(c, UiTheme.c("accent"))
	if scorers.is_empty():
		W.row(s, ["No goals yet", "", "", ""], "muted")


# ---------------------------------------------------------------- Fixtures

func _build_fixtures() -> void:
	var cols := W.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)

	var left := W.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(W.heading("Your fixtures"))
	var t := W.table(["Wk", "", "Opponent", "Result"], [44, 40, 0, 90])
	left.add_child(t)
	for w in season.total_weeks():
		var f: Dictionary = season.user_fixture(w)
		if f.is_empty():
			continue
		var opp_id: String = f["away"] if f["user_home"] else f["home"]
		var r: Dictionary = season.user_result(w)
		var res := ""
		var key := ""
		if not r.is_empty():
			var gf: int = r["hg"] if f["user_home"] else r["ag"]
			var ga: int = r["ag"] if f["user_home"] else r["hg"]
			res = "%s %d-%d" % ["W" if gf > ga else ("L" if gf < ga else "D"), gf, ga]
			key = "good" if gf > ga else ("bad" if gf < ga else "warn")
		var it := W.row(t, [w + 1, "H" if f["user_home"] else "A", season.club(opp_id).name, res], "", "highlight" if w == season.week else "")
		if key != "":
			it.set_custom_color(3, UiTheme.c(key))

	var right := W.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var head := W.hbox(8)
	right.add_child(head)
	head.add_child(W.heading("Results by week"))
	head.add_child(W.spacer())
	if season.results.is_empty():
		right.add_child(W.label("No games played yet.", 14, "muted"))
		return
	if _results_week < 0 or _results_week >= season.results.size():
		_results_week = season.results.size() - 1
	var weeks: Array = []
	for w in season.results.size():
		weeks.append("Week %d" % (w + 1))
	var pick := W.option(weeks, _results_week)
	pick.item_selected.connect(_on_results_week)
	head.add_child(pick)
	var rt := W.table(["Home", "", "Away"], [0, 70, 0])
	right.add_child(rt)
	for r in season.results[_results_week]:
		var mine: bool = r["home"] == season.user_club_id or r["away"] == season.user_club_id
		var it := W.row(rt, [season.club(r["home"]).name, "%d - %d" % [r["hg"], r["ag"]], season.club(r["away"]).name], "accent" if mine else "")
		it.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)


func _on_results_week(i: int) -> void:
	_results_week = i
	_open.call_deferred("fixtures")


# ---------------------------------------------------------------- Settings

func _build_settings() -> void:
	var card := W.panel()
	_content.add_child(card)
	var v := W.vbox(12)
	card.add_child(v)
	v.add_child(W.heading("Colour theme"))
	var swatches := W.hbox(10)
	v.add_child(swatches)
	for theme_name in UiTheme.names():
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = theme_name == UiTheme.current
		b.text = theme_name
		b.custom_minimum_size = Vector2(150, 64)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiTheme.THEMES[theme_name]["panel"])
		sb.border_color = Color(UiTheme.THEMES[theme_name]["accent"])
		sb.set_border_width_all(4 if theme_name == UiTheme.current else 2)
		sb.set_corner_radius_all(10)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, sb)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color(UiTheme.THEMES[theme_name]["text"]))
		b.pressed.connect(func(): app.set_theme_name(theme_name))
		swatches.add_child(b)

	v.add_child(HSeparator.new())
	v.add_child(W.heading("Career"))
	v.add_child(W.wrap_label("Your career saves automatically after every match.", 14))
	var row := W.hbox(10)
	v.add_child(row)
	var menu := W.button("Main menu")
	menu.custom_minimum_size = Vector2(140, 40)
	menu.pressed.connect(app.show_new_game)
	row.add_child(menu)
	var del := W.button("Delete career")
	del.custom_minimum_size = Vector2(140, 40)
	del.add_theme_color_override("font_color", UiTheme.c("bad"))
	row.add_child(del)
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Delete this career? This cannot be undone."
	confirm.confirmed.connect(app.delete_career)
	add_child(confirm)
	del.pressed.connect(func(): confirm.popup_centered())

	v.add_child(HSeparator.new())
	v.add_child(W.heading("About"))
	v.add_child(W.wrap_label("Open Football Manager is free and open source. No payments, ever. All clubs and players in this build are fictional.", 14))
