extends VBoxContainer
## Home: what happens next (today's match, or continue to it), the season summary and
## job offers when they matter, recent results, the league table and the inbox.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Tactics = preload("res://src/sim/tactics.gd")

var hub = null
var season = null


func _ready() -> void:
	season = hub.season
	add_theme_constant_override("separation", 12)
	var cols := W.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)

	var left := W.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	cols.add_child(left)
	if season.sacked:
		left.add_child(_sacked_card())
	elif season.season_over:
		left.add_child(_season_over_card())
	elif not season.today_user_fixture().is_empty():
		left.add_child(_match_card())
	else:
		left.add_child(_continue_card())
	if not season.sponsor_offers.is_empty() and not season.season_over:
		left.add_child(_sponsor_card())
	left.add_child(_recent_card())

	var right := W.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_mini_table())
	right.add_child(_news_card())


# ---------------------------------------------------------------- what's next

func _match_card() -> Control:
	var card := W.panel()
	var v := W.vbox(10)
	card.add_child(v)
	var uf: Dictionary = season.today_user_fixture()
	var f: Dictionary = uf["fixture"]
	var k = season.comp(uf["comp"])
	var home: bool = f["home"] == season.user_club_id
	var opp_id: String = f["away"] if home else f["home"]
	var opp = season.club(opp_id)
	v.add_child(W.heading("Today  ·  %s  ·  %s" % [k.name, k.round_name(uf["round"])]))
	if f.has("first_leg"):
		var fl: Array = f["first_leg"]
		v.add_child(W.label("First leg: %s %d-%d %s" % [opp.name if home else season.user_club().name, fl[0], fl[1], season.user_club().name if home else opp.name], 13, "muted"))
	var row := W.hbox(14)
	v.add_child(row)
	row.add_child(W.shield(opp, 40))
	var info := W.vbox(2)
	var where: String = "neutral ground" if f.get("neutral", false) else ("at home" if home else "away")
	info.add_child(W.label("%s  %s" % ["vs" if home or f.get("neutral", false) else "at", opp.name], 20))
	var line := "Squad %.0f  ·  %s  ·  You play %s" % [opp.average_overall(), season.country_name(opp.country), where]
	var ol = season.comp(opp.league)
	if ol != null and ol.table.has(opp_id) and ol.table[opp_id][0] > 0:
		line = "%s in the %s  ·  " % [W.ordinal(ol.position_of(opp_id)), ol.name] + line
	info.add_child(W.label(line, 13, "muted"))
	row.add_child(info)

	var usual: int = season.usual_style(opp_id)
	var mgr = season.managers.get(opp_id)
	var scout := ("Manager %s. " % mgr.name) if mgr != null else ""
	scout += ("Lately they play %s." % Tactics.STYLE_NAMES[usual]) if usual >= 0 else "Their recent style is unknown."
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
	var hint := W.wrap_label(_tactic_hint(t.style, usual), 13, "muted")
	v.add_child(hint)
	fo.item_selected.connect(func(i):
		season.set_user_formation(forms[i])
		hub.app.save())
	so.item_selected.connect(func(i):
		t.style = i
		hint.text = _tactic_hint(i, usual)
		hub.app.save())
	mo.item_selected.connect(func(i):
		t.mentality = i
		hub.app.save())

	var buttons := W.hbox(10)
	v.add_child(buttons)
	var play := W.button("Play match", true)
	play.pressed.connect(hub.app.play_match)
	buttons.add_child(play)
	var sim := W.button("Quick sim")
	sim.custom_minimum_size = Vector2(130, 42)
	sim.pressed.connect(hub.app.quick_sim)
	buttons.add_child(sim)
	return card


func _tactic_hint(style: int, their_usual: int) -> String:
	var fam: float = float(season.familiarity.get(str(style), 0.65))
	var text := "%s: your squad knows it %d%%." % [Tactics.STYLE_NAMES[style], roundi(fam * 100.0)]
	if their_usual >= 0:
		match Tactics.matchup(style, their_usual):
			1: text += "  Good pick against their usual style."
			-1: text += "  Risky: their usual style beats this one."
	return text


func _continue_card() -> Control:
	var card := W.panel()
	var v := W.vbox(10)
	card.add_child(v)
	var d: Dictionary = season.today()
	v.add_child(W.heading("Next up"))
	var nxt: Dictionary = season.next_user_fixture()
	if nxt.is_empty():
		v.add_child(W.label("No more matches for you this season.", 18))
	else:
		var f: Dictionary = nxt["fixture"]
		var k = season.comp(nxt["comp"])
		var opp_id: String = f["away"] if f["home"] == season.user_club_id else f["home"]
		v.add_child(W.label("%s vs %s" % [k.name, season.club(opp_id).name], 18))
		v.add_child(W.label("%s  ·  %s" % [season.calendar[nxt["day"]]["label"], k.round_name(nxt["round"])], 13, "muted"))
	if d.get("kind", "") == "preseason":
		v.add_child(W.wrap_label("Pre-season: sign players, pick a sponsor and set your tactics before the first match.", 14, "text"))
	var b := W.button("Continue", true)
	b.pressed.connect(hub.app.advance)
	v.add_child(b)
	return card


func _sponsor_card() -> Control:
	var card := W.panel()
	var v := W.vbox(8)
	card.add_child(v)
	v.add_child(W.heading("Choose a sponsor for this season"))
	for i in season.sponsor_offers.size():
		var o: Dictionary = season.sponsor_offers[i]
		var row := W.hbox(10)
		var text := "%s (%s): %s a week" % [o["name"], o["kind"], W.money(int(o["weekly"]))]
		if int(o["bonus_target"]) > 0:
			text += ", plus %s if you finish in the top %d" % [W.money(int(o["bonus"])), int(o["bonus_target"])]
		var l := W.wrap_label(text, 14, "text")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var pick := W.button("Sign")
		pick.custom_minimum_size = Vector2(90, 34)
		pick.pressed.connect(func():
			season.choose_sponsor(i)
			hub.app.save()
			hub.refresh())
		row.add_child(pick)
		v.add_child(row)
	return card


func _season_over_card() -> Control:
	var card := W.panel()
	var v := W.vbox(10)
	card.add_child(v)
	var s: Dictionary = season.season_summary
	v.add_child(W.heading("Season %d/%02d is over" % [season.year, (season.year + 1) % 100]))
	var l = season.user_league()
	if l != null:
		var pos: int = l.position_of(season.user_club_id)
		var fate := ""
		if s.get("promoted", []).has(season.user_club_id):
			fate = "  Promoted!"
		elif s.get("relegated", []).has(season.user_club_id):
			fate = "  Relegated."
		v.add_child(W.label("You finished %s in the %s.%s" % [W.ordinal(pos), l.name, fate], 20))
	var trophies: Array = s.get("trophies", [])
	if not trophies.is_empty():
		v.add_child(W.label("Trophies: %s" % ", ".join(trophies), 16, "accent"))
	v.add_child(W.label("The owner rates the season %d/100%s." % [roundi(float(s.get("owner_score", 0.0)) * 100.0),
		(" and adds %s to the budget" % W.money(int(s.get("grant", 0)))) if int(s.get("grant", 0)) > 0 else ""], 15, "text"))
	var mine_awards: Array = s.get("awards", []).filter(func(a): return a.get("club", "") == season.user_club_id)
	for a in mine_awards:
		var who: String = a.get("manager", "") if a["award"] == "Manager of the Season" else season.player(a["player"]).name if season.player(a["player"]) != null else "?"
		v.add_child(W.label("%s: %s" % [a["award"], who], 14, "good"))
	v.add_child(W.wrap_label("Next season players get a year older, youngsters join your academy, and contracts that end now are over. Promotion and relegation take effect.", 13))
	if not season.job_offers.is_empty():
		v.add_child(W.heading("Job offers"))
		for o in season.job_offers:
			v.add_child(_job_row(o))
	var b := W.button("Start next season", true)
	b.pressed.connect(hub.app.next_season)
	v.add_child(b)
	return card


func _sacked_card() -> Control:
	var card := W.panel()
	var v := W.vbox(10)
	card.add_child(v)
	v.add_child(W.label("You have been sacked.", 22, "bad"))
	v.add_child(W.wrap_label("The owner of %s has let you go. Pick one of the clubs that want you to carry on your career." % season.user_club().name, 15, "text"))
	for o in season.job_offers:
		v.add_child(_job_row(o))
	return card


func _job_row(o: Dictionary) -> Control:
	var c = season.club(o["club"])
	var row := W.hbox(10)
	row.add_child(W.shield(c, 30))
	var l = season.comp(c.league)
	var info := W.label("%s  ·  %s  ·  squad %.0f. %s" % [c.name, l.name if l != null else "", c.average_overall(), o["reason"]], 14, "text")
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(info)
	var b := W.button("Take the job")
	b.custom_minimum_size = Vector2(120, 34)
	b.pressed.connect(func(): hub.app.accept_job(c.id))
	row.add_child(b)
	return row


# ---------------------------------------------------------------- side cards

func _recent_card() -> Control:
	var card := W.panel()
	var v := W.vbox(6)
	card.add_child(v)
	v.add_child(W.heading("Recent results"))
	var shown := 0
	for i in range(season.user_results.size() - 1, -1, -1):
		var r: Dictionary = season.user_results[i]
		var home: bool = r["home"] == season.user_club_id
		var gf: int = r["hg"] if home else r["ag"]
		var ga: int = r["ag"] if home else r["hg"]
		var mark := "D"
		var key := "warn"
		if gf > ga or (r.get("pens", false) and r["winner"] == season.user_club_id):
			mark = "W"
			key = "good"
		elif gf < ga or (r.get("pens", false) and r["winner"] != season.user_club_id):
			mark = "L"
			key = "bad"
		var row := W.hbox(10)
		var badge := W.label(mark, 15, key)
		badge.custom_minimum_size = Vector2(18, 0)
		row.add_child(badge)
		var kind: String = season.comp(r["comp"]).kind
		var tag := W.label({"league": "League", "cup": "Cup", "europe": "Europe"}.get(kind, ""), 12, "muted")
		tag.custom_minimum_size = Vector2(56, 0)
		row.add_child(tag)
		row.add_child(W.label("%s %d-%d %s%s" % [season.club(r["home"]).name, r["hg"], r["ag"], season.club(r["away"]).name, " (pens)" if r.get("pens", false) else ""], 14))
		v.add_child(row)
		shown += 1
		if shown >= 5:
			break
	if shown == 0:
		v.add_child(W.label("No games played yet.", 14, "muted"))
	return card


func _mini_table() -> Control:
	var card := W.panel()
	var v := W.vbox(6)
	card.add_child(v)
	var l = season.user_league()
	if l == null:
		return card
	v.add_child(W.heading(l.name))
	var t := W.table(["#", "Club", "P", "GD", "Pts"], [46, 0, 40, 48, 48])
	t.size_flags_vertical = Control.SIZE_FILL
	t.scroll_vertical_enabled = false
	v.add_child(t)
	var order: Array = l.standings()
	var me: int = order.find(season.user_club_id)
	var rows := 0
	for i in order.size():
		if not (i < 4 or absi(i - me) <= 1):
			continue
		var row: Array = l.table[order[i]]
		var gd: int = row[4] - row[5]
		var key := ""
		if i >= order.size() - l.relegate and l.relegate > 0:
			key = "bad"
		var it := W.row(t, [i + 1, season.club(order[i]).name, row[0], ("+%d" % gd) if gd > 0 else str(gd), row[6]], key, "highlight" if order[i] == season.user_club_id else "")
		if order[i] == season.user_club_id:
			for c in 5:
				it.set_custom_color(c, UiTheme.c("accent"))
		rows += 1
	t.custom_minimum_size = Vector2(0, 40 + rows * 34)
	return card


func _news_card() -> Control:
	var card := W.panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := W.vbox(6)
	card.add_child(v)
	v.add_child(W.heading("Inbox"))
	var sb: Array = W.scroll_box()
	v.add_child(sb[0])
	for n in season.news.slice(0, 25):
		var row := W.hbox(8)
		var when := W.label(str(n.get("label", "")), 12, "muted")
		when.custom_minimum_size = Vector2(70, 0)
		row.add_child(when)
		var l := W.wrap_label(n["text"], 14, "text")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		sb[1].add_child(row)
	return card
