extends VBoxContainer
## Transfers: search every player in the world with filters, open a profile to bid or ask
## for a loan; answer bids for your own players; see your transfer-listed players.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const POSITIONS := ["Any", "GK", "CB", "FB", "DM", "CM", "AM", "WG", "ST"]
const VALUES := [["Any value", 0], ["Up to €100K", 100000], ["Up to €500K", 500000], ["Up to €1M", 1000000], ["Up to €5M", 5000000],
	["Up to €20M", 20000000], ["Up to €50M", 50000000]]

static var filters: Dictionary = {"position": 0, "min_ovr": 0, "max_ovr": 99, "min_age": 15, "max_age": 40, "value": 0,
	"league": 0, "name": "", "club": "", "nationality": "", "min_pot": 0, "listed": false, "free": false}

var hub = null
var season = null
var _results: Array = []
var _tree: Tree
var _count: Label
var _leagues: Array = []


func _ready() -> void:
	season = hub.season
	var cols := W.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)

	cols.add_child(_filter_panel())

	var mid := W.vbox(8)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_stretch_ratio = 2.2
	cols.add_child(mid)
	var head := W.hbox(10)
	mid.add_child(head)
	var status := "Transfer window open" if season.window_open() else "Transfer window closed (it opens in pre-season to week 6, and weeks 22-25)"
	head.add_child(W.label(status, 14, "good" if season.window_open() else "warn"))
	head.add_child(W.spacer())
	_count = W.label("", 13, "muted")
	head.add_child(_count)
	_tree = W.table(["Name", "Pos", "Age", "Ovr", "Pot", "Club", "Value", "Wage"], [0, 46, 44, 46, 60, 170, 76, 70])
	mid.add_child(_tree)
	_tree.item_selected.connect(func():
		var players: Array = _results.map(func(r): return r["player"])
		hub.open_profile(players, int(_tree.get_selected().get_metadata(0))))

	var right := W.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_offers_card())
	right.add_child(_listed_card())
	_search()


func _filter_panel() -> Control:
	var card := W.panel()
	card.custom_minimum_size = Vector2(250, 0)
	var sb: Array = W.scroll_box()
	card.add_child(sb[0])
	var v: VBoxContainer = sb[1]
	v.add_child(W.heading("Find players"))
	var name_edit := W.line_edit("Name")
	name_edit.text = filters["name"]
	v.add_child(name_edit)
	var club_edit := W.line_edit("Club")
	club_edit.text = filters["club"]
	v.add_child(club_edit)
	v.add_child(W.label("League", 12, "muted"))
	var league := OptionButton.new()
	league.add_item("Any league")
	_leagues = [""]
	for d in season.league_defs:
		league.add_item(d["name"])
		_leagues.append(d["id"])
	league.select(filters["league"])
	v.add_child(league)
	v.add_child(W.label("Position", 12, "muted"))
	var pos := W.option(POSITIONS, filters["position"])
	v.add_child(pos)
	v.add_child(W.label("Overall", 12, "muted"))
	var ovr := W.hbox(6)
	var min_o := W.spin(0, 99, filters["min_ovr"])
	var max_o := W.spin(0, 99, filters["max_ovr"])
	min_o.custom_minimum_size = Vector2(100, 0)
	max_o.custom_minimum_size = Vector2(100, 0)
	ovr.add_child(min_o)
	ovr.add_child(max_o)
	v.add_child(ovr)
	v.add_child(W.label("Age", 12, "muted"))
	var age := W.hbox(6)
	var min_a := W.spin(15, 45, filters["min_age"])
	var max_a := W.spin(15, 45, filters["max_age"])
	min_a.custom_minimum_size = Vector2(100, 0)
	max_a.custom_minimum_size = Vector2(100, 0)
	age.add_child(min_a)
	age.add_child(max_a)
	v.add_child(age)
	v.add_child(W.label("Minimum potential", 12, "muted"))
	var pot := W.spin(0, 99, filters["min_pot"])
	v.add_child(pot)
	v.add_child(W.label("Value", 12, "muted"))
	var value := W.option(VALUES.map(func(x): return x[0]), filters["value"])
	v.add_child(value)
	var nat := W.line_edit("Nationality code, e.g. ESP")
	nat.text = filters["nationality"]
	v.add_child(nat)
	var listed := CheckBox.new()
	listed.text = "Transfer-listed only"
	listed.button_pressed = filters["listed"]
	v.add_child(listed)
	var free := CheckBox.new()
	free.text = "Free agents only"
	free.button_pressed = filters["free"]
	v.add_child(free)
	var go := W.button("Search", true)
	v.add_child(go)
	var reset := W.button("Clear filters")
	v.add_child(reset)
	go.pressed.connect(func():
		filters = {"position": pos.selected, "min_ovr": int(min_o.value), "max_ovr": int(max_o.value), "min_age": int(min_a.value),
			"max_age": int(max_a.value), "value": value.selected, "league": league.selected, "name": name_edit.text,
			"club": club_edit.text, "nationality": nat.text, "min_pot": int(pot.value), "listed": listed.button_pressed, "free": free.button_pressed}
		_search())
	reset.pressed.connect(func():
		filters = {"position": 0, "min_ovr": 0, "max_ovr": 99, "min_age": 15, "max_age": 40, "value": 0,
			"league": 0, "name": "", "club": "", "nationality": "", "min_pot": 0, "listed": false, "free": false}
		hub.open_tab.call_deferred("transfers"))
	name_edit.text_submitted.connect(func(_t): go.pressed.emit())
	return card


func _search() -> void:
	var f := {
		"name": filters["name"], "club": filters["club"], "nationality": filters["nationality"],
		"position": "" if filters["position"] == 0 else POSITIONS[filters["position"]],
		"min_ovr": filters["min_ovr"], "max_ovr": filters["max_ovr"], "min_age": filters["min_age"], "max_age": filters["max_age"],
		"max_value": VALUES[filters["value"]][1], "min_pot": filters["min_pot"], "league": _leagues[filters["league"]],
		"listed_only": filters["listed"], "free_only": filters["free"], "exclude_club": season.user_club_id,
	}
	_results = season.search_players(f, 300)
	_tree.clear()
	_tree.create_item()
	var scouting: int = int(season.user_club().facilities.get("scouting", 1))
	for i in _results.size():
		var r: Dictionary = _results[i]
		var p = r["player"]
		var c = r["club"]
		var pot := str(p.potential)
		if scouting < 3:
			var spread: int = (4 - scouting) * 3
			var lo: int = maxi(p.overall, p.potential - absi(hash(p.id)) % (spread + 1))
			pot = "%d-%d" % [lo, mini(99, lo + spread)]
		var it := W.row(_tree, [p.name, p.position, p.age, p.overall, pot, c.name if c != null else "Free agent", W.money(p.value), W.money(p.wage)])
		it.set_metadata(0, i)
		if p.listed:
			it.set_custom_color(0, UiTheme.c("good"))
	_count.text = "%d player%s%s. Click one for details." % [_results.size(), "" if _results.size() == 1 else "s", " (first 300)" if _results.size() >= 300 else ""]


func _offers_card() -> Control:
	var card := W.panel()
	var v := W.vbox(8)
	card.add_child(v)
	v.add_child(W.heading("Bids for your players"))
	if season.offers.is_empty():
		v.add_child(W.wrap_label("No bids right now. Put players on the transfer list to attract offers.", 13))
	for o in season.offers:
		var p = season.player(o["player"])
		var buyer = season.club(o["club"])
		if p == null or buyer == null:
			continue
		v.add_child(W.wrap_label("%s bid %s for %s (value %s)." % [buyer.name, W.money(int(o["fee"])), p.name, W.money(p.value)], 14, "text"))
		var row := W.hbox(8)
		var yes := W.button("Accept")
		yes.pressed.connect(func():
			var msg: String = season.answer_offer(int(o["id"]), true)
			hub.app.save()
			hub.message("Transfer", msg)
			hub.refresh())
		row.add_child(yes)
		var no := W.button("Reject")
		no.pressed.connect(func():
			season.answer_offer(int(o["id"]), false)
			hub.app.save()
			hub.open_tab.call_deferred("transfers"))
		row.add_child(no)
		v.add_child(row)
	return card


func _listed_card() -> Control:
	var card := W.panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := W.vbox(6)
	card.add_child(v)
	v.add_child(W.heading("Your transfer list"))
	var listed: Array = season.user_club().players.filter(func(p): return p.listed)
	if listed.is_empty():
		v.add_child(W.wrap_label("Nobody listed. Open a player in the Squad tab to list him.", 13))
	for p in listed:
		v.add_child(W.label("%s %s  ·  %d  ·  %s" % [p.position, p.name, p.overall, W.money(p.value)], 14))
	v.add_child(W.heading("Cash"))
	v.add_child(W.label("%s to spend" % W.money(season.user_club().cash), 16, "accent"))
	return card
