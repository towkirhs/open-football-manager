extends Control
## Player profile, shown on top of the current screen.
## Big picture, ratings, attributes, best roles, season stats and contract.
## Previous / Next step through the list it was opened from.

signal closed

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Lineup = preload("res://src/sim/lineup.gd")

const ATTR_NAMES := {"pace": "Pace", "shooting": "Shooting", "passing": "Passing", "dribbling": "Dribbling",
	"defending": "Defending", "physical": "Physical", "goalkeeping": "Goalkeeping"}
const ROLES := ["GK", "CB", "FB", "WB", "DM", "CM", "AM", "WG", "ST"]
const POSITION_NAMES := {"GK": "Goalkeeper", "CB": "Centre-back", "FB": "Full-back", "DM": "Defensive midfielder",
	"CM": "Central midfielder", "AM": "Attacking midfielder", "WG": "Winger", "ST": "Striker"}

var season = null
var players: Array = []
var index: int = 0
## Optional: func(player, box, profile) that adds action buttons to the profile.
var actions: Callable

var _card: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = W.panel()
	_card.custom_minimum_size = Vector2(860, 0)
	center.add_child(_card)
	render()


func _on_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		close()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		close()
	elif ev.is_action_pressed("ui_left"):
		_step(-1)
	elif ev.is_action_pressed("ui_right"):
		_step(1)


func close() -> void:
	closed.emit()
	queue_free()


func _step(d: int) -> void:
	if players.is_empty():
		return
	index = (index + d + players.size()) % players.size()
	render()


func render() -> void:
	W.clear_children(_card)
	var p = players[index]
	var club = null
	if season != null:
		var cid: String = season.club_of(p.id)
		club = season.club(cid) if cid != "" else null
	var mine: bool = season != null and club != null and club.id == season.user_club_id
	var root := W.vbox(12)
	_card.add_child(root)

	var top := W.hbox(18)
	root.add_child(top)
	var pic = Portrait.new()
	pic.custom_minimum_size = Vector2(160, 190)
	pic.setup(p, club.colours if club != null else ["#1f7a4d", "#ffffff"], UiTheme.c("panel2"))
	top.add_child(pic)

	var info := W.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(W.label(p.name, 26))
	info.add_child(W.label("%s  ·  %d years  ·  %s  ·  %s" % [POSITION_NAMES.get(p.position, p.position), p.age, p.nationality,
		club.name if club != null else "Free agent"], 14, "muted"))
	var badges := W.hbox(10)
	info.add_child(badges)
	badges.add_child(_big_number("OVR", str(p.overall), "accent"))
	badges.add_child(_big_number("POT", _potential_text(p, mine), "text"))
	badges.add_child(_big_number("FIT", "%d%%" % roundi(p.fitness), "good" if p.fitness >= 85 else ("warn" if p.fitness >= 70 else "bad")))
	badges.add_child(_big_number("MORALE", str(roundi(p.morale)), "good" if p.morale >= 70 else ("warn" if p.morale >= 50 else "bad")))
	if p.injury_weeks > 0:
		info.add_child(W.label("Injured: out for %d more week%s" % [p.injury_weeks, "" if p.injury_weeks == 1 else "s"], 15, "bad"))
	var contract := "Contract until summer %d" % (p.contract_end + 1)
	if p.loan_from != "" and season != null:
		contract = "On loan from %s" % season.club(p.loan_from).name
	info.add_child(W.label("Value %s  ·  Wage %s a week  ·  %s%s" % [money(p.value), money(p.wage), contract, "  ·  Transfer-listed" if p.listed else ""], 14, "text"))

	var nav := W.vbox(8)
	nav.custom_minimum_size = Vector2(200, 0)
	top.add_child(nav)
	var close_btn := W.button("Close")
	close_btn.custom_minimum_size = Vector2(110, 36)
	close_btn.pressed.connect(close)
	nav.add_child(close_btn)
	if players.size() > 1:
		var prev := W.button("◀ Previous")
		prev.pressed.connect(func(): _step(-1))
		nav.add_child(prev)
		var next := W.button("Next ▶")
		next.pressed.connect(func(): _step(1))
		nav.add_child(next)
	if actions.is_valid():
		nav.add_child(HSeparator.new())
		actions.call(p, nav, self)

	var cols := W.hbox(24)
	root.add_child(cols)

	var attrs := W.vbox(6)
	attrs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(attrs)
	attrs.add_child(W.heading("Attributes"))
	var keys: Array = ["pace", "shooting", "passing", "dribbling", "defending", "physical"]
	if p.position == "GK":
		keys = ["goalkeeping", "physical", "passing", "pace", "defending", "dribbling"]
	for k in keys:
		attrs.add_child(_bar(ATTR_NAMES[k], int(p.attrs.get(k, 40))))

	var side := W.vbox(8)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(side)
	side.add_child(W.heading("Best roles"))
	var scores: Array = []
	for r in ROLES:
		if (r == "GK") != (p.position == "GK"):
			continue
		scores.append([r, Lineup.role_score(p, r)])
	scores.sort_custom(func(a, b): return a[1] > b[1])
	var role_row := W.hbox(8)
	side.add_child(role_row)
	for s in scores.slice(0, 4):
		role_row.add_child(_chip("%s %d" % [s[0], s[1]], s[0] == p.position))

	side.add_child(W.heading("This season"))
	var st: Dictionary = season.stats_for(p.id) if season != null else {"apps": 0, "goals": 0, "assists": 0, "rating_sum": 0.0, "yellows": 0, "reds": 0}
	var avg := "%.2f" % (st["rating_sum"] / st["apps"]) if st["apps"] > 0 else "-"
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	side.add_child(grid)
	for pair in [["Apps", st["apps"]], ["Goals", st["goals"]], ["Assists", st["assists"]],
			["Avg rating", avg], ["Yellows", st["yellows"]], ["Reds", st["reds"]]]:
		grid.add_child(_big_number(pair[0], str(pair[1]), "text"))
	if not p.career.is_empty():
		side.add_child(W.heading("Career"))
		var lines: Array = []
		for c in p.career.slice(maxi(0, p.career.size() - 4)):
			lines.append("%d/%02d %s: %d apps, %d goals, %.2f" % [int(c["year"]), (int(c["year"]) + 1) % 100, c["club"], int(c["apps"]), int(c["goals"]), float(c["avg"])])
		side.add_child(W.wrap_label("\n".join(lines), 13, "text"))


func _potential_text(p, mine: bool) -> String:
	if mine or season == null:
		return str(p.potential)
	var scouting: int = int(season.user_club().facilities.get("scouting", 1))
	if scouting >= 3:
		return str(p.potential)
	# Weak scouting only gives a range.
	var spread: int = (4 - scouting) * 3
	var seed_shift: int = absi(hash(p.id)) % (spread + 1)
	var lo: int = maxi(p.overall, p.potential - seed_shift)
	return "%d-%d" % [lo, mini(99, lo + spread)]


func _big_number(caption: String, value: String, color_key: String) -> Control:
	var box := W.panel("panel2")
	box.custom_minimum_size = Vector2(92, 0)
	var v := W.vbox(0)
	box.add_child(v)
	var cap := W.label(caption, 11, "muted")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var val := W.label(value, 22, color_key)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	return box


func _bar(caption: String, value: int) -> Control:
	var row := W.hbox(10)
	var l := W.label(caption, 14, "text")
	l.custom_minimum_size = Vector2(100, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 99
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiTheme.c("panel2")
	bg.set_corner_radius_all(7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.c("good") if value >= 75 else (UiTheme.c("accent") if value >= 60 else (UiTheme.c("warn") if value >= 45 else UiTheme.c("bad")))
	fill.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var n := W.label(str(value), 15, "text")
	n.custom_minimum_size = Vector2(30, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(n)
	return row


func _chip(text: String, main: bool) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.c("highlight") if main else UiTheme.c("panel2")
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(W.label(text, 14, "accent" if main else "text"))
	return p


static func money(v: int) -> String:
	if v >= 1000000:
		return "€%.1fM" % (v / 1000000.0)
	if v >= 1000:
		return "€%dK" % roundi(v / 1000.0)
	return "€%d" % v
