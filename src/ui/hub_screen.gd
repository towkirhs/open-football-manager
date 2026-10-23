extends Control
## The club hub: everything between matches, in tabs. Each tab is its own script in
## src/ui/tabs/. The hub also owns the player profile pop-up and the transfer and
## contract dialogs, so every tab can use them.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PlayerProfile = preload("res://src/ui/player_profile.gd")

const TABS := [
	["home", "Home", "res://src/ui/tabs/home_tab.gd"],
	["squad", "Squad", "res://src/ui/tabs/squad_tab.gd"],
	["tactics", "Tactics", "res://src/ui/tabs/tactics_tab.gd"],
	["transfers", "Transfers", "res://src/ui/tabs/transfers_tab.gd"],
	["club", "Club", "res://src/ui/tabs/club_tab.gd"],
	["comps", "Competitions", "res://src/ui/tabs/comps_tab.gd"],
	["fixtures", "Fixtures", "res://src/ui/tabs/fixtures_tab.gd"],
	["settings", "Settings", "res://src/ui/tabs/settings_tab.gd"],
]
const FOCUS_KEYS := ["balanced", "attacking", "defending", "physical", "technical", "goalkeeping"]
const FOCUS_NAMES := ["Balanced", "Attacking", "Defending", "Physical", "Technical", "Goalkeeping"]

var app = null
var season = null
var _content: Control
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	season = app.season
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := W.vbox(10)
	margin.add_child(root)
	root.add_child(_top_bar())
	root.add_child(_tab_bar())
	_content = W.vbox(10)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content)
	open_tab(app.hub_tab)


func _top_bar() -> Control:
	var bar := W.hbox(14)
	var club = season.user_club()
	bar.add_child(W.shield(club, 46))
	var names := W.vbox(0)
	names.add_child(W.label(club.name, 22))
	var l = season.user_league()
	var sub := "%s  ·  Season %d/%02d  ·  %s" % [l.name if l != null else "", season.year, (season.year + 1) % 100,
		season.today().get("label", "Season over")]
	if season.window_open():
		sub += "  ·  Transfer window open"
	names.add_child(W.label(sub, 13, "muted"))
	bar.add_child(names)
	bar.add_child(W.spacer())
	var cash := W.vbox(0)
	var cash_l := W.label(W.money(club.cash), 22, "text" if club.cash >= 0 else "bad")
	cash_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash.add_child(cash_l)
	var cap := W.label("in the bank", 13, "muted")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash.add_child(cap)
	bar.add_child(cash)
	if l != null:
		var t: Array = l.table[club.id]
		var stat := W.vbox(0)
		var pos_label := W.label(W.ordinal(l.position_of(club.id)) if t[0] > 0 else "–", 24, "accent")
		pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat.add_child(pos_label)
		var pts := W.label("%d pts from %d games" % [t[6], t[0]], 13, "muted")
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat.add_child(pts)
		bar.add_child(stat)
	return bar


func _tab_bar() -> Control:
	var bar := W.hbox(4)
	var group := ButtonGroup.new()
	for tab in TABS:
		var b := Button.new()
		b.text = tab[1]
		if tab[0] == "transfers" and not season.offers.is_empty():
			b.text += " (%d)" % season.offers.size()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "TabButton"
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func(): open_tab(tab[0]))
		_tab_buttons[tab[0]] = b
		bar.add_child(b)
	return bar


func open_tab(tab: String) -> void:
	var path := ""
	for t in TABS:
		if t[0] == tab:
			path = t[2]
	if path == "":
		tab = "home"
		path = TABS[0][2]
	app.hub_tab = tab
	_tab_buttons[tab].button_pressed = true
	W.clear_children(_content)
	var view = load(path).new()
	view.hub = self
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(view)


## Rebuild the whole hub (after something changed).
func refresh() -> void:
	app.show_hub.call_deferred(app.hub_tab)


# ---------------------------------------------------------------- player profile

func open_profile(players: Array, index: int) -> void:
	var prof = PlayerProfile.new()
	prof.season = season
	prof.players = players
	prof.index = index
	prof.actions = profile_actions
	add_child(prof)


## Buttons on a player's profile: contract and squad actions for your own players,
## bids and loans for everyone else.
func profile_actions(p, box: Control, prof) -> void:
	var uc = season.user_club()
	if uc.youth.has(p):
		var promote := W.button("Promote to first team", true)
		promote.pressed.connect(func():
			season.promote_youth(p)
			app.save()
			prof.close()
			refresh())
		box.add_child(promote)
		var rel := W.button("Release from academy")
		rel.pressed.connect(func():
			season.release_youth(p)
			app.save()
			prof.close()
			refresh())
		box.add_child(rel)
		box.add_child(_training_picker(p))
		return
	var cid: String = season.club_of(p.id)
	if cid == season.user_club_id:
		box.add_child(_training_picker(p))
		if p.loan_from == "":
			var renew := W.button("Offer new contract")
			renew.pressed.connect(func(): renew_dialog(p))
			box.add_child(renew)
			var lst := W.button("Remove from transfer list" if p.listed else "Put on transfer list")
			lst.pressed.connect(func():
				season.toggle_listed(p)
				app.save()
				prof.render())
			box.add_child(lst)
			var rel2 := W.button("Release")
			rel2.add_theme_color_override("font_color", UiTheme.c("bad"))
			rel2.pressed.connect(func(): confirm("Release %s? You pay half of what is left on his contract." % p.name, func():
				season.release_player(p)
				app.save()
				prof.close()
				refresh()))
			box.add_child(rel2)
		else:
			box.add_child(W.wrap_label("On loan from %s until the end of the season." % season.club(p.loan_from).name, 12))
		return
	var b := W.button("Make a bid" if cid != "" else "Offer a contract", true)
	b.disabled = not season.window_open()
	b.pressed.connect(func(): bid_dialog(p))
	box.add_child(b)
	if cid != "":
		var loan := W.button("Ask for a loan")
		loan.disabled = not season.window_open()
		loan.pressed.connect(func(): loan_dialog(p))
		box.add_child(loan)
	if not season.window_open():
		box.add_child(W.wrap_label("The transfer window is closed.", 12))


func _training_picker(p) -> Control:
	var v := W.vbox(4)
	v.add_child(W.label("Training focus", 12, "muted"))
	var o := W.option(FOCUS_NAMES, maxi(0, FOCUS_KEYS.find(p.training)))
	o.item_selected.connect(func(i):
		p.training = FOCUS_KEYS[i]
		app.save())
	v.add_child(o)
	return v


# ---------------------------------------------------------------- dialogs

func message(title: String, text: String) -> void:
	var m := W.modal(self, title, 460)
	m["body"].add_child(W.wrap_label(text, 15, "text"))


func confirm(text: String, on_yes: Callable) -> void:
	var m := W.modal(self, "Are you sure?", 460)
	m["body"].add_child(W.wrap_label(text, 15, "text"))
	var yes := W.button("Yes", true)
	yes.pressed.connect(func():
		m["root"].queue_free()
		on_yes.call())
	m["body"].add_child(yes)


func bid_dialog(p) -> void:
	var seller = season.club(season.club_of(p.id))
	var m := W.modal(self, ("Bid for %s" % p.name) if seller != null else ("Sign %s" % p.name), 520)
	var body: VBoxContainer = m["body"]
	if seller == null:
		body.add_child(W.wrap_label("%s is a free agent: no fee, just agree a contract." % p.name, 14, "text"))
		var go := W.button("Discuss terms", true)
		go.pressed.connect(func():
			m["root"].queue_free()
			terms_dialog(p, 0))
		body.add_child(go)
		return
	body.add_child(W.wrap_label("%s plays for %s. Market value %s. You have %s." % [p.name, seller.name, W.money(p.value), W.money(season.user_club().cash)], 14, "text"))
	var fee := W.spin(0, 500000000, float(p.value), 50000, "€ ")
	body.add_child(fee)
	var answer := W.wrap_label("", 14, "accent")
	body.add_child(answer)
	var row := W.hbox(10)
	body.add_child(row)
	var send := W.button("Send bid", true)
	row.add_child(send)
	var terms_btn := W.button("Discuss personal terms")
	terms_btn.visible = false
	row.add_child(terms_btn)
	var agreed := [0]
	send.pressed.connect(func():
		var r: Dictionary = season.bid(p, int(fee.value))
		answer.text = r["text"]
		if r["answer"] == "accept":
			agreed[0] = int(fee.value)
			terms_btn.visible = true
			send.disabled = true
		elif r["answer"] == "counter":
			fee.value = r["fee"])
	terms_btn.pressed.connect(func():
		m["root"].queue_free()
		terms_dialog(p, agreed[0]))


func terms_dialog(p, fee: int) -> void:
	var m := W.modal(self, "Contract for %s" % p.name, 520)
	var body: VBoxContainer = m["body"]
	body.add_child(W.wrap_label("He earns %s a week now. Offer a weekly wage and a contract length." % W.money(p.wage), 14, "text"))
	var wage := W.spin(0, 5000000, float(maxi(p.wage, 1000)), 100, "€ ", " a week")
	body.add_child(wage)
	var years := W.option(["1 year", "2 years", "3 years", "4 years", "5 years"], 2)
	body.add_child(years)
	var answer := W.wrap_label("", 14, "accent")
	body.add_child(answer)
	var send := W.button("Offer contract", true)
	body.add_child(send)
	send.pressed.connect(func():
		var r: Dictionary = season.offer_contract(p, fee, int(wage.value), years.selected + 1)
		answer.text = r["text"]
		if r["answer"] == "counter":
			wage.value = r["wage"]
		elif r["answer"] == "accept":
			send.disabled = true
			app.save()
			m["close"].pressed.connect(refresh))


func loan_dialog(p) -> void:
	var m := W.modal(self, "Loan %s" % p.name, 480)
	var body: VBoxContainer = m["body"]
	body.add_child(W.wrap_label("He would join until the end of the season. How much of his %s weekly wage will you pay?" % W.money(p.wage), 14, "text"))
	var share := W.option(["25%", "50%", "75%", "100%"], 1)
	body.add_child(share)
	var answer := W.wrap_label("", 14, "accent")
	body.add_child(answer)
	var send := W.button("Ask for the loan", true)
	body.add_child(send)
	send.pressed.connect(func():
		var r: Dictionary = season.loan_in(p, [0.25, 0.5, 0.75, 1.0][share.selected])
		answer.text = r["text"]
		if r["answer"] == "accept":
			send.disabled = true
			app.save()
			m["close"].pressed.connect(refresh))


func renew_dialog(p) -> void:
	var m := W.modal(self, "New contract for %s" % p.name, 520)
	var body: VBoxContainer = m["body"]
	body.add_child(W.wrap_label("His contract runs until summer %d. He earns %s a week." % [p.contract_end + 1, W.money(p.wage)], 14, "text"))
	var wage := W.spin(0, 5000000, float(p.wage), 100, "€ ", " a week")
	body.add_child(wage)
	var years := W.option(["1 more year", "2 more years", "3 more years", "4 more years", "5 more years"], 2)
	body.add_child(years)
	var answer := W.wrap_label("", 14, "accent")
	body.add_child(answer)
	var send := W.button("Offer", true)
	body.add_child(send)
	send.pressed.connect(func():
		var r: Dictionary = season.renew(p, int(wage.value), years.selected + 1)
		answer.text = r["text"]
		if r["answer"] == "counter":
			wage.value = r["wage"]
		elif r["answer"] == "accept":
			send.disabled = true
			app.save())
