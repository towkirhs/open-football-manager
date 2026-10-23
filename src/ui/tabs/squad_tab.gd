extends VBoxContainer
## Squad: the first team and the youth academy. Click a player for his profile
## (training focus, contract, transfer list, release, promote).

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const POS_ORDER := ["GK", "CB", "FB", "DM", "CM", "AM", "WG", "ST"]
const TITLES := ["", "Pos", "Name", "Age", "Ovr", "Pot", "Fit", "Mor", "Status", "Wage", "Until", "Apps", "Gls", "Ast", "Avg"]
const KEYS := ["xi", "pos", "name", "age", "overall", "potential", "fitness", "morale", "injury", "wage", "contract_end", "apps", "goals", "assists", "avg"]

static var sort_col: int = 0
static var sort_desc: bool = true
static var academy: bool = false

var hub = null
var season = null
var _order: Array = []


func _ready() -> void:
	season = hub.season
	add_theme_constant_override("separation", 10)
	var club = season.user_club()
	var head := W.hbox(8)
	add_child(head)
	var group := ButtonGroup.new()
	for pair in [[false, "First team (%d)" % club.players.size()], [true, "Academy (%d)" % club.youth.size()]]:
		var b := Button.new()
		b.text = pair[1]
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "TabButton"
		b.button_pressed = academy == pair[0]
		var to: bool = pair[0]
		b.pressed.connect(func():
			academy = to
			hub.open_tab("squad"))
		head.add_child(b)
	head.add_child(W.spacer())
	var wages: int = club.wage_bill()
	head.add_child(W.label("Wage bill %s a week  ·  average %.1f" % [W.money(wages), club.average_overall()], 14, "muted"))

	var expiring: Array = club.players.filter(func(p): return p.contract_end <= season.year and p.loan_from == "")
	if not academy and not expiring.is_empty():
		add_child(W.wrap_label("%d contract%s end this summer (marked in the Until column). Offer new contracts from the player's profile." % [expiring.size(), "" if expiring.size() == 1 else "s"], 13, "warn"))
	if academy:
		add_child(W.wrap_label("Prospects grow with training. Promote the best ones when they are ready; the academy holds up to 10.", 13))

	var t := W.table(TITLES, [34, 46, 0, 44, 46, 50, 46, 46, 92, 72, 54, 50, 44, 44, 50])
	add_child(t)
	var lineup = season.user_lineup()
	var starters := {}
	for p in lineup.players_on_pitch():
		starters[p.id] = true
	var rows: Array = []
	for p in (club.youth if academy else club.players):
		var st: Dictionary = season.stats_for(p.id)
		var avg: float = st["rating_sum"] / st["apps"] if st["apps"] > 0 else 0.0
		rows.append({"p": p, "xi": starters.has(p.id), "pos": POS_ORDER.find(p.position), "avg": avg, "st": st})
	var key: String = KEYS[sort_col]
	rows.sort_custom(func(a, b):
		var va = _sort_value(a, key)
		var vb = _sort_value(b, key)
		if va == vb:
			if a["pos"] != b["pos"]:
				return a["pos"] < b["pos"]
			return a["p"].overall > b["p"].overall
		return (va > vb) if sort_desc else (va < vb))
	_order = []
	for r in rows:
		var p = r["p"]
		var st: Dictionary = r["st"]
		var status := "Fit"
		if p.injury_weeks > 0:
			status = "Injured %dw" % p.injury_weeks
		elif p.loan_from != "":
			status = "On loan"
		elif p.listed:
			status = "Listed"
		var vals := ["XI" if r["xi"] else "", p.position, p.name, p.age, p.overall, p.potential, roundi(p.fitness), roundi(p.morale), status,
			W.money(p.wage), str(p.contract_end + 1), st["apps"], st["goals"], st["assists"], ("%.1f" % r["avg"]) if st["apps"] > 0 else "-"]
		var it := W.row(t, vals)
		it.set_metadata(0, _order.size())
		_order.append(p)
		if r["xi"]:
			it.set_custom_color(0, UiTheme.c("accent"))
		if p.injury_weeks > 0:
			it.set_custom_color(8, UiTheme.c("bad"))
		if p.fitness < 75:
			it.set_custom_color(6, UiTheme.c("warn"))
		if p.contract_end <= season.year and p.loan_from == "":
			it.set_custom_color(10, UiTheme.c("warn"))
	t.column_title_clicked.connect(func(col, _btn):
		if col == sort_col:
			sort_desc = not sort_desc
		else:
			sort_col = col
			sort_desc = col in [0, 4, 5, 6, 7, 9, 11, 12, 13, 14]
		hub.open_tab.call_deferred("squad"))
	t.item_selected.connect(func(): hub.open_profile(_order, int(t.get_selected().get_metadata(0))))


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
