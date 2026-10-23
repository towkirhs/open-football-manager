extends RefCounted
## One league career: the clubs, this season's fixtures, results, table and player stats.
## The human manager runs one club; AI managers run the rest.
##
## Weekly flow:
##   1. prepare_user_match() gives a match engine for the human's game (watch it live),
##      or skip it and let play_week() simulate it with the saved tactics.
##   2. play_week() plays every other game, applies all results, and moves to the next week.

const Club = preload("res://src/sim/club.gd")
const Tactics = preload("res://src/sim/tactics.gd")
const Lineup = preload("res://src/sim/lineup.gd")
const MatchEngine = preload("res://src/sim/match_engine.gd")
const AiManager = preload("res://src/sim/ai_manager.gd")
const Fixtures = preload("res://src/sim/fixtures.gd")

const SAVE_VERSION := 1
const SAVE_PATH := "user://career.json"
const STYLE_MEMORY := 6
const WEEKLY_RECOVERY := 15.0
const MORALE_WIN := 4.0
const MORALE_LOSS := -4.0

var league_name: String = ""
var year: int = 2026
var clubs: Array = []
var user_club_id: String = ""
## Weeks of [home_id, away_id] pairs.
var fixtures: Array = []
## Index of the next week to play.
var week: int = 0
## Weeks of {"home", "away", "hg", "ag"} results.
var results: Array = []
## club_id -> {"p","w","d","l","gf","ga","pts","form"}
var table: Dictionary = {}
## club_id -> AiManager (every club except the human's)
var managers: Dictionary = {}
## club_id -> recent styles used, newest last. AI managers read this to plan against you.
var style_history: Dictionary = {}
## player_id -> {"apps","goals","assists","rating_sum","yellows","reds"}
var player_stats: Dictionary = {}
var user_tactics = null
## Newest first: {"week": int, "text": String}
var news: Array = []
## Past seasons: {"year", "champion", "user_position", "user_points"}
var history: Array = []

var _club_by_id: Dictionary = {}
var _player_by_id: Dictionary = {}
var _player_club: Dictionary = {}


# ---------------------------------------------------------------- setup

func new_game(league: Dictionary, user_id: String, rng: RandomNumberGenerator) -> void:
	league_name = league.get("name", "League")
	clubs = league["clubs"]
	user_club_id = user_id
	_index()
	managers = {}
	for c in clubs:
		if c.id == user_id:
			continue
		var m = AiManager.new()
		m.setup_random(rng)
		managers[c.id] = m
	user_tactics = Tactics.new()
	user_tactics.formation = "4-4-2"
	user_tactics.style = Tactics.Style.POSSESSION
	user_tactics.familiarity = 0.85
	history = []
	news = []
	start_season(rng)
	add_news("Welcome to %s. The board expects a good season." % user_club().name)


func start_season(rng: RandomNumberGenerator) -> void:
	var ids: Array = clubs.map(func(c): return c.id)
	fixtures = Fixtures.double_round_robin(ids, rng)
	week = 0
	results = []
	table = {}
	for id in ids:
		table[id] = {"p": 0, "w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0, "form": []}
	player_stats = {}
	style_history = {}
	for c in clubs:
		for p in c.players:
			p.fitness = 100.0


func _index() -> void:
	_club_by_id = {}
	_player_by_id = {}
	_player_club = {}
	for c in clubs:
		_club_by_id[c.id] = c
		for p in c.players:
			_player_by_id[p.id] = p
			_player_club[p.id] = c.id


# ---------------------------------------------------------------- queries

func club(id: String):
	return _club_by_id.get(id)


func user_club():
	return _club_by_id.get(user_club_id)


func player(id: String):
	return _player_by_id.get(id)


func total_weeks() -> int:
	return fixtures.size()


func is_finished() -> bool:
	return week >= fixtures.size()


## The human's fixture in a given week: {"home": id, "away": id, "user_home": bool}, or {} if none.
func user_fixture(w: int = -1) -> Dictionary:
	if w < 0:
		w = week
	if w >= fixtures.size():
		return {}
	for m in fixtures[w]:
		if m[0] == user_club_id or m[1] == user_club_id:
			return {"home": m[0], "away": m[1], "user_home": m[0] == user_club_id}
	return {}


## Result of the human's game in a past week, or {}.
func user_result(w: int) -> Dictionary:
	if w >= results.size():
		return {}
	for r in results[w]:
		if r["home"] == user_club_id or r["away"] == user_club_id:
			return r
	return {}


## Club ids sorted by points, goal difference, goals scored, then name.
func standings() -> Array:
	var ids: Array = table.keys()
	ids.sort_custom(_ranks_above)
	return ids


func _ranks_above(a: String, b: String) -> bool:
	var ta: Dictionary = table[a]
	var tb: Dictionary = table[b]
	if ta["pts"] != tb["pts"]:
		return ta["pts"] > tb["pts"]
	var gda: int = ta["gf"] - ta["ga"]
	var gdb: int = tb["gf"] - tb["ga"]
	if gda != gdb:
		return gda > gdb
	if ta["gf"] != tb["gf"]:
		return ta["gf"] > tb["gf"]
	return club(a).name < club(b).name


func position_of(id: String) -> int:
	return standings().find(id) + 1


## The style a club has used most in its recent games, or -1 if it has not played yet.
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


## Top scorers: Array of {"id", "name", "club", "goals", "assists"}.
func top_scorers(n: int = 10) -> Array:
	var rows: Array = []
	for id in player_stats:
		var st: Dictionary = player_stats[id]
		if st["goals"] > 0:
			var p = player(id)
			if p != null:
				rows.append({"id": id, "name": p.name, "club": club(_player_club[id]).short_name, "goals": st["goals"], "assists": st["assists"]})
	rows.sort_custom(func(a, b): return a["goals"] > b["goals"] or (a["goals"] == b["goals"] and a["assists"] > b["assists"]))
	return rows.slice(0, n)


func stats_for(player_id: String) -> Dictionary:
	return player_stats.get(player_id, {"apps": 0, "goals": 0, "assists": 0, "rating_sum": 0.0, "yellows": 0, "reds": 0})


func add_news(text: String) -> void:
	news.push_front({"week": week + 1, "text": text})
	if news.size() > 40:
		news.resize(40)


# ---------------------------------------------------------------- playing

func ai_tactics(club_id: String, opponent_id: String, rng: RandomNumberGenerator):
	return managers[club_id].pick_tactics(usual_style(opponent_id), rng)


func tactics_for(club_id: String, opponent_id: String, rng: RandomNumberGenerator):
	if club_id == user_club_id:
		return user_tactics.copy()
	return ai_tactics(club_id, opponent_id, rng)


func make_engine(home_id: String, away_id: String, rng: RandomNumberGenerator):
	var hc = club(home_id)
	var ac = club(away_id)
	var ht = tactics_for(home_id, away_id, rng)
	var at = tactics_for(away_id, home_id, rng)
	var hl = Lineup.new()
	hl.auto_pick(hc.players, ht.formation)
	var al = Lineup.new()
	al.auto_pick(ac.players, at.formation)
	var e = MatchEngine.new()
	e.setup(hc.name, hl, ht, ac.name, al, at, rng)
	if managers.has(home_id):
		e.set_ai(0, managers[home_id])
	if managers.has(away_id):
		e.set_ai(1, managers[away_id])
	return e


## Engine for the human's game this week, ready to step() live. Null if no game.
func prepare_user_match(rng: RandomNumberGenerator):
	var f := user_fixture()
	if f.is_empty():
		return null
	return make_engine(f["home"], f["away"], rng)


## Plays the rest of the week. Pass the finished live engine for the human's game,
## or null to simulate it. Returns this week's results.
func play_week(rng: RandomNumberGenerator, user_engine = null) -> Array:
	if is_finished():
		return []
	var played: Array = []
	results.append(played)
	for m in fixtures[week]:
		var h: String = m[0]
		var a: String = m[1]
		var e = null
		if user_engine != null and (h == user_club_id or a == user_club_id):
			e = user_engine
			if not e.finished:
				e.simulate()
		else:
			e = make_engine(h, a, rng)
			e.simulate()
		played.append(_apply(h, a, e))
	_end_of_week()
	week += 1
	if is_finished():
		_record_season_end()
	return played


func _apply(h: String, a: String, e) -> Dictionary:
	var r: Dictionary = e.result()
	var hg: int = r["home_goals"]
	var ag: int = r["away_goals"]
	_table_row(h, hg, ag)
	_table_row(a, ag, hg)
	for pair in [[h, e.home.tactics.style], [a, e.away.tactics.style]]:
		var hist: Array = style_history.get(pair[0], [])
		hist.append(pair[1])
		if hist.size() > STYLE_MEMORY:
			hist.pop_front()
		style_history[pair[0]] = hist

	for id in r["ratings"]:
		var st := stats_for(id)
		st["apps"] += 1
		st["rating_sum"] += float(r["ratings"][id])
		player_stats[id] = st
	for ev in r["events"]:
		var pid: String = ev.get("player", "")
		match ev["type"]:
			"goal":
				_bump(pid, "goals")
				_bump(ev.get("assist", ""), "assists")
			"yellow":
				_bump(pid, "yellows")
			"red":
				_bump(pid, "reds")
	for inj in r["injuries"]:
		var p = player(inj["id"])
		if p != null:
			# +1 because the weekly countdown runs right after this match.
			p.injury_weeks = int(inj["weeks"]) + 1
			if _player_club.get(p.id) == user_club_id:
				add_news("%s is injured and out for about %d week%s." % [p.name, inj["weeks"], "" if inj["weeks"] == 1 else "s"])
	for id in r["condition"]:
		if r["ratings"].has(id):
			var p = player(id)
			if p != null:
				p.fitness = float(r["condition"][id])

	var hm := 0.0
	var am := 0.0
	if hg > ag:
		hm = MORALE_WIN
		am = MORALE_LOSS
	elif ag > hg:
		hm = MORALE_LOSS
		am = MORALE_WIN
	for pair in [[h, hm], [a, am]]:
		for p in club(pair[0]).players:
			p.morale = clampf(p.morale + pair[1], 20.0, 100.0)

	if h == user_club_id or a == user_club_id:
		var won: bool = (h == user_club_id and hg > ag) or (a == user_club_id and ag > hg)
		var drew: bool = hg == ag
		add_news("%s %s %d-%d %s." % ["Win:" if won else ("Draw:" if drew else "Defeat:"), club(h).name, hg, ag, club(a).name])
	return {"home": h, "away": a, "hg": hg, "ag": ag}


func _bump(pid: String, key: String) -> void:
	if pid == "":
		return
	var st := stats_for(pid)
	st[key] += 1
	player_stats[pid] = st


func _table_row(id: String, gf: int, ga: int) -> void:
	var t: Dictionary = table[id]
	t["p"] += 1
	t["gf"] += gf
	t["ga"] += ga
	var mark := "D"
	if gf > ga:
		t["w"] += 1
		t["pts"] += 3
		mark = "W"
	elif gf < ga:
		t["l"] += 1
		mark = "L"
	else:
		t["d"] += 1
		t["pts"] += 1
	var form: Array = t["form"]
	form.append(mark)
	if form.size() > 5:
		form.pop_front()


func _end_of_week() -> void:
	for c in clubs:
		for p in c.players:
			if p.injury_weeks > 0:
				p.injury_weeks -= 1
				if p.injury_weeks == 0 and c.id == user_club_id:
					add_news("%s is fit again." % p.name)
			p.fitness = minf(100.0, p.fitness + WEEKLY_RECOVERY)


func _record_season_end() -> void:
	var order := standings()
	var champion = club(order[0])
	var pos: int = order.find(user_club_id) + 1
	history.append({"year": year, "champion": champion.name, "user_position": pos, "user_points": table[user_club_id]["pts"]})
	add_news("Season over. %s are champions. You finished %s." % [champion.name, ordinal(pos)])


## Starts the next season with the same clubs (ageing and transfers come later).
func next_season(rng: RandomNumberGenerator) -> void:
	year += 1
	start_season(rng)
	add_news("The %d/%d season begins." % [year, (year + 1) % 100])


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var mgrs := {}
	for id in managers:
		mgrs[id] = managers[id].to_dict()
	return {
		"version": SAVE_VERSION,
		"league_name": league_name,
		"year": year,
		"clubs": clubs.map(func(c): return c.to_dict()),
		"user_club_id": user_club_id,
		"fixtures": fixtures,
		"week": week,
		"results": results,
		"table": table,
		"managers": mgrs,
		"style_history": style_history,
		"player_stats": player_stats,
		"user_tactics": user_tactics.to_dict(),
		"news": news,
		"history": history,
	}


func load_dict(d: Dictionary) -> void:
	league_name = str(d.get("league_name", ""))
	year = int(d.get("year", 2026))
	clubs = []
	for cd in d.get("clubs", []):
		var c = Club.new()
		c.load_dict(cd)
		clubs.append(c)
	user_club_id = str(d.get("user_club_id", ""))
	fixtures = d.get("fixtures", [])
	week = int(d.get("week", 0))
	# JSON stores every number as a float; turn counts back into ints.
	results = []
	for wk in d.get("results", []):
		results.append(wk.map(func(r): return {"home": r["home"], "away": r["away"], "hg": int(r["hg"]), "ag": int(r["ag"])}))
	table = {}
	var td: Dictionary = d.get("table", {})
	for id in td:
		var row: Dictionary = td[id]
		table[id] = {"p": int(row["p"]), "w": int(row["w"]), "d": int(row["d"]), "l": int(row["l"]),
			"gf": int(row["gf"]), "ga": int(row["ga"]), "pts": int(row["pts"]), "form": row.get("form", [])}
	managers = {}
	var md: Dictionary = d.get("managers", {})
	for id in md:
		var m = AiManager.new()
		m.load_dict(md[id])
		managers[id] = m
	style_history = {}
	var sh: Dictionary = d.get("style_history", {})
	for id in sh:
		style_history[id] = sh[id].map(func(s): return int(s))
	player_stats = {}
	var ps: Dictionary = d.get("player_stats", {})
	for id in ps:
		var s: Dictionary = ps[id]
		player_stats[id] = {"apps": int(s["apps"]), "goals": int(s["goals"]), "assists": int(s["assists"]),
			"rating_sum": float(s["rating_sum"]), "yellows": int(s["yellows"]), "reds": int(s["reds"])}
	user_tactics = Tactics.new()
	user_tactics.load_dict(d.get("user_tactics", {}))
	news = []
	for n in d.get("news", []):
		news.append({"week": int(n["week"]), "text": str(n["text"])})
	history = d.get("history", [])
	_index()


func save(path: String = SAVE_PATH) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## Returns true when the save was read.
func load_from(path: String = SAVE_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != SAVE_VERSION:
		return false
	load_dict(parsed)
	return true
