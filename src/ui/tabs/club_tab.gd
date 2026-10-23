extends VBoxContainer
## Club: finances, the owner, the bank, facilities and staff.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Economy = preload("res://src/sim/economy.gd")
const Club = preload("res://src/sim/club.gd")

const SECTIONS := [["money", "Finances"], ["owner", "Owner"], ["bank", "Bank"], ["facilities", "Facilities"], ["staff", "Staff"]]
const LEDGER := [["gate", "Match-day tickets"], ["tv", "TV money"], ["sponsor", "Sponsor"], ["prize", "Prize money"], ["owner", "Owner's bonus"],
	["transfers", "Transfers"], ["bank", "Bank (loans taken / repaid early)"], ["wages", "Wages"], ["facilities", "Facilities"], ["staff", "Staff changes"], ["loans", "Loan repayments"]]
const FACILITY_NAMES := {"stadium": "Stadium", "training": "Training ground", "youth": "Youth academy", "medical": "Medical centre", "scouting": "Scouting network"}
const STAFF_NAMES := {"head_coach": "Head coach (training)", "assistant": "Assistant (tactic familiarity)", "fitness": "Fitness coach (recovery)",
	"goalkeeping": "Goalkeeping coach", "youth": "Youth coach (academy)", "scout": "Chief scout", "physio": "Physio (injuries)"}

static var section: String = "money"

var hub = null
var season = null
var club = null


func _ready() -> void:
	season = hub.season
	club = season.user_club()
	var bar := W.hbox(4)
	add_child(bar)
	var group := ButtonGroup.new()
	for s in SECTIONS:
		var b := Button.new()
		b.text = s[1]
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "TabButton"
		b.button_pressed = section == s[0]
		var key: String = s[0]
		b.pressed.connect(func():
			section = key
			hub.open_tab.call_deferred("club"))
		bar.add_child(b)
	var sb: Array = W.scroll_box()
	add_child(sb[0])
	var body: VBoxContainer = sb[1]
	match section:
		"owner": _owner(body)
		"bank": _bank(body)
		"facilities": _facilities(body)
		"staff": _staff(body)
		_: _money(body)


# ---------------------------------------------------------------- finances

func _money(body: VBoxContainer) -> void:
	var stats := W.hbox(10)
	body.add_child(stats)
	stats.add_child(W.stat("Cash", W.money(club.cash), "text" if club.cash >= 0 else "bad", 140))
	stats.add_child(W.stat("Wages a week", W.money(club.wage_bill()), "text", 140))
	stats.add_child(W.stat("Squad value", W.money(club.squad_value()), "text", 140))
	stats.add_child(W.stat("Stadium", "%d seats" % club.stadium, "text", 140))
	stats.add_child(W.stat("Fans", str(club.fans), "text", 120))

	var cols := W.hbox(12)
	body.add_child(cols)
	var left := W.panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lv := W.vbox(6)
	left.add_child(lv)
	lv.add_child(W.heading("This season so far"))
	var t := W.table(["", "Amount"], [0, 120])
	t.custom_minimum_size = Vector2(0, 420)
	t.scroll_vertical_enabled = false
	lv.add_child(t)
	var total := 0
	for row in LEDGER:
		var amount: int = int(club.ledger.get(row[0], 0))
		total += amount
		if amount != 0:
			W.row(t, [row[1], W.money(amount)], "good" if amount > 0 else "bad")
	W.row(t, ["Total", W.money(total)], "accent")

	var right := W.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := W.vbox(8)
	right.add_child(rv)
	rv.add_child(W.heading("Ticket price"))
	var tier: int = season.tier_of(club)
	var fair: int = Economy.fair_price(tier)
	var price_label := W.label("", 16)
	rv.add_child(price_label)
	var slider := HSlider.new()
	slider.min_value = maxi(1, fair / 3)
	slider.max_value = fair * 3
	slider.step = 1
	slider.value = club.ticket_price
	slider.custom_minimum_size = Vector2(0, 24)
	rv.add_child(slider)
	var expect := W.wrap_label("", 13)
	rv.add_child(expect)
	var update := func(v: float):
		club.ticket_price = int(v)
		var crowd := Economy.attendance(club, tier, 0.5, "league")
		price_label.text = "€%d a ticket (fair price in this division: €%d)" % [club.ticket_price, fair]
		expect.text = "Expected crowd about %d of %d, about %s per home game. Higher prices mean smaller crowds." % [crowd, club.stadium, W.money(crowd * club.ticket_price)]
	update.call(slider.value)
	slider.value_changed.connect(func(v):
		update.call(v))
	slider.drag_ended.connect(func(_c): hub.app.save())

	rv.add_child(HSeparator.new())
	rv.add_child(W.heading("Sponsor"))
	if not club.sponsor.is_empty():
		var s: Dictionary = club.sponsor
		var text := "%s pays %s a week." % [s["name"], W.money(int(s["weekly"]))]
		if int(s.get("bonus_target", 0)) > 0:
			text += " Bonus of %s for a top-%d finish." % [W.money(int(s["bonus"])), int(s["bonus_target"])]
		rv.add_child(W.wrap_label(text, 14, "text"))
	elif not season.sponsor_offers.is_empty():
		rv.add_child(W.wrap_label("Choose a sponsor on the Home tab.", 14, "warn"))
	rv.add_child(HSeparator.new())
	rv.add_child(W.heading("Income outlook"))
	rv.add_child(W.wrap_label("TV money for your division: %s a season. Weekly wages: %s. Facility upkeep is paid every week." % [W.money(Economy.tv_money(tier)), W.money(club.wage_bill())], 13))


# ---------------------------------------------------------------- owner

func _owner(body: VBoxContainer) -> void:
	var stats := W.hbox(10)
	body.add_child(stats)
	var conf: int = roundi(club.confidence)
	stats.add_child(W.stat("Owner confidence", "%d/100" % conf, "good" if conf >= 60 else ("warn" if conf >= 30 else "bad"), 170))
	stats.add_child(W.stat("Targets met so far", "%d/100" % roundi(season.owner_score() * 100.0), "text", 170))
	stats.add_child(W.stat("Your reputation", "%d/100" % roundi(season.manager_rep), "accent", 160))
	stats.add_child(W.stat("Trophies", str(club.trophies.size()), "text", 110))

	var card := W.panel()
	body.add_child(card)
	var v := W.vbox(8)
	card.add_child(v)
	v.add_child(W.heading("The owner's targets this season"))
	for g in season.owner_progress():
		var row := W.hbox(10)
		var mark := W.label("✓" if float(g["score"]) >= 1.0 else ("~" if float(g["score"]) > 0.0 else "✗"), 16, "good" if float(g["score"]) >= 1.0 else ("warn" if float(g["score"]) > 0.0 else "bad"))
		mark.custom_minimum_size = Vector2(20, 0)
		row.add_child(mark)
		var l := W.label(g["text"], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(W.label(g["status"], 13, "muted"))
		v.add_child(row)
	v.add_child(W.wrap_label("Meeting targets raises confidence and earns a bonus at the end of the season. If confidence falls too low, you are sacked. Overspending is allowed, but ending the season in debt counts against you.", 13))

	var h := W.panel()
	body.add_child(h)
	var hv := W.vbox(6)
	h.add_child(hv)
	hv.add_child(W.heading("Your career"))
	if season.history.is_empty():
		hv.add_child(W.label("Your first season.", 14, "muted"))
	else:
		var t := W.table(["Season", "Club", "League", "Pos", "Pts", "Trophies", "Rating"], [80, 0, 0, 50, 50, 0, 70])
		t.custom_minimum_size = Vector2(0, 40 + season.history.size() * 34)
		t.scroll_vertical_enabled = false
		hv.add_child(t)
		for r in season.history:
			W.row(t, ["%d/%02d" % [int(r["year"]), (int(r["year"]) + 1) % 100], r["club"], r["league"], int(r["position"]), int(r["points"]),
				", ".join(r.get("trophies", [])), "%d" % roundi(float(r.get("score", 0.0)) * 100.0)])
	if not club.trophies.is_empty():
		hv.add_child(W.heading("Club trophies"))
		hv.add_child(W.wrap_label(", ".join(club.trophies.map(func(t): return "%s %d" % [t["name"], int(t["year"])])), 14, "text"))


# ---------------------------------------------------------------- bank

func _bank(body: VBoxContainer) -> void:
	var income: int = season.yearly_income(club)
	var rating := Economy.credit_rating(club, income)
	var limit := Economy.loan_limit(club)
	var stats := W.hbox(10)
	body.add_child(stats)
	stats.add_child(W.stat("Credit rating", rating, "good" if rating in ["A", "B"] else ("warn" if rating == "C" else "bad"), 140))
	stats.add_child(W.stat("Interest", "%d%% a year" % roundi(Economy.interest_rate(rating) * 100.0), "text", 150))
	stats.add_child(W.stat("You can borrow", W.money(limit), "accent", 160))
	stats.add_child(W.stat("Debt", W.money(club.debt()), "text", 140))
	body.add_child(W.wrap_label("The bank lends up to 40% of what the club owns (stadium, facilities, half the squad's value, cash), minus existing debt. Missed repayments and big debts lower your rating.", 13))

	var cols := W.hbox(12)
	body.add_child(cols)
	var loan := W.panel()
	loan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(loan)
	var lv := W.vbox(8)
	loan.add_child(lv)
	lv.add_child(W.heading("Take a loan"))
	var amount := W.spin(0, maxi(0, limit), mini(limit, 1000000), 50000, "€ ")
	lv.add_child(amount)
	var years := W.option(["Over 1 season", "Over 2 seasons", "Over 3 seasons", "Over 4 seasons", "Over 5 seasons"], 2)
	lv.add_child(years)
	var pay := W.label("", 13, "muted")
	lv.add_child(pay)
	var show_pay := func():
		pay.text = "Weekly repayment: %s" % W.money(Economy.repayment(int(amount.value), Economy.interest_rate(rating), (years.selected + 1) * 52))
	show_pay.call()
	amount.value_changed.connect(func(_v): show_pay.call())
	years.item_selected.connect(func(_i): show_pay.call())
	var take := W.button("Borrow", true)
	take.disabled = limit <= 0
	take.pressed.connect(func():
		if Economy.take_loan(club, int(amount.value), years.selected + 1, rating):
			hub.app.save()
			hub.refresh())
	lv.add_child(take)

	var adv := W.panel()
	adv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(adv)
	var av := W.vbox(8)
	adv.add_child(av)
	av.add_child(W.heading("Advance on TV money"))
	var weeks_left: int = maxi(0, 46 - season.league_week())
	var alimit := Economy.advance_limit(club, season.tier_of(club), weeks_left, 46)
	av.add_child(W.wrap_label("Get up to half of the TV money still to come this season now, for a %d%% fee. It is paid back weekly until the season ends." % roundi(float(Economy.cfg()["advance_fee"]) * 100.0), 13))
	var a_amount := W.spin(0, maxi(0, alimit), alimit, 10000, "€ ")
	av.add_child(a_amount)
	var take_adv := W.button("Take the advance", true)
	take_adv.disabled = alimit <= 0 or weeks_left <= 0
	take_adv.pressed.connect(func():
		if Economy.take_advance(club, int(a_amount.value), weeks_left):
			hub.app.save()
			hub.refresh())
	av.add_child(take_adv)

	var cur := W.panel()
	body.add_child(cur)
	var cv := W.vbox(6)
	cur.add_child(cv)
	cv.add_child(W.heading("Your loans"))
	if club.loans.is_empty():
		cv.add_child(W.label("No loans.", 14, "muted"))
	for i in club.loans.size():
		var l: Dictionary = club.loans[i]
		var row := W.hbox(10)
		var text := "%s of %s: %s a week, %d weeks left" % ["Advance" if l["kind"] == "advance" else "Loan", W.money(int(l["principal"])), W.money(int(l["weekly"])), int(l["weeks_left"])]
		var lab := W.label(text, 14)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var rp := W.button("Repay now")
		rp.custom_minimum_size = Vector2(120, 34)
		var idx: int = i
		rp.pressed.connect(func():
			if Economy.repay_early(club, idx):
				hub.app.save()
				hub.refresh()
			else:
				hub.message("Bank", "You don't have enough cash to repay this loan now."))
		row.add_child(rp)
		cv.add_child(row)


# ---------------------------------------------------------------- facilities

func _facilities(body: VBoxContainer) -> void:
	body.add_child(W.wrap_label("Upgrades are paid at once and take effect immediately. Each level also costs more upkeep every week.", 13))
	for k in Club.FACILITIES:
		var card := W.panel()
		body.add_child(card)
		var row := W.hbox(14)
		card.add_child(row)
		var lvl: int = int(club.facilities[k])
		var info := W.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(W.label("%s  %s" % [FACILITY_NAMES[k], "★".repeat(lvl) + "☆".repeat(5 - lvl)], 17))
		info.add_child(W.label("Now: %s" % Economy.facility_effect(k, lvl), 13, "muted"))
		if lvl < 5:
			info.add_child(W.label("Next level: %s" % Economy.facility_effect(k, lvl + 1), 13, "text"))
		row.add_child(info)
		var cost := Economy.upgrade_cost(club, k)
		var b := W.button("Maxed" if cost < 0 else "Upgrade for %s" % W.money(cost), cost >= 0)
		b.custom_minimum_size = Vector2(200, 42)
		b.disabled = cost < 0 or club.cash < cost
		var key: String = k
		b.pressed.connect(func():
			if Economy.upgrade(club, key):
				season.add_news("%s upgraded to level %d." % [FACILITY_NAMES[key], int(club.facilities[key])])
				hub.app.save()
				hub.refresh())
		row.add_child(b)


# ---------------------------------------------------------------- staff

func _staff(body: VBoxContainer) -> void:
	body.add_child(W.wrap_label("Better staff cost more. Replacing someone pays off ten weeks of the old contract.", 13))
	for role in STAFF_NAMES:
		var s: Dictionary = club.staff.get(role, {"name": "Vacant", "skill": 0, "wage": 0, "end": season.year})
		var card := W.panel()
		body.add_child(card)
		var row := W.hbox(14)
		card.add_child(row)
		var info := W.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(W.label("%s: %s" % [STAFF_NAMES[role], s["name"]], 16))
		info.add_child(W.label("Skill %d  ·  %s a week" % [int(s["skill"]), W.money(int(s["wage"]))], 13, "muted"))
		row.add_child(info)
		var b := W.button("Find a replacement")
		b.custom_minimum_size = Vector2(190, 38)
		var r: String = role
		b.pressed.connect(func(): _candidates(r))
		row.add_child(b)


func _candidates(role: String) -> void:
	var m := W.modal(hub, "Candidates: %s" % STAFF_NAMES[role], 560)
	for s in season.staff_candidates(role, hub.app.rng):
		var row := W.hbox(10)
		var l := W.label("%s  ·  skill %d  ·  %s a week" % [s["name"], int(s["skill"]), W.money(int(s["wage"]))], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var hire := W.button("Hire")
		hire.custom_minimum_size = Vector2(90, 34)
		var cand: Dictionary = s
		hire.pressed.connect(func():
			season.hire_staff(role, cand)
			hub.app.save()
			m["root"].queue_free()
			hub.open_tab.call_deferred("club"))
		row.add_child(hire)
		m["body"].add_child(row)
