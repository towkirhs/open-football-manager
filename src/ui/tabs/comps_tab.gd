extends VBoxContainer
## Competitions: any league (table, scorers, award race), any cup (rounds), any
## European cup (groups and knockouts), plus honours and awards.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const CompEurope = preload("res://src/sim/comp_europe.gd")

static var choice: String = ""

var hub = null
var season = null
var _ids: Array = []


func _ready() -> void:
	season = hub.season
	var head := W.hbox(10)
	add_child(head)
	var pick := OptionButton.new()
	_ids = []
	for k in season.comps_for(season.user_club_id):
		_ids.append(k.id)
	for id in season.comps:
		if not _ids.has(id):
			_ids.append(id)
	_ids.append("@honours")
	_ids.append("@awards")
	for id in _ids:
		if id == "@honours":
			pick.add_item("Honours: past winners")
		elif id == "@awards":
			pick.add_item("Awards: past seasons")
		else:
			var k = season.comp(id)
			pick.add_item(("★ " if k.involves(season.user_club_id) else "") + k.name)
	if choice == "" or not _ids.has(choice):
		choice = _ids[0]
	pick.select(_ids.find(choice))
	pick.item_selected.connect(func(i):
		choice = _ids[i]
		hub.open_tab.call_deferred("comps"))
	head.add_child(pick)
	head.add_child(W.spacer())
	head.add_child(W.label("★ = you play in it", 13, "muted"))

	match choice:
		"@honours": _honours()
		"@awards": _awards()
		_:
			var k = season.comp(choice)
			match k.kind:
				"league": _league(k)
				"cup": _cup(k)
				"europe": _europe(k)


func _club_name(id: String) -> String:
	var c = season.club(id)
	return c.name if c != null else "?"


func _player_name(id: String) -> String:
	var p = season.player(id)
	return p.name if p != null else "(retired)"


# ---------------------------------------------------------------- league

func _league(l) -> void:
	var cols := W.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)
	var left := W.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	cols.add_child(left)
	var note := "%d clubs  ·  %d rounds played" % [l.clubs.size(), l.results.size()]
	if l.relegate > 0:
		note += "  ·  bottom %d go down" % l.relegate
	if l.tier > 1:
		note += "  ·  top %d go up" % _promoted_places(l)
	left.add_child(W.label(note, 13, "muted"))
	var t := W.table(["#", "Club", "P", "W", "D", "L", "GF", "GA", "GD", "Pts", "Form"], [46, 0, 40, 40, 40, 40, 44, 44, 48, 48, 80])
	left.add_child(t)
	var order: Array = l.standings()
	var up: int = _promoted_places(l) if l.tier > 1 else 0
	var europe: int = 7 if l.tier == 1 else 0
	for i in order.size():
		var r: Array = l.table[order[i]]
		var gd: int = r[4] - r[5]
		var key := ""
		if i < up or i < europe:
			key = "good"
		elif l.relegate > 0 and i >= order.size() - l.relegate:
			key = "bad"
		var mine: bool = order[i] == season.user_club_id
		var it := W.row(t, [i + 1, _club_name(order[i]), r[0], r[1], r[2], r[3], r[4], r[5], ("+%d" % gd) if gd > 0 else str(gd), r[6], r[7]],
			"", "highlight" if mine else "")
		if key != "":
			it.set_custom_color(0, UiTheme.c(key))
		if mine:
			for c in 11:
				it.set_custom_color(c, UiTheme.c("accent"))
		it.set_metadata(0, order[i])

	var right := W.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(W.heading("Top scorers"))
	var s := W.table(["Player", "Club", "Gls", "Ast"], [0, 60, 46, 46])
	s.custom_minimum_size = Vector2(0, 260)
	s.size_flags_vertical = Control.SIZE_FILL
	right.add_child(s)
	for r in season.top_scorers(l.id, 12):
		var it := W.row(s, [_player_name(r["id"]), season.club(season.club_of(r["id"])).short_name if season.club_of(r["id"]) != "" else "", r["goals"], r["assists"]])
		if season.club_of(r["id"]) == season.user_club_id:
			for c in 4:
				it.set_custom_color(c, UiTheme.c("accent"))
	right.add_child(W.heading("Award race"))
	var race: Dictionary = season.award_race(l.id, 3)
	for pair in [["best", "Player of the Season (avg rating)"], ["young", "Young Player (21 and under)"]]:
		var rows: Array = race[pair[0]]
		if rows.is_empty():
			continue
		var names: Array = rows.map(func(r): return "%s %.2f" % [_player_name(r["id"]), float(r["value"])])
		right.add_child(W.wrap_label("%s: %s" % [pair[1], ", ".join(names)], 13, "text"))


func _promoted_places(l) -> int:
	for d in season.league_defs:
		if d["country"] == l.country and int(d["tier"]) == l.tier - 1:
			return int(d.get("relegate", 0))
	return 0


# ---------------------------------------------------------------- cup

func _cup(k) -> void:
	var sb: Array = W.scroll_box()
	add_child(sb[0])
	var v: VBoxContainer = sb[1]
	if k.winner != "":
		v.add_child(W.label("Winner: %s" % _club_name(k.winner), 20, "accent"))
	elif k.involves(season.user_club_id):
		v.add_child(W.label("You are %s." % ("still in the cup" if k.alive(season.user_club_id) else "out (%s)" % k.reached(season.user_club_id)), 15, "text"))
	for r in range(k.ties.size() - 1, -1, -1):
		var card := W.panel()
		v.add_child(card)
		var cv := W.vbox(4)
		card.add_child(cv)
		cv.add_child(W.heading(k.round_name(r)))
		var played: bool = r < k.results.size()
		var lines: Array = []
		if played:
			for x in k.results[r]:
				var line := "%s %d-%d %s" % [_club_name(x[0]), int(x[2]), int(x[3]), _club_name(x[1])]
				if int(x[2]) == int(x[3]):
					line += " (%s on penalties)" % _club_name(x[4])
				lines.append(line)
		else:
			for t in k.ties[r]:
				lines.append("%s vs %s" % [_club_name(t[0]), _club_name(t[1])])
		_lines(cv, lines)


func _lines(box: VBoxContainer, lines: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	box.add_child(grid)
	for line in lines:
		var mine: bool = line.contains(season.user_club().name)
		grid.add_child(W.label(line, 14, "accent" if mine else "text"))


# ---------------------------------------------------------------- europe

func _europe(k) -> void:
	var sb: Array = W.scroll_box()
	add_child(sb[0])
	var v: VBoxContainer = sb[1]
	if k.winner != "":
		v.add_child(W.label("Winner: %s" % _club_name(k.winner), 20, "accent"))
	if not k.final_tie.is_empty():
		var fr := ""
		if k.results.size() > CompEurope.GROUP_ROUNDS + 6:
			var x: Array = k.results[CompEurope.GROUP_ROUNDS + 6][0]
			fr = " — %d-%d%s" % [int(x[2]), int(x[3]), " (%s on penalties)" % _club_name(x[4]) if int(x[2]) == int(x[3]) else ""]
		v.add_child(W.label("Final: %s vs %s%s" % [_club_name(k.final_tie[0]), _club_name(k.final_tie[1]), fr], 16))
	for s in range(k.ko.size() - 1, -1, -1):
		var card := W.panel()
		v.add_child(card)
		var cv := W.vbox(4)
		card.add_child(cv)
		cv.add_child(W.heading(CompEurope.KO_NAMES[s]))
		var lines: Array = []
		for t in k.ko[s]:
			var r1: int = CompEurope.GROUP_ROUNDS + s * 2
			var line := "%s vs %s" % [_club_name(t[0]), _club_name(t[1])]
			var legs: Array = []
			for r in [r1, r1 + 1]:
				if r < k.results.size():
					for x in k.results[r]:
						if (x[0] == t[0] and x[1] == t[1]) or (x[0] == t[1] and x[1] == t[0]):
							legs.append("%d-%d" % [int(x[2]), int(x[3])])
							if x[4] != "":
								line += "  →  %s" % _club_name(x[4])
			if not legs.is_empty():
				line += "   [" + ", ".join(legs) + "]"
			lines.append(line)
		_lines(cv, lines)
	v.add_child(W.heading("Groups"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for g in k.groups.size():
		var card := W.panel()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var cv := W.vbox(4)
		card.add_child(cv)
		cv.add_child(W.heading("Group %s" % char(65 + g)))
		var t := W.table(["Club", "P", "GD", "Pts"], [0, 40, 48, 48])
		t.custom_minimum_size = Vector2(0, 180)
		t.scroll_vertical_enabled = false
		t.size_flags_vertical = Control.SIZE_FILL
		cv.add_child(t)
		var order: Array = k.group_standings(g)
		for i in order.size():
			var r: Array = k.table[order[i]]
			var it := W.row(t, ["%s (%s)" % [_club_name(order[i]), season.club(order[i]).country], r[0], r[4] - r[5], r[6]], "good" if i < 2 and k.results.size() >= CompEurope.GROUP_ROUNDS else "")
			if order[i] == season.user_club_id:
				for c in 4:
					it.set_custom_color(c, UiTheme.c("accent"))


# ---------------------------------------------------------------- honours and awards

func _honours() -> void:
	var t := W.table(["Season", "Competition", "Winner"], [90, 0, 0])
	add_child(t)
	if season.honours.is_empty():
		W.row(t, ["", "No seasons finished yet", ""], "muted")
	for i in range(season.honours.size() - 1, -1, -1):
		var h: Dictionary = season.honours[i]
		var it := W.row(t, ["%d/%02d" % [int(h["year"]), (int(h["year"]) + 1) % 100], h["comp"], _club_name(h["winner"])])
		if h["winner"] == season.user_club_id:
			for c in 3:
				it.set_custom_color(c, UiTheme.c("accent"))


func _awards() -> void:
	var t := W.table(["Season", "League", "Award", "Winner", "Club"], [90, 0, 0, 0, 0])
	add_child(t)
	if season.awards.is_empty():
		W.row(t, ["", "No seasons finished yet", "", "", ""], "muted")
	for i in range(season.awards.size() - 1, -1, -1):
		var a: Dictionary = season.awards[i]
		var who: String = str(a.get("manager", "")) if a["award"] == "Manager of the Season" else _player_name(str(a.get("player", "")))
		var it := W.row(t, ["%d/%02d" % [int(a["year"]), (int(a["year"]) + 1) % 100], a["comp"], a["award"], who, _club_name(str(a.get("club", "")))])
		if a.get("club", "") == season.user_club_id:
			for c in 5:
				it.set_custom_color(c, UiTheme.c("accent"))
