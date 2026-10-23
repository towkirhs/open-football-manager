extends VBoxContainer
## Tactics: your eleven on a pitch. Click a position to choose who plays there.
## Shows how well the eleven suits each style and how well the squad knows each one.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Tactics = preload("res://src/sim/tactics.gd")
const Lineup = preload("res://src/sim/lineup.gd")
const Balance = preload("res://src/sim/balance.gd")
const PitchView = preload("res://src/ui/pitch_view.gd")

static var slot: int = -1

var hub = null
var season = null
var _lineup = null
var _candidates: Array = []


func _ready() -> void:
	season = hub.season
	_lineup = season.user_lineup()
	if slot >= _lineup.slots.size():
		slot = -1
	var cols := W.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)

	var pitch = PitchView.new()
	pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pitch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pitch.custom_minimum_size = Vector2(420, 0)
	cols.add_child(pitch)
	pitch.set_lineup(_lineup, slot)
	pitch.slot_pressed.connect(func(i):
		slot = -1 if i == slot else i
		hub.open_tab.call_deferred("tactics"))

	var right := W.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.3
	cols.add_child(right)

	var t = season.user_tactics
	var forms: Array = Tactics.formation_names()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	right.add_child(grid)
	var fo := W.option(forms, forms.find(t.formation))
	var so := W.option(Tactics.STYLE_NAMES, t.style)
	var mo := W.option(Tactics.MENTALITY_NAMES, t.mentality)
	for o in [fo, so, mo]:
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(o)
	fo.item_selected.connect(func(i):
		season.set_user_formation(forms[i])
		slot = -1
		hub.app.save()
		hub.open_tab.call_deferred("tactics"))
	so.item_selected.connect(func(i):
		t.style = i
		hub.app.save()
		hub.open_tab.call_deferred("tactics"))
	mo.item_selected.connect(func(i):
		t.mentality = i
		hub.app.save())

	var auto_row := W.hbox(10)
	right.add_child(auto_row)
	var auto := CheckBox.new()
	auto.text = "Assistant picks the team every week"
	auto.button_pressed = season.user_auto_pick
	auto.toggled.connect(func(on):
		if on:
			season.user_auto_pick = true
		else:
			season.set_user_selection(season.user_lineup())
		hub.app.save()
		hub.open_tab.call_deferred("tactics"))
	auto_row.add_child(auto)
	auto_row.add_child(W.spacer())
	var best := W.button("Pick best XI")
	best.custom_minimum_size = Vector2(130, 36)
	best.pressed.connect(func():
		var l = Lineup.new()
		l.auto_pick(season.user_club().players, t.formation)
		season.set_user_selection(l)
		slot = -1
		hub.app.save()
		hub.open_tab.call_deferred("tactics"))
	auto_row.add_child(best)

	right.add_child(_style_card())

	if slot < 0:
		right.add_child(W.heading("Click a player on the pitch to change who plays there"))
		right.add_child(W.heading("Bench"))
		var names: Array = _lineup.bench.map(func(p): return "%s %s" % [p.position, p.name])
		right.add_child(W.wrap_label(", ".join(names), 14, "text"))
		return
	var role: String = _lineup.slots[slot]["role"]
	var current = _lineup.slots[slot]["player"]
	right.add_child(W.heading("Choose who plays %s  ·  double-click for details" % role))
	var tree := W.table(["Pos", "Name", role, "Ovr", "Fit", "Now"], [48, 0, 50, 50, 50, 70])
	right.add_child(tree)
	_candidates = []
	var where := {}
	for s in _lineup.slots:
		if s["player"] != null:
			where[s["player"].id] = "XI"
	for p in _lineup.bench:
		where[p.id] = "Bench"
	var pool: Array = season.user_club().players.duplicate()
	pool.sort_custom(func(a, b): return Lineup.role_score(a, role) > Lineup.role_score(b, role))
	for p in pool:
		var now: String = where.get(p.id, "")
		if p.injury_weeks > 0:
			now = "Injured"
		var it := W.row(tree, [p.position, p.name, Lineup.role_score(p, role), p.overall, roundi(p.fitness), now],
			"muted" if p.injury_weeks > 0 else "", "highlight" if p == current else "")
		it.set_metadata(0, _candidates.size())
		_candidates.append(p)
		if p.injury_weeks > 0:
			for c in 6:
				it.set_selectable(c, false)
		elif now == "XI":
			it.set_custom_color(5, UiTheme.c("accent"))
	tree.item_selected.connect(func(): _assign(_candidates[int(tree.get_selected().get_metadata(0))]))
	tree.item_activated.connect(func(): hub.open_profile(_candidates, int(tree.get_selected().get_metadata(0))))


func _style_card() -> Control:
	var card := W.panel()
	var v := W.vbox(6)
	card.add_child(v)
	v.add_child(W.heading("Styles: how well this eleven suits each one, and how well the squad knows it"))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	v.add_child(grid)
	var outfield: Array = []
	for s in _lineup.slots:
		if s["player"] != null and s["role"] != "GK":
			outfield.append(s["player"])
	for s in 5:
		var fit := _style_fit(outfield, s)
		var box := W.vbox(2)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(W.label(Tactics.STYLE_NAMES[s], 12, "accent" if s == season.user_tactics.style else "muted"))
		var word := "Good" if fit >= 1.04 else ("Poor" if fit <= 0.96 else "OK")
		var key := "good" if fit >= 1.04 else ("bad" if fit <= 0.96 else "text")
		box.add_child(W.label("Suits: %s %+d%%" % [word, roundi((fit - 1.0) * 100.0)], 14, key))
		var fam: float = float(season.familiarity.get(str(s), 0.65))
		box.add_child(W.label("Known: %d%%" % roundi(fam * 100.0), 13, "text"))
		grid.add_child(box)
	v.add_child(W.wrap_label("Familiarity grows every week you play a style (faster with a good assistant manager) and fades slowly for the others.", 12))
	return card


func _style_fit(players: Array, style: int) -> float:
	if players.is_empty():
		return 1.0
	var cfg: Dictionary = Balance.match_cfg()
	var w: Dictionary = Tactics.style_cfg(style)["fit"]
	var diff := 0.0
	for p in players:
		diff += p.weighted(w) - p.outfield_average()
	return clampf(1.0 + diff / players.size() / float(cfg["fit_scale"]), float(cfg["fit_min"]), float(cfg["fit_max"]))


func _assign(p) -> void:
	if slot < 0 or p.injury_weeks > 0:
		return
	var outgoing = _lineup.slots[slot]["player"]
	if outgoing == p:
		return
	var other: int = _lineup.slot_index_of(p.id)
	if other >= 0:
		_lineup.slots[other]["player"] = outgoing
	else:
		var b: int = _lineup.bench.find(p)
		if b >= 0:
			_lineup.bench.remove_at(b)
			if outgoing != null:
				_lineup.bench.insert(b, outgoing)
		elif outgoing != null:
			_lineup.bench.push_front(outgoing)
			if _lineup.bench.size() > Lineup.BENCH_SIZE:
				_lineup.bench.resize(Lineup.BENCH_SIZE)
	_lineup.slots[slot]["player"] = p
	season.set_user_selection(_lineup)
	hub.app.save()
	hub.open_tab.call_deferred("tactics")
