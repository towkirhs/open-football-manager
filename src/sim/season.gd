extends RefCounted
## A career. Holds the world (countries, leagues, clubs, free agents) and the current
## season: every league, cup and European competition on one calendar.
##
## The calendar is a list of days. A day is a league week, a European night or a cup
## round. play_day() plays everything on the current day; when the human manager's club
## plays that day, the UI can first run that match live and pass the finished engine in.
##
## At the end of the last day the season closes (honours, awards, owner review,
## contracts); next_season() then applies promotion and relegation, ages everyone,
## brings in youth players and builds the new season.

const Club = preload("res://src/sim/club.gd")
const Player = preload("res://src/sim/player.gd")
const Tactics = preload("res://src/sim/tactics.gd")
const Lineup = preload("res://src/sim/lineup.gd")
const MatchEngine = preload("res://src/sim/match_engine.gd")
const AiManager = preload("res://src/sim/ai_manager.gd")
const CompLeague = preload("res://src/sim/comp_league.gd")
const CompCup = preload("res://src/sim/comp_cup.gd")
const CompEurope = preload("res://src/sim/comp_europe.gd")
const QuickSim = preload("res://src/sim/quick_sim.gd")
const Economy = preload("res://src/sim/economy.gd")
const Development = preload("res://src/sim/development.gd")
const Transfers = preload("res://src/sim/transfers.gd")
const WorldGen = preload("res://src/sim/world_gen.gd")
const Balance = preload("res://src/sim/balance.gd")

const SAVE_VERSION := 2
const SAVE_PATH := "user://career.json"
const LEAGUE_WEEKS := 46
## League week after which each European round is played.
const EURO_AFTER := {2: 0, 5: 1, 8: 2, 11: 3, 14: 4, 17: 5, 24: 6, 26: 7, 30: 8, 32: 9, 36: 10, 38: 11, 44: 12}
## League weeks after which cup rounds are played (a cup with k rounds uses the last k).
const CUP_SLOTS := [3, 7, 10, 13, 19, 27, 34, 41]
const SUMMER_WINDOW_END := 5
const WINTER_WINDOW := [21, 24]
const STYLE_MEMORY := 6
const MAX_FREE_AGENTS := 500
const MAX_ACADEMY := 10

# ---- world
var world_name: String = ""
var fictional: bool = true
var countries: Array = []
var league_defs: Array = []
var europe_defs: Array = []
var clubs: Array = []
var free_agents: Array = []
var managers: Dictionary = {}

# ---- the human manager
var user_club_id: String = ""
var manager_name: String = "You"
var manager_rep: float = 35.0
var user_tactics = null
var user_auto_pick: bool = true
var user_selection: Dictionary = {}
## Style familiarity for the human's squad: "0".."4" -> 0.5..1.0
var familiarity: Dictionary = {}
var owner_goals: Array = []
var sponsor_offers: Array = []
## Incoming bids for the human's players: {"id", "club", "player", "fee", "wage", "expires"}
var offers: Array = []
## Clubs offering the human a job: {"club", "reason"}
var job_offers: Array = []
var sacked: bool = false

# ---- the season
var year: int = 2026
var comps: Dictionary = {}
var calendar: Array = []
var day: int = 0
var season_over: bool = false
## comp_id -> {player_id: [apps, goals, assists, rating_sum, yellows, reds]}
var stats: Dictionary = {}
var style_history: Dictionary = {}
var user_results: Array = []
var news: Array = []
## Standings of each league at the end of last season (for European places).
var last_standings: Dictionary = {}
var last_cup_winners: Dictionary = {}
## Moves to apply before next season: {club_id: new_league_id}
var pending_moves: Dictionary = {}
var season_summary: Dictionary = {}
var history: Array = []
var honours: Array = []
var awards: Array = []
var next_offer_id: int = 1
## Average player rating of each league (and each foreign country) when the career began.
## New players (youth, unattached) are generated towards it, which keeps the world from
## drifting: rich leagues cannot pull away for ever and poor ones do not sink.
var level_anchor: Dictionary = {}

var _club_by_id: Dictionary = {}
var _player_by_id: Dictionary = {}
var _player_club: Dictionary = {}
var _xi_cache: Dictionary = {}


# ================================================================ setup

func new_game(world: Dictionary, user_id: String, rng: RandomNumberGenerator, name: String = "You") -> void:
	world_name = str(world.get("name", "World"))
	fictional = bool(world.get("fictional", true))
	countries = world.get("countries", [])
	league_defs = world.get("leagues", [])
	europe_defs = world.get("europe", [])
	clubs = world["clubs"]
	year = int(world.get("start_year", 2026))
	free_agents = []
	user_club_id = user_id
	manager_name = name
	_index()
	_compute_anchors()
	manager_rep = clampf(user_club().reputation - 15.0, 10.0, 60.0)
	managers = {}
	for c in clubs:
		if c.id != user_id:
			managers[c.id] = _new_manager(rng)
	user_tactics = Tactics.new()
	user_tactics.formation = "4-4-2"
	user_tactics.style = Tactics.Style.POSSESSION
	familiarity = {}
	for s in 5:
		familiarity[str(s)] = 0.8 if s == Tactics.Style.POSSESSION else 0.65
	history = []
	honours = []
	awards = []
	news = []
	_build_season(rng, true)
	var greet := "Welcome to %s." % user_club().name if manager_name == "You" else "Welcome to %s, %s." % [user_club().name, manager_name]
	add_news(greet + " Pick a sponsor on the Home tab, and see the owner's targets in the Club tab.")


func _anchor_key(c) -> String:
	return "L:" + c.league if c.league != "" else "F:" + c.country


func _compute_anchors() -> void:
	var sums := {}
	for c in clubs:
		var k := _anchor_key(c)
		if not sums.has(k):
			sums[k] = [0.0, 0]
		sums[k][0] += c.average_overall()
		sums[k][1] += 1
	level_anchor = {}
	for k in sums:
		level_anchor[k] = snappedf(sums[k][0] / sums[k][1], 0.1)


## The level new players for this club are generated at: between the club's own level
## and its league's starting level.
func generation_level(c) -> float:
	var own: float = c.average_overall()
	return lerpf(own, float(level_anchor.get(_anchor_key(c), own)), 0.6)


func _new_manager(rng: RandomNumberGenerator):
	var m = AiManager.new()
	m.setup_random(rng)
	return m


func _index() -> void:
	_club_by_id = {}
	_player_by_id = {}
	_player_club = {}
	for c in clubs:
		_club_by_id[c.id] = c
		for p in c.players:
			_player_by_id[p.id] = p
			_player_club[p.id] = c.id
		for p in c.youth:
			_player_by_id[p.id] = p
			_player_club[p.id] = c.id
	for p in free_agents:
		_player_by_id[p.id] = p
		_player_club[p.id] = ""
	_xi_cache = {}


func _build_season(rng: RandomNumberGenerator, first: bool) -> void:
	comps = {}
	stats = {}
	style_history = {}
	user_results = []
	offers = []
	day = 0
	season_over = false
	season_summary = {}
	# Leagues
	for def in league_defs:
		var ids: Array = clubs.filter(func(c): return c.league == def["id"]).map(func(c): return c.id)
		if ids.size() < 2:
			continue
		var l = CompLeague.new()
		l.setup(def, ids, rng)
		comps[l.id] = l
	# Domestic cups: every club in a playable country, strongest divisions first.
	for country in countries:
		if not country.get("playable", false):
			continue
		var cup_clubs: Array = clubs.filter(func(c): return c.country == country["id"] and c.league != "")
		cup_clubs.sort_custom(func(a, b): return _tier(a) < _tier(b) or (_tier(a) == _tier(b) and a.reputation > b.reputation))
		if cup_clubs.size() < 4:
			continue
		var cup = CompCup.new()
		cup.setup({"id": "CUP_" + country["id"], "name": country.get("cup", country["name"] + " Cup"), "country": country["id"]}, cup_clubs.map(func(c): return c.id), rng)
		comps[cup.id] = cup
	# European cups
	var entrants := _euro_entrants(first, rng)
	var country_of := {}
	for c in clubs:
		country_of[c.id] = c.country
	for def in europe_defs:
		var ids: Array = entrants.get(def["id"], [])
		if ids.size() < 32:
			continue
		ids.sort_custom(func(a, b): return club(a).reputation > club(b).reputation)
		var e = CompEurope.new()
		e.setup(def, ids, rng, country_of)
		comps[e.id] = e
		for cid in ids:
			club(cid).book("prize", int(Economy.cfg()["europe_entry"].get(def["id"], 0)))
	_build_calendar()
	# Club preparations
	for c in clubs:
		c.ledger = {}
		c.missed_payments = 0
		for p in c.players:
			p.fitness = 100.0
		if c.id != user_club_id:
			var offers_ai: Array = Economy.sponsor_offers(c, _tier(c), rng)
			c.sponsor = offers_ai[1]
	var uc = user_club()
	sponsor_offers = Economy.sponsor_offers(uc, _tier(uc), rng)
	uc.sponsor = {}
	_set_owner_goals()
	_xi_cache = {}
	if uc.players.size() < 18:
		add_news("Your squad has only %d players. Sign more before the season starts (Transfers tab), or promote youngsters from the academy." % uc.players.size())


func _build_calendar() -> void:
	calendar = []
	calendar.append({"label": "Pre-season", "kind": "preseason", "week": -1, "items": [], "window": true})
	var week_items: Array = []
	for _w in LEAGUE_WEEKS:
		week_items.append([])
	for id in comps:
		var comp = comps[id]
		if comp.kind != "league":
			continue
		var n: int = comp.round_count()
		for r in n:
			week_items[int(floor(float(r) * LEAGUE_WEEKS / n))].append([id, r])
	for wk in LEAGUE_WEEKS:
		var window: bool = wk <= SUMMER_WINDOW_END or (wk >= WINTER_WINDOW[0] and wk <= WINTER_WINDOW[1])
		calendar.append({"label": "Week %d" % (wk + 1), "kind": "league", "week": wk, "items": week_items[wk], "window": window})
		if EURO_AFTER.has(wk):
			var items: Array = []
			for id in comps:
				if comps[id].kind == "europe":
					items.append([id, EURO_AFTER[wk]])
			if not items.is_empty():
				calendar.append({"label": "European night", "kind": "europe", "week": wk, "items": items, "window": window})
		var cup_items: Array = []
		for id in comps:
			var comp = comps[id]
			if comp.kind != "cup":
				continue
			var n: int = comp.round_count()
			var slots: Array = CUP_SLOTS.slice(maxi(0, CUP_SLOTS.size() - n))
			var r: int = slots.find(wk)
			if r >= 0 and r < n:
				cup_items.append([id, r])
		if not cup_items.is_empty():
			calendar.append({"label": "Cup round", "kind": "cup", "week": wk, "items": cup_items, "window": window})


## Who plays in Europe: the top of each playable country's first division (last
## season's table, or reputation in the first season), then foreign clubs by strength.
func _euro_entrants(first: bool, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"EC1": [], "EC2": [], "EC3": []}
	var taken := {}
	for def in league_defs:
		if int(def.get("tier", 1)) != 1:
			continue
		var order: Array = []
		if not first and last_standings.has(def["id"]):
			order = last_standings[def["id"]].filter(func(id): return _club_by_id.has(id) and club(id).league == def["id"])
		else:
			order = clubs.filter(func(c): return c.league == def["id"]).map(func(c): return c.id)
			order.sort_custom(func(a, b): return club(a).reputation > club(b).reputation)
		for i in order.size():
			var cup := ""
			if i < 4:
				cup = "EC1"
			elif i < 6:
				cup = "EC2"
			elif i < 7:
				cup = "EC3"
			if cup != "":
				out[cup].append(order[i])
				taken[order[i]] = true
	var pool: Array = []
	for c in clubs:
		if c.league == "" and not taken.has(c.id):
			pool.append([c.id, c.reputation + rng.randfn(0.0, 3.0)])
	# Not enough foreign clubs (small custom worlds): fill from playable top divisions.
	if pool.size() < 96 - taken.size():
		for c in clubs:
			if not taken.has(c.id) and c.league != "" and _tier(c) == 1:
				pool.append([c.id, c.reputation - 5.0 + rng.randfn(0.0, 3.0)])
	pool.sort_custom(func(a, b): return a[1] > b[1])
	var i := 0
	for cup in ["EC1", "EC2", "EC3"]:
		while out[cup].size() < 32 and i < pool.size():
			out[cup].append(pool[i][0])
			i += 1
	return out


# ================================================================ queries

func club(id: String):
	return _club_by_id.get(id)


func user_club():
	return _club_by_id.get(user_club_id)


func player(id: String):
	return _player_by_id.get(id)


## Club id of a player ("" for free agents).
func club_of(pid: String) -> String:
	return _player_club.get(pid, "")


func comp(id: String):
	return comps.get(id)


func league_def(id: String) -> Dictionary:
	for d in league_defs:
		if d["id"] == id:
			return d
	return {}


func _tier(c) -> int:
	if c.league == "":
		return 1
	return int(league_def(c.league).get("tier", 1))


func tier_of(c) -> int:
	return _tier(c)


func user_league():
	return comps.get(user_club().league)


func country_name(id: String) -> String:
	for c in countries:
		if c["id"] == id:
			return c["name"]
	return id


## Competitions the club is in this season (league first).
func comps_for(club_id: String) -> Array:
	var out: Array = []
	var c = club(club_id)
	if comps.has(c.league):
		out.append(comps[c.league])
	for id in comps:
		var k = comps[id]
		if k.kind != "league" and k.involves(club_id):
			out.append(k)
	return out


func is_finished() -> bool:
	return day >= calendar.size()


func today() -> Dictionary:
	if is_finished():
		return {}
	return calendar[day]


func window_open() -> bool:
	return not is_finished() and bool(calendar[day].get("window", false))


## The human's fixture on a given day: {"comp", "round", "fixture"} or {}.
func user_fixture_on(d: int) -> Dictionary:
	if d >= calendar.size():
		return {}
	for item in calendar[d]["items"]:
		var k = comps[item[0]]
		for f in k.fixtures(item[1]):
			if f["home"] == user_club_id or f["away"] == user_club_id:
				return {"comp": item[0], "round": item[1], "fixture": f, "day": d}
	return {}


func today_user_fixture() -> Dictionary:
	return user_fixture_on(day)


## The next day with a known fixture for the human's club (cup draws not yet made are skipped).
func next_user_fixture() -> Dictionary:
	for d in range(day, calendar.size()):
		var f := user_fixture_on(d)
		if not f.is_empty():
			return f
	return {}


func league_week() -> int:
	if is_finished():
		return LEAGUE_WEEKS
	return maxi(0, int(calendar[day]["week"]))


## Sum of a player's stats across this season's competitions.
func stats_for(pid: String) -> Dictionary:
	var t := [0, 0, 0, 0.0, 0, 0]
	for cid in stats:
		var s: Array = stats[cid].get(pid, [])
		if s.is_empty():
			continue
		for i in 6:
			t[i] += s[i]
	return {"apps": t[0], "goals": t[1], "assists": t[2], "rating_sum": t[3], "yellows": t[4], "reds": t[5]}


func top_scorers(comp_id: String, n: int = 10) -> Array:
	var rows: Array = []
	var cs: Dictionary = stats.get(comp_id, {})
	for pid in cs:
		var s: Array = cs[pid]
		if s[1] > 0:
			rows.append({"id": pid, "goals": s[1], "assists": s[2], "apps": s[0]})
	rows.sort_custom(func(a, b): return a["goals"] > b["goals"] or (a["goals"] == b["goals"] and a["assists"] > b["assists"]))
	return rows.slice(0, n)


## Live award race for a league: {"best", "young", "scorer"} each an Array of {"id", "value"}.
func award_race(comp_id: String, n: int = 5) -> Dictionary:
	var k = comps.get(comp_id)
	var rounds_played: int = k.results.size() if k != null and k.kind == "league" else 0
	var min_apps: int = maxi(1, int(rounds_played * 0.5))
	var best: Array = []
	var young: Array = []
	var cs: Dictionary = stats.get(comp_id, {})
	for pid in cs:
		var s: Array = cs[pid]
		if s[0] < min_apps:
			continue
		var avg: float = s[3] / s[0]
		best.append({"id": pid, "value": avg})
		var p = player(pid)
		if p != null and p.age <= 21:
			young.append({"id": pid, "value": avg})
	best.sort_custom(func(a, b): return a["value"] > b["value"])
	young.sort_custom(func(a, b): return a["value"] > b["value"])
	var scorers: Array = top_scorers(comp_id, n).map(func(r): return {"id": r["id"], "value": r["goals"]})
	return {"best": best.slice(0, n), "young": young.slice(0, n), "scorer": scorers}


func add_news(text: String) -> void:
	news.push_front({"year": year, "label": today().get("label", "Summer") if not is_finished() else "Season end", "text": text})
	if news.size() > 60:
		news.resize(60)


func yearly_income(c) -> int:
	return Economy.estimate_income(c, _tier(c), 21)


# ================================================================ lineups and tactics

## Best available eleven for a club, cached for a few days.
func best_xi(cid: String):
	var cached: Dictionary = _xi_cache.get(cid, {})
	if not cached.is_empty() and day - int(cached["day"]) < 4:
		var ok := true
		for slot in cached["lineup"].slots:
			if slot["player"] != null and slot["player"].injury_weeks > 0:
				ok = false
		if ok:
			return cached["lineup"]
	var l = Lineup.new()
	var c = club(cid)
	var formation := "4-4-2"
	if managers.has(cid):
		formation = managers[cid].preferred_formation
	l.auto_pick(c.players, formation)
	var total := 0.0
	for slot in l.slots:
		if slot["player"] != null:
			total += Lineup.role_score(slot["player"], slot["role"]) * (0.85 + 0.15 * slot["player"].fitness / 100.0)
	_xi_cache[cid] = {"day": day, "lineup": l, "strength": total / maxf(1.0, l.slots.size())}
	return l


func xi_strength(cid: String) -> float:
	best_xi(cid)
	return float(_xi_cache[cid]["strength"])


func is_key_player(c, p) -> bool:
	var l = best_xi(c.id)
	return l.slot_index_of(p.id) >= 0


func user_lineup():
	var l = Lineup.new()
	var players: Array = user_club().players
	var f: String = user_tactics.formation
	if user_auto_pick or user_selection.is_empty():
		l.auto_pick(players, f)
	elif str(user_selection.get("formation", "")) != f:
		l.from_ids(players, user_selection["formation"], user_selection["slots"], user_selection["bench"])
		l.reshape(f)
	else:
		l.from_ids(players, f, user_selection["slots"], user_selection["bench"])
	return l


func set_user_selection(lineup) -> void:
	user_selection = {"formation": lineup.formation, "slots": lineup.slot_ids(), "bench": lineup.bench_ids()}
	user_auto_pick = false


func set_user_formation(formation: String) -> void:
	if not user_auto_pick and not user_selection.is_empty():
		var l = user_lineup()
		l.reshape(formation)
		user_tactics.formation = formation
		set_user_selection(l)
	else:
		user_tactics.formation = formation


func lineup_for(club_id: String, tactics):
	if club_id == user_club_id:
		var l = user_lineup()
		if l.formation != tactics.formation:
			l.reshape(tactics.formation)
		return l
	var a = Lineup.new()
	a.auto_pick(club(club_id).players, tactics.formation)
	return a


func usual_style(id: String) -> int:
	var hist: Array = style_history.get(id, [])
	if hist.is_empty():
		return -1
	var counts := {}
	var best := -1
	var best_n := 0
	for s in hist:
		counts[s] = counts.get(s, 0) + 1
		if counts[s] > best_n or (counts[s] == best_n and s == hist[hist.size() - 1]):
			best_n = counts[s]
			best = s
	return best


func tactics_for(club_id: String, opponent_id: String, rng: RandomNumberGenerator):
	if club_id == user_club_id:
		var t = user_tactics.copy()
		t.familiarity = float(familiarity.get(str(t.style), 0.65))
		return t
	if not managers.has(club_id):
		managers[club_id] = _new_manager(rng)
	return managers[club_id].pick_tactics(usual_style(opponent_id), rng)


func make_engine(home_id: String, away_id: String, rng: RandomNumberGenerator):
	var ht = tactics_for(home_id, away_id, rng)
	var at = tactics_for(away_id, home_id, rng)
	var e = MatchEngine.new()
	e.setup(club(home_id).name, lineup_for(home_id, ht), ht, club(away_id).name, lineup_for(away_id, at), at, rng)
	if managers.has(home_id):
		e.set_ai(0, managers[home_id])
	if managers.has(away_id):
		e.set_ai(1, managers[away_id])
	return e


## Engine for the human's match today, ready to step() live. Null if no match today.
func prepare_user_match(rng: RandomNumberGenerator):
	var f := today_user_fixture()
	if f.is_empty():
		return null
	return make_engine(f["fixture"]["home"], f["fixture"]["away"], rng)


# ================================================================ playing a day

## Plays everything on today's calendar day. Pass the finished live engine for the
## human's match, or null to simulate it. Returns the day's results.
func play_day(rng: RandomNumberGenerator, user_engine = null) -> Array:
	if is_finished():
		return []
	var d: Dictionary = calendar[day]
	var out: Array = []
	for item in d["items"]:
		var k = comps[item[0]]
		var r: int = item[1]
		var res: Array = []
		for f in k.fixtures(r):
			res.append(_play_fixture(k, r, f, rng, user_engine))
		k.record(r, res, rng)
		_after_round(k, r, res)
		out.append_array(res)
	_after_day(d, rng)
	day += 1
	if is_finished():
		_close_season(rng)
	return out


## Plays days until the human's next match (or the end of the season).
func advance_to_next_match(rng: RandomNumberGenerator) -> void:
	while not is_finished() and today_user_fixture().is_empty():
		play_day(rng)
		if sacked:
			return


func _play_fixture(k, r: int, f: Dictionary, rng: RandomNumberGenerator, user_engine) -> Dictionary:
	var h: String = f["home"]
	var a: String = f["away"]
	var mine: bool = h == user_club_id or a == user_club_id
	var res: Dictionary
	var styles := [-1, -1]
	if mine or (k.kind == "league" and k.id == user_club().league):
		var e = user_engine if (mine and user_engine != null) else make_engine(h, a, rng)
		if not e.finished:
			e.simulate()
		res = e.result()
		styles = [e.home.tactics.style, e.away.tactics.style]
	else:
		var hx = best_xi(h)
		var ax = best_xi(a)
		res = QuickSim.play(hx.slots, ax.slots, xi_strength(h), xi_strength(a), rng, f.get("neutral", false))
	var hg: int = res["home_goals"]
	var ag: int = res["away_goals"]
	var winner: String = k.decide(f, hg, ag)
	var pens := false
	if f.get("decisive", false) and winner == "":
		winner = h if rng.randf() < 0.5 + (xi_strength(h) - xi_strength(a)) * 0.01 else a
		pens = true
	_apply_result(k, h, a, res, styles, f)
	var summary := {"comp": k.id, "round": r, "home": h, "away": a, "hg": hg, "ag": ag, "winner": winner, "pens": pens}
	if mine:
		var s2: Dictionary = summary.duplicate()
		s2["day"] = day
		s2["label"] = k.round_name(r)
		user_results.append(s2)
		var my_goals: int = hg if h == user_club_id else ag
		var their_goals: int = ag if h == user_club_id else hg
		var word := "Draw"
		if my_goals > their_goals or (pens and winner == user_club_id):
			word = "Win"
		elif my_goals < their_goals or (pens and winner != user_club_id):
			word = "Defeat"
		add_news("%s (%s): %s %d-%d %s%s." % [word, k.name, club(h).name, hg, ag, club(a).name, " (penalties)" if pens else ""])
	return summary


func _apply_result(k, h: String, a: String, res: Dictionary, styles: Array, f: Dictionary) -> void:
	var cs: Dictionary = stats.get(k.id, {})
	for pid in res["ratings"]:
		var s: Array = cs.get(pid, [0, 0, 0, 0.0, 0, 0])
		s[0] += 1
		s[3] += float(res["ratings"][pid])
		cs[pid] = s
	for ev in res["events"]:
		var pid: String = ev.get("player", "")
		if pid == "":
			continue
		var idx := -1
		match ev["type"]:
			"goal": idx = 1
			"yellow": idx = 4
			"red": idx = 5
		if idx >= 0:
			var s: Array = cs.get(pid, [0, 0, 0, 0.0, 0, 0])
			s[idx] += 1
			cs[pid] = s
		if ev["type"] == "goal" and str(ev.get("assist", "")) != "":
			var s2: Array = cs.get(ev["assist"], [0, 0, 0, 0.0, 0, 0])
			s2[2] += 1
			cs[ev["assist"]] = s2
	stats[k.id] = cs
	for inj in res["injuries"]:
		var p = player(inj["id"])
		if p == null:
			continue
		var c = club(club_of(p.id))
		var medical: int = int(c.facilities.get("medical", 1)) if c != null else 1
		var physio: int = c.staff_skill("physio") if c != null else 50
		var weeks: int = maxi(1, roundi(int(inj["weeks"]) * (1.15 - 0.075 * medical) * (1.1 - physio / 250.0)))
		p.injury_weeks = maxi(p.injury_weeks, weeks + 1)
		if c != null and c.id == user_club_id:
			add_news("%s is injured, out for about %d week%s." % [p.name, weeks, "" if weeks == 1 else "s"])
	if not res["condition"].is_empty():
		for pid in res["condition"]:
			if res["ratings"].has(pid):
				var p = player(pid)
				if p != null:
					p.fitness = float(res["condition"][pid])
	else:
		for pid in res["ratings"]:
			var p = player(pid)
			if p != null:
				p.fitness = maxf(55.0, p.fitness - 12.0)
	if styles[0] >= 0:
		for pair in [[h, styles[0]], [a, styles[1]]]:
			var hist: Array = style_history.get(pair[0], [])
			hist.append(pair[1])
			if hist.size() > STYLE_MEMORY:
				hist.pop_front()
			style_history[pair[0]] = hist
	var hg: int = res["home_goals"]
	var ag: int = res["away_goals"]
	var hm := 0.0
	if hg > ag:
		hm = 3.0
	elif hg < ag:
		hm = -3.0
	for pair in [[h, hm], [a, -hm]]:
		var c = club(pair[0])
		for p in c.players:
			p.morale = clampf(p.morale + float(pair[1]) + (75.0 - p.morale) * 0.03, 20.0, 100.0)
	# Gate money
	var hc = club(h)
	if f.get("neutral", false):
		var gate: int = Economy.gate_income(hc, 1, 0.8, k.kind)
		hc.book("gate", gate / 2)
		club(a).book("gate", gate / 2)
	else:
		hc.book("gate", Economy.gate_income(hc, _tier(hc), _form(h), k.kind))


func _form(cid: String) -> float:
	var l = comps.get(club(cid).league)
	if l == null or not l.table.has(cid):
		return 0.5
	var form: String = l.table[cid][7]
	if form.is_empty():
		return 0.5
	var pts := 0
	for ch in form:
		pts += 3 if ch == "W" else (1 if ch == "D" else 0)
	return float(pts) / (3.0 * form.length())


func _after_round(k, r: int, res: Array) -> void:
	var e: Dictionary = Economy.cfg()
	if k.kind == "cup":
		for x in res:
			if x["winner"] != "":
				club(x["winner"]).book("prize", int(e["cup_round_prize"]) * int(pow(2, r)))
		if k.winner != "":
			club(k.winner).book("prize", int(e["cup_round_prize"]) * int(pow(2, r + 2)))
	elif k.kind == "europe":
		var win_prize: int = int(e["europe_win"].get(k.id, 0))
		var stage_prize: int = int(e["europe_stage"].get(k.id, 0))
		for x in res:
			if r < CompEurope.GROUP_ROUNDS:
				if x["hg"] > x["ag"]:
					club(x["home"]).book("prize", win_prize)
				elif x["ag"] > x["hg"]:
					club(x["away"]).book("prize", win_prize)
			elif x["winner"] != "":
				club(x["winner"]).book("prize", stage_prize * (1 + (r - CompEurope.GROUP_ROUNDS) / 2))
		if r == CompEurope.GROUP_ROUNDS - 1:
			for g in k.groups.size():
				for cid in k.group_standings(g).slice(0, 2):
					club(cid).book("prize", stage_prize)
	if k.kind != "league":
		var uid := user_club_id
		var was_in := false
		for x in res:
			if x["home"] == uid or x["away"] == uid:
				was_in = true
				var knockout: bool = k.kind == "cup" or r >= CompEurope.GROUP_ROUNDS
				if knockout and x["winner"] != "" and x["winner"] != uid:
					add_news("Knocked out of the %s (%s)." % [k.name, k.round_name(r)])
		if k.kind == "europe" and r == CompEurope.GROUP_ROUNDS - 1 and k.involves(uid):
			add_news("%s group stage over: you %s." % [k.name, "go through to the last 16" if k.alive(uid) else "are out"])
		if k.is_complete() and k.winner == uid and was_in:
			add_news("You won the %s!" % k.name)


func _after_day(d: Dictionary, rng: RandomNumberGenerator) -> void:
	var league_day: bool = d["kind"] == "league" or d["kind"] == "preseason"
	for c in clubs:
		var fit_coach: int = c.staff_skill("fitness")
		var rec: float = (14.0 if league_day else 7.0) + fit_coach / 25.0 + int(c.facilities.get("medical", 1)) * 0.6
		for p in c.players:
			p.fitness = minf(100.0, p.fitness + rec)
	if d["kind"] == "league":
		var share: float = float(Economy.cfg().get("foreign_tv_share", 0.45))
		for c in clubs:
			if c.league == "":
				# Their own league is not simulated, but it still pays them.
				c.book("tv", int(Economy.tv_money(1) * share * c.reputation / 80.0 / LEAGUE_WEEKS))
				if int(d["week"]) % 2 == 0:
					c.book("gate", Economy.gate_income(c, 1, 0.6, "league"))
			for p in c.players:
				if p.injury_weeks > 0:
					p.injury_weeks -= 1
					if p.injury_weeks == 0 and c.id == user_club_id:
						add_news("%s is fit again." % p.name)
			Economy.weekly(c, _tier(c), LEAGUE_WEEKS)
			Development.train_club(c, rng)
		Development.update_familiarity(familiarity, user_tactics.style, user_club().staff_skill("assistant"))
		_expire_offers()
		if int(d["week"]) == 20:
			_contract_warning()
		if int(d["week"]) == 30:
			_mid_season_review(rng)
	if d.get("window", false):
		Transfers.ai_window_day(self, rng)
	if d["kind"] == "preseason" and user_club().sponsor.is_empty() and not sponsor_offers.is_empty():
		choose_sponsor(0)
		add_news("No sponsor was picked, so the board signed the safe deal with %s." % user_club().sponsor["name"])
	if user_club().cash < 0 and d["kind"] == "league":
		user_club().confidence = maxf(0.0, user_club().confidence - 0.5)


# ================================================================ owner

func _set_owner_goals() -> void:
	owner_goals = []
	var uc = user_club()
	var l = comps.get(uc.league)
	if l != null:
		var ranked: Array = l.clubs.duplicate()
		ranked.sort_custom(func(a, b): return club(a).reputation > club(b).reputation)
		var rk: int = ranked.find(uc.id) + 1
		var target: int = clampi(rk + 2, 1, ranked.size())
		var text := "Finish %s or higher in the %s" % [ordinal(target), l.name]
		if target >= ranked.size() - l.relegate:
			target = ranked.size() - l.relegate
			text = "Avoid relegation from the %s" % l.name
		owner_goals.append({"kind": "league", "target": target, "text": text, "weight": 0.55})
	for k in comps_for(uc.id):
		if k.kind == "cup":
			var aim := 2 if uc.reputation >= 70 else 1
			owner_goals.append({"kind": "cup", "comp": k.id, "target": aim, "text": "Win at least %d round%s in the %s" % [aim, "" if aim == 1 else "s", k.name], "weight": 0.1})
		elif k.kind == "europe":
			owner_goals.append({"kind": "europe", "comp": k.id, "target": 1, "text": "Reach the knockout stage of the %s" % k.name, "weight": 0.15})
	owner_goals.append({"kind": "finance", "target": 0, "text": "Finish the season with money in the bank", "weight": 0.2})


## Each goal scored from 0 to 1: {"text", "score", "status"}
func owner_progress() -> Array:
	var out: Array = []
	var uc = user_club()
	for g in owner_goals:
		var score := 0.0
		var status := ""
		match g["kind"]:
			"league":
				var l = comps.get(uc.league)
				var pos: int = l.position_of(uc.id) if l != null else 99
				score = 1.0 if pos <= int(g["target"]) else clampf(1.0 - (pos - int(g["target"])) / 6.0, 0.0, 1.0)
				status = "Currently %s" % ordinal(pos)
			"cup":
				var k = comps.get(g["comp"])
				var won := 0
				if k != null:
					for rr in k.results:
						for x in rr:
							if x[4] == uc.id:
								won += 1
				score = 1.0 if won >= int(g["target"]) else 0.0
				status = "%d round%s won" % [won, "" if won == 1 else "s"]
			"europe":
				var k2 = comps.get(g["comp"])
				var stage: String = k2.reached(uc.id) if k2 != null else ""
				var through: bool = stage != "" and stage != "Group stage"
				score = 1.0 if through else 0.0
				status = k2.reached(uc.id) if k2 != null else ""
			"finance":
				score = 1.0 if uc.cash >= 0 else clampf(1.0 + uc.cash / maxf(1.0, float(yearly_income(uc)) * 0.2), 0.0, 1.0)
				status = "Cash %s" % _money(uc.cash)
		out.append({"text": g["text"], "score": score, "status": status, "weight": g["weight"]})
	return out


func owner_score() -> float:
	var total := 0.0
	var w := 0.0
	for g in owner_progress():
		total += float(g["score"]) * float(g["weight"])
		w += float(g["weight"])
	return total / maxf(0.01, w)


func _mid_season_review(rng: RandomNumberGenerator) -> void:
	var uc = user_club()
	var score := owner_score()
	uc.confidence = clampf(uc.confidence + (score - 0.5) * 20.0, 0.0, 100.0)
	if uc.confidence < 12.0:
		_sack_user(rng, "The owner has lost patience with results this season.")
	elif score < 0.4:
		add_news("The owner is worried about results. Confidence: %d/100." % roundi(uc.confidence))
	# AI clubs doing badly may change manager too.
	_ai_sackings(rng, false)


func _sack_user(rng: RandomNumberGenerator, reason: String) -> void:
	sacked = true
	add_news("You have been sacked. %s" % reason)
	manager_rep = maxf(5.0, manager_rep - 8.0)
	_make_job_offers(rng, true)


func _make_job_offers(rng: RandomNumberGenerator, after_sacking: bool) -> void:
	job_offers = []
	var candidates: Array = clubs.filter(func(c): return c.id != user_club_id and c.league != "")
	candidates.shuffle()
	# After a sacking: smaller clubs. After a good season: clubs bigger than yours.
	var base: float = maxf(manager_rep, float(user_club().reputation))
	var lo: float = manager_rep - 25.0 if after_sacking else base + 2.0
	var hi: float = manager_rep - 2.0 if after_sacking else base + 12.0
	for c in candidates:
		if c.reputation >= lo and c.reputation <= hi:
			job_offers.append({"club": c.id, "reason": "They need a new manager." if after_sacking else "They are impressed by your work."})
			if job_offers.size() >= 3:
				break
	if after_sacking and job_offers.is_empty():
		var weakest: Array = candidates.duplicate()
		weakest.sort_custom(func(a, b): return a.reputation < b.reputation)
		for c in weakest.slice(0, 3):
			job_offers.append({"club": c.id, "reason": "A fresh start lower down."})


## Take a job at another club (after a sacking, or an offer in the summer).
func accept_job(club_id: String, rng: RandomNumberGenerator) -> void:
	var old: String = user_club_id
	managers[old] = _new_manager(rng)
	managers.erase(club_id)
	user_club_id = club_id
	user_auto_pick = true
	user_selection = {}
	sacked = false
	job_offers = []
	var uc = user_club()
	uc.confidence = 60.0
	_set_owner_goals()
	sponsor_offers = []
	add_news("You are the new manager of %s." % uc.name)
	_xi_cache = {}


func _ai_sackings(rng: RandomNumberGenerator, season_end: bool) -> void:
	for id in comps:
		var l = comps[id]
		if l.kind != "league":
			continue
		var order: Array = l.standings()
		var n: int = order.size()
		var ranked: Array = l.clubs.duplicate()
		ranked.sort_custom(func(a, b): return club(a).reputation > club(b).reputation)
		for i in n:
			var cid: String = order[i]
			if cid == user_club_id or not managers.has(cid):
				continue
			var expected: int = ranked.find(cid)
			var under: int = i - expected
			if under >= n / 3 and rng.randf() < (0.5 if season_end else 0.25):
				var old_name: String = managers[cid].name
				managers[cid] = _new_manager(rng)
				if id == user_club().league:
					add_news("%s have sacked %s. %s takes over." % [club(cid).name, old_name, managers[cid].name])
				if season_end and rng.randf() < 0.3 and manager_rep >= club(cid).reputation - 12:
					job_offers.append({"club": cid, "reason": "They want you to replace %s." % old_name})


func _contract_warning() -> void:
	var expiring: Array = user_club().players.filter(func(p): return p.contract_end <= year and p.loan_from == "")
	if not expiring.is_empty():
		add_news("%d contract%s run out this summer: %s. Renew them in the Squad tab or they will leave." % [
			expiring.size(), "" if expiring.size() == 1 else "s", ", ".join(expiring.slice(0, 5).map(func(p): return p.name))])


# ================================================================ human manager actions

func choose_sponsor(index: int) -> void:
	if index < 0 or index >= sponsor_offers.size():
		return
	user_club().sponsor = sponsor_offers[index]
	sponsor_offers = []


func set_ticket_price(price: int) -> void:
	user_club().ticket_price = clampi(price, 1, 500)


## A bid for another club's player. Returns {"answer", "fee", "text"}.
func bid(p, fee: int) -> Dictionary:
	var seller = club(club_of(p.id))
	var uc = user_club()
	if not window_open():
		return {"answer": "closed", "fee": 0, "text": "The transfer window is closed."}
	if seller == uc:
		return {"answer": "own", "fee": 0, "text": "He already plays for you."}
	if fee > uc.cash:
		return {"answer": "money", "fee": fee, "text": "You don't have %s to spend." % _money(fee)}
	if seller == null:
		return {"answer": "accept", "fee": 0, "text": "%s is a free agent. Agree personal terms to sign him." % p.name}
	if not Transfers.interested(p, uc):
		return {"answer": "reject", "fee": 0, "text": "%s is not interested in joining %s." % [p.name, uc.name]}
	var r: Dictionary = Transfers.evaluate_bid(self, seller, p, fee, uc)
	match r["answer"]:
		"accept":
			r["text"] = "%s accept %s. Now agree personal terms." % [seller.name, _money(fee)]
		"counter":
			r["text"] = "%s want %s." % [seller.name, _money(r["fee"])]
		_:
			r["text"] = "%s reject the bid. They value him at about %s." % [seller.name, _money(r["fee"])]
	return r


## Personal terms after an accepted bid; completes the transfer when accepted.
func offer_contract(p, fee: int, wage: int, years: int) -> Dictionary:
	var uc = user_club()
	var seller = club(club_of(p.id))
	var r: Dictionary = Transfers.evaluate_terms(self, p, uc, wage, years)
	if r["answer"] == "accept":
		if fee > uc.cash:
			return {"answer": "money", "wage": wage, "text": "Not enough money for the fee."}
		Transfers.complete(self, p, seller, uc, fee, wage, years)
		r["text"] = "%s signs for %s on a %d-year deal!" % [p.name, uc.name, years]
	elif r["answer"] == "counter":
		r["text"] = "%s wants %s a week." % [p.name, _money(r["wage"])]
	else:
		r["text"] = "%s turns the offer down. He wants about %s a week." % [p.name, _money(r["wage"])]
	return r


## Loan for the rest of the season. The parent club agrees if he is not a regular starter.
func loan_in(p, wage_share: float) -> Dictionary:
	var seller = club(club_of(p.id))
	if seller == null or not window_open() or seller.id == user_club_id:
		return {"answer": "reject", "text": "A loan is not possible."}
	if is_key_player(seller, p):
		return {"answer": "reject", "text": "%s will not loan out a first-team regular." % seller.name}
	if wage_share < 0.5 and p.age > 23:
		return {"answer": "reject", "text": "%s want you to pay at least half of his wage." % seller.name}
	Transfers.complete(self, p, seller, user_club(), 0, p.wage, 1, true, wage_share)
	return {"answer": "accept", "text": "%s joins on loan until the end of the season." % p.name}


func renew(p, wage: int, years: int) -> Dictionary:
	var r: Dictionary = Transfers.evaluate_terms(self, p, user_club(), wage, years)
	if r["answer"] == "accept":
		p.wage = wage
		p.contract_end = year + years
		r["text"] = "%s signs a new deal until %d." % [p.name, p.contract_end + 1]
	elif r["answer"] == "counter":
		r["text"] = "%s wants %s a week." % [p.name, _money(r["wage"])]
	else:
		r["text"] = "%s turns it down. He wants about %s a week." % [p.name, _money(r["wage"])]
	return r


func search_players(filters: Dictionary, limit: int = 300) -> Array:
	return Transfers.search(self, filters, limit)


func release_player(p) -> void:
	Transfers.release(self, user_club(), p)


func toggle_listed(p) -> void:
	p.listed = not p.listed


func add_offer(from_club, p, fee: int, wage: int) -> void:
	for o in offers:
		if o["player"] == p.id:
			return
	offers.append({"id": next_offer_id, "club": from_club.id, "player": p.id, "fee": fee, "wage": wage, "expires": day + 6})
	next_offer_id += 1
	add_news("%s bid %s for %s. Answer in the Transfers tab." % [from_club.name, _money(fee), p.name])


func answer_offer(offer_id: int, accept: bool) -> String:
	for o in offers.duplicate():
		if int(o["id"]) != offer_id:
			continue
		offers.erase(o)
		var p = player(o["player"])
		var buyer = club(o["club"])
		if not accept or p == null or buyer == null or club_of(p.id) != user_club_id:
			return "Offer turned down."
		if buyer.cash < int(o["fee"]):
			return "%s can no longer afford the fee." % buyer.name
		Transfers.complete(self, p, user_club(), buyer, int(o["fee"]), int(o["wage"]), 3)
		return "%s joins %s for %s." % [p.name, buyer.name, _money(int(o["fee"]))]
	return ""


func _expire_offers() -> void:
	offers = offers.filter(func(o): return int(o["expires"]) >= day and player(o["player"]) != null and club_of(o["player"]) == user_club_id)


func promote_youth(p) -> void:
	var uc = user_club()
	if uc.youth.has(p):
		uc.youth.erase(p)
		uc.players.append(p)
		p.wage = maxi(p.wage, int(Economy.cfg()["min_wage"]))
		_xi_cache.erase(uc.id)


func release_youth(p) -> void:
	user_club().youth.erase(p)
	_player_by_id.erase(p.id)
	_player_club.erase(p.id)


## Staff candidates for a role: Array of staff dictionaries.
func staff_candidates(role: String, rng: RandomNumberGenerator) -> Array:
	var uc = user_club()
	var base: int = uc.staff_skill(role)
	var out: Array = []
	for i in 4:
		out.append(WorldGen.make_staff(rng, clampi(base - 8 + i * 7 + rng.randi_range(-4, 4), 20, 95), year))
	return out


func hire_staff(role: String, s: Dictionary) -> void:
	var uc = user_club()
	if uc.staff.has(role):
		# Paying off the old contract: ten weeks' wages.
		uc.book("staff", -int(uc.staff[role]["wage"]) * 10)
	uc.staff[role] = s
	add_news("%s joins as %s." % [s["name"], role.replace("_", " ")])


func on_player_moved(p, seller, buyer, fee: int, loan: bool) -> void:
	_player_club[p.id] = buyer.id if buyer != null else ""
	_player_by_id[p.id] = p
	if seller != null:
		_xi_cache.erase(seller.id)
	if buyer != null:
		_xi_cache.erase(buyer.id)
	var uid := user_club_id
	if (seller != null and seller.id == uid) or (buyer != null and buyer.id == uid):
		return
	# Big moves in the human's league make the news.
	var ul: String = user_club().league
	if fee >= 5000000 and buyer != null and (buyer.league == ul or (seller != null and seller.league == ul)):
		add_news("%s joins %s from %s for %s." % [p.name, buyer.name, seller.name if seller != null else "free agency", _money(fee)])


# ================================================================ season end

func _close_season(rng: RandomNumberGenerator) -> void:
	season_over = true
	var uc = user_club()
	var summary := {"year": year, "promoted": [], "relegated": [], "champions": {}, "cups": {}, "awards": []}
	pending_moves = {}
	last_standings = {}
	# Leagues: champions, prize money, history, promotion and relegation.
	var by_country := {}
	for def in league_defs:
		var l = comps.get(def["id"])
		if l == null:
			continue
		var order: Array = l.standings()
		last_standings[l.id] = order
		var n: int = order.size()
		var tv_bonus: int = int(Economy.tv_money(l.tier) * float(Economy.cfg()["tv_position_bonus"]))
		for i in n:
			var c = club(order[i])
			c.book("prize", int(tv_bonus * float(n - 1 - i) / maxf(1.0, n - 1)))
			c.history.append({"year": year, "league": l.name, "position": i + 1})
			if not c.sponsor.is_empty() and int(c.sponsor.get("bonus_target", 0)) > 0 and i + 1 <= int(c.sponsor["bonus_target"]):
				c.book("sponsor", int(c.sponsor.get("bonus", 0)))
		var champ = club(order[0])
		champ.trophies.append({"year": year, "name": l.name})
		honours.append({"year": year, "comp": l.name, "winner": champ.id})
		summary["champions"][l.id] = champ.id
		by_country[def["country"]] = by_country.get(def["country"], [])
		by_country[def["country"]].append(l)
		_season_awards(l, summary)
	for cid in by_country:
		var ls: Array = by_country[cid]
		ls.sort_custom(func(a, b): return a.tier < b.tier)
		for t in ls.size() - 1:
			var upper = ls[t]
			var lower = ls[t + 1]
			var k: int = mini(upper.relegate, mini(upper.clubs.size(), lower.clubs.size()) / 2)
			var down: Array = upper.standings().slice(upper.clubs.size() - k)
			var up: Array = lower.standings().slice(0, k)
			for c in down:
				pending_moves[c] = lower.id
				summary["relegated"].append(c)
			for c in up:
				pending_moves[c] = upper.id
				summary["promoted"].append(c)
	# Cups and Europe
	for id in comps:
		var k = comps[id]
		if k.kind != "league" and k.winner != "":
			club(k.winner).trophies.append({"year": year, "name": k.name})
			honours.append({"year": year, "comp": k.name, "winner": k.winner})
			summary["cups"][id] = k.winner
			if k.kind == "cup":
				last_cup_winners[k.country] = k.winner
	# Player career records
	for c in clubs:
		for p in c.players:
			var st := stats_for(p.id)
			if st["apps"] > 0:
				p.career.append({"year": year, "club": c.short_name, "apps": st["apps"], "goals": st["goals"],
					"assists": st["assists"], "avg": snappedf(st["rating_sum"] / st["apps"], 0.01)})
				if p.career.size() > 20:
					p.career.pop_front()
	# The human manager's review
	var score := owner_score()
	var trophies_won: Array = uc.trophies.filter(func(t): return int(t["year"]) == year).map(func(t): return t["name"])
	uc.confidence = clampf(uc.confidence + (score - 0.5) * 50.0 + trophies_won.size() * 10.0, 0.0, 100.0)
	var grant: int = int(yearly_income(uc) * float(Economy.cfg()["owner_grant_share"]) * score)
	if grant > 0:
		uc.book("owner", grant)
	manager_rep = clampf(manager_rep + (score - 0.5) * 12.0 + trophies_won.size() * 4.0, 1.0, 99.0)
	var l_user = comps.get(uc.league)
	var pos: int = l_user.position_of(uc.id) if l_user != null else 0
	history.append({"year": year, "club": uc.name, "league": l_user.name if l_user != null else "", "position": pos,
		"points": l_user.table[uc.id][6] if l_user != null else 0, "trophies": trophies_won, "score": snappedf(score, 0.01)})
	summary["owner_score"] = score
	summary["grant"] = grant
	summary["position"] = pos
	summary["trophies"] = trophies_won
	season_summary = summary
	job_offers = []
	if uc.confidence < 15.0:
		_sack_user(rng, "The owner was unhappy with the season.")
	else:
		if score >= 0.75:
			_make_job_offers(rng, false)
		add_news("Season over: you finished %s. The owner rates the season %d/100%s." % [ordinal(pos), roundi(score * 100.0),
			(" and gives a bonus of %s" % _money(grant)) if grant > 0 else ""])
	_ai_sackings(rng, true)
	# Contracts
	for c in clubs:
		if c.id != user_club_id:
			Transfers.ai_contracts(self, c, rng)
	for p in uc.players.duplicate():
		if p.loan_from == "" and p.contract_end <= year:
			uc.players.erase(p)
			free_agents.append(p)
			on_player_moved(p, uc, null, 0, false)
			add_news("%s's contract has ended and he leaves the club." % p.name)
	# Loans end
	for c in clubs:
		for p in c.players.duplicate():
			if p.loan_from != "":
				var home = club(p.loan_from)
				c.players.erase(p)
				p.loan_from = ""
				p.loan_wage_share = 1.0
				if home != null:
					home.players.append(p)
					on_player_moved(p, c, home, 0, false)
				else:
					free_agents.append(p)


## AI clubs with money to spare invest it in facilities (which also cost upkeep).
func _ai_invest(c) -> void:
	var income: int = yearly_income(c)
	for _i in 2:
		if c.cash < income:
			return
		var lowest := ""
		for k in Club.FACILITIES:
			if int(c.facilities[k]) < 5 and (lowest == "" or int(c.facilities[k]) < int(c.facilities[lowest])):
				lowest = k
		if lowest == "":
			return
		var cost: int = Economy.upgrade_cost(c, lowest)
		if cost < 0 or c.cash - cost < income / 2:
			return
		Economy.upgrade(c, lowest)


func _season_awards(l, summary: Dictionary) -> void:
	var race := award_race(l.id, 1)
	for key in ["best", "young", "scorer"]:
		if race[key].is_empty():
			continue
		var pid: String = race[key][0]["id"]
		var label: String = {"best": "Player of the Season", "young": "Young Player of the Season", "scorer": "Top Scorer"}[key]
		var entry := {"year": year, "comp": l.name, "award": label, "player": pid, "club": club_of(pid), "value": race[key][0]["value"]}
		awards.append(entry)
		summary["awards"].append(entry)
		if club_of(pid) == user_club_id:
			add_news("%s wins %s in the %s!" % [player(pid).name, label, l.name])
	# Manager of the season: the club that beat expectations by the most.
	var ranked: Array = l.clubs.duplicate()
	ranked.sort_custom(func(a, b): return club(a).reputation > club(b).reputation)
	var order: Array = l.standings()
	var best_id := ""
	var best_gain := -999
	for i in order.size():
		var gain: int = ranked.find(order[i]) - i
		if gain > best_gain:
			best_gain = gain
			best_id = order[i]
	if best_id != "":
		var mname: String = manager_name if best_id == user_club_id else (managers[best_id].name if managers.has(best_id) else "?")
		var entry2 := {"year": year, "comp": l.name, "award": "Manager of the Season", "player": "", "manager": mname, "club": best_id, "value": best_gain}
		awards.append(entry2)
		summary["awards"].append(entry2)
		if best_id == user_club_id:
			manager_rep = minf(99.0, manager_rep + 4.0)
			add_news("You are the %s Manager of the Season!" % l.name)


func next_season(rng: RandomNumberGenerator) -> void:
	if not season_over:
		return
	# Promotion and relegation
	for cid in pending_moves:
		var c = club(cid)
		var up: bool = int(league_def(pending_moves[cid]).get("tier", 1)) < _tier(c)
		c.league = pending_moves[cid]
		c.fans = int(c.fans * (1.15 if up else 0.85))
		c.fans = mini(c.fans, int(c.stadium * 1.1))
		c.ticket_price = Economy.fair_price(_tier(c))
	pending_moves = {}
	year += 1
	# Ageing, retirements, reputation
	var weights: Dictionary = Balance.data()["role_weights"]
	for c in clubs:
		for p in c.players.duplicate():
			Development.age_player(p, rng)
			if Development.retires(p, rng):
				c.players.erase(p)
				_player_by_id.erase(p.id)
				_player_club.erase(p.id)
				if c.id == user_club_id:
					add_news("%s has retired." % p.name)
		for p in c.youth:
			Development.age_player(p, rng)
		c.reputation = clampi(roundi(c.reputation * 0.8 + (xi_strength(c.id) if not c.players.is_empty() else c.reputation) * 0.2), 1, 99)
	for p in free_agents.duplicate():
		Development.age_player(p, rng)
		if Development.retires(p, rng) or p.age >= 35:
			free_agents.erase(p)
			_player_by_id.erase(p.id)
			_player_club.erase(p.id)
	free_agents.sort_custom(func(a, b): return a.overall > b.overall)
	if free_agents.size() > MAX_FREE_AGENTS:
		for p in free_agents.slice(MAX_FREE_AGENTS):
			_player_by_id.erase(p.id)
			_player_club.erase(p.id)
		free_agents.resize(MAX_FREE_AGENTS)
	# Youth intake. AI clubs promote their best prospects when the squad is short.
	_xi_cache = {}
	for c in clubs:
		var strength: float = generation_level(c)
		var intake: Array = Development.youth_intake(c, strength, year, rng)
		for p in intake:
			c.youth.append(p)
			_player_by_id[p.id] = p
			_player_club[p.id] = c.id
		if c.id == user_club_id:
			add_news("%d new prospects join your youth academy." % intake.size())
		else:
			Transfers.fill_squad(self, c, 23, rng)
			_ai_invest(c)
		c.youth.sort_custom(func(a, b): return a.potential > b.potential)
		while c.youth.size() > MAX_ACADEMY:
			var gone = c.youth.pop_back()
			_player_by_id.erase(gone.id)
			_player_club.erase(gone.id)
		for p in c.players:
			p.refresh_overall(weights)
	# The board never lets your squad fall apart: below 16 players it signs free agents.
	var uc = user_club()
	if uc.players.size() < 16 or uc.players.filter(func(p): return p.position == "GK").size() < 2:
		var added: Array = Transfers.fill_squad(self, uc, 16, rng)
		if not added.is_empty():
			add_news("Your squad was too small, so the board signed %d player%s: %s." % [added.size(), "" if added.size() == 1 else "s", ", ".join(added.map(func(p): return p.name))])
	_build_season(rng, false)
	add_news("The %d/%02d season begins. Pick a sponsor and check the owner's targets in the Club tab." % [year, (year + 1) % 100])


# ================================================================ helpers

static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


static func _money(v: int) -> String:
	var neg := v < 0
	var a: int = absi(v)
	var s := ""
	if a >= 1000000:
		s = "€%.1fM" % (a / 1000000.0)
	elif a >= 1000:
		s = "€%dK" % roundi(a / 1000.0)
	else:
		s = "€%d" % a
	return ("-" + s) if neg else s


# ================================================================ saving

func to_dict() -> Dictionary:
	var mgrs := {}
	for id in managers:
		mgrs[id] = managers[id].to_dict()
	var cd := {}
	for id in comps:
		cd[id] = comps[id].to_dict()
	return {
		"version": SAVE_VERSION, "world_name": world_name, "fictional": fictional,
		"countries": countries, "league_defs": league_defs, "europe_defs": europe_defs,
		"clubs": clubs.map(func(c): return c.to_dict()),
		"free_agents": free_agents.map(func(p): return p.to_dict()),
		"managers": mgrs,
		"user_club_id": user_club_id, "manager_name": manager_name, "manager_rep": manager_rep,
		"user_tactics": user_tactics.to_dict(), "user_auto_pick": user_auto_pick, "user_selection": user_selection,
		"familiarity": familiarity, "owner_goals": owner_goals, "sponsor_offers": sponsor_offers,
		"offers": offers, "job_offers": job_offers, "sacked": sacked,
		"year": year, "comps": cd, "calendar": calendar, "day": day, "season_over": season_over,
		"stats": stats, "style_history": style_history, "user_results": user_results, "news": news,
		"last_standings": last_standings, "last_cup_winners": last_cup_winners, "pending_moves": pending_moves,
		"season_summary": season_summary, "history": history, "honours": honours, "awards": awards,
		"next_offer_id": next_offer_id, "level_anchor": level_anchor,
	}


func load_dict(d: Dictionary) -> void:
	world_name = str(d.get("world_name", ""))
	fictional = bool(d.get("fictional", true))
	countries = d.get("countries", [])
	league_defs = d.get("league_defs", [])
	europe_defs = d.get("europe_defs", [])
	clubs = []
	for x in d.get("clubs", []):
		var c = Club.new()
		c.load_dict(x)
		clubs.append(c)
	free_agents = []
	for x in d.get("free_agents", []):
		var p = Player.new()
		p.load_dict(x)
		free_agents.append(p)
	managers = {}
	var md: Dictionary = d.get("managers", {})
	for id in md:
		var m = AiManager.new()
		m.load_dict(md[id])
		managers[id] = m
	user_club_id = str(d.get("user_club_id", ""))
	manager_name = str(d.get("manager_name", "You"))
	manager_rep = float(d.get("manager_rep", 35.0))
	user_tactics = Tactics.new()
	user_tactics.load_dict(d.get("user_tactics", {}))
	user_auto_pick = bool(d.get("user_auto_pick", true))
	user_selection = d.get("user_selection", {})
	familiarity = d.get("familiarity", {})
	owner_goals = d.get("owner_goals", [])
	sponsor_offers = d.get("sponsor_offers", [])
	offers = d.get("offers", [])
	job_offers = d.get("job_offers", [])
	sacked = bool(d.get("sacked", false))
	year = int(d.get("year", 2026))
	comps = {}
	var cd: Dictionary = d.get("comps", {})
	for id in cd:
		var x: Dictionary = cd[id]
		var k = null
		match str(x.get("kind", "")):
			"league": k = CompLeague.new()
			"cup": k = CompCup.new()
			"europe": k = CompEurope.new()
		if k != null:
			k.load_dict(x)
			comps[id] = k
	calendar = []
	for x in d.get("calendar", []):
		calendar.append({"label": x["label"], "kind": x["kind"], "week": int(x["week"]), "window": bool(x.get("window", false)),
			"items": x["items"].map(func(it): return [it[0], int(it[1])])})
	day = int(d.get("day", 0))
	season_over = bool(d.get("season_over", false))
	stats = {}
	var sd: Dictionary = d.get("stats", {})
	for cid in sd:
		var m2 := {}
		for pid in sd[cid]:
			var s: Array = sd[cid][pid]
			m2[pid] = [int(s[0]), int(s[1]), int(s[2]), float(s[3]), int(s[4]), int(s[5])]
		stats[cid] = m2
	style_history = {}
	var sh: Dictionary = d.get("style_history", {})
	for id in sh:
		style_history[id] = sh[id].map(func(s): return int(s))
	user_results = []
	for r in d.get("user_results", []):
		var r2: Dictionary = r.duplicate()
		r2["hg"] = int(r["hg"])
		r2["ag"] = int(r["ag"])
		r2["round"] = int(r.get("round", 0))
		r2["day"] = int(r.get("day", 0))
		user_results.append(r2)
	news = d.get("news", [])
	last_standings = d.get("last_standings", {})
	last_cup_winners = d.get("last_cup_winners", {})
	pending_moves = d.get("pending_moves", {})
	season_summary = d.get("season_summary", {})
	history = d.get("history", [])
	honours = d.get("honours", [])
	awards = d.get("awards", [])
	next_offer_id = int(d.get("next_offer_id", 1))
	_index()
	level_anchor = d.get("level_anchor", {})
	if level_anchor.is_empty():
		_compute_anchors()


func save(path: String = SAVE_PATH) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func load_from(path: String = SAVE_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != SAVE_VERSION:
		return false
	load_dict(parsed)
	return true
