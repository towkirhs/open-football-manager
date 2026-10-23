extends SceneTree
## Simulation tests and balance report. Runs without any UI.
##
## Run:  godot --headless --path . -s res://tests/run_tests.gd
## Add  -- --quick  at the end for a faster run (used by the online build).
## The last line says ALL CHECKS PASSED when everything is within range.

const Tactics = preload("res://src/sim/tactics.gd")
const MatchEngine = preload("res://src/sim/match_engine.gd")
const Lineup = preload("res://src/sim/lineup.gd")
const AiManager = preload("res://src/sim/ai_manager.gd")
const Gen = preload("res://src/sim/player_generator.gd")
const Club = preload("res://src/sim/club.gd")
const Season = preload("res://src/sim/season.gd")
const WorldGen = preload("res://src/sim/world_gen.gd")
const Transfers = preload("res://src/sim/transfers.gd")
const QuickSim = preload("res://src/sim/quick_sim.gd")
const Development = preload("res://src/sim/development.gd")
const Economy = preload("res://src/sim/economy.gd")
const CompCup = preload("res://src/sim/comp_cup.gd")
const WorldLoader = preload("res://src/data/world_loader.gd")

const SCRIPTS := ["res://src/sim/match_engine.gd", "res://src/sim/tactics.gd", "res://src/sim/lineup.gd",
	"res://src/sim/ai_manager.gd", "res://src/sim/player_generator.gd", "res://src/sim/season.gd",
	"res://src/sim/fixtures.gd", "res://src/sim/world_gen.gd", "res://src/sim/comp_league.gd",
	"res://src/sim/comp_cup.gd", "res://src/sim/comp_europe.gd", "res://src/sim/quick_sim.gd",
	"res://src/sim/economy.gd", "res://src/sim/development.gd", "res://src/sim/transfers.gd",
	"res://src/data/world_loader.gd",
	"res://src/ui/app.gd", "res://src/ui/ui_theme.gd", "res://src/ui/new_game_screen.gd",
	"res://src/ui/hub_screen.gd", "res://src/ui/match_screen.gd", "res://src/ui/widgets.gd",
	"res://src/ui/portrait.gd", "res://src/ui/player_profile.gd", "res://src/ui/pitch_view.gd",
	"res://src/ui/tabs/home_tab.gd", "res://src/ui/tabs/squad_tab.gd", "res://src/ui/tabs/tactics_tab.gd",
	"res://src/ui/tabs/transfers_tab.gd", "res://src/ui/tabs/club_tab.gd", "res://src/ui/tabs/comps_tab.gd",
	"res://src/ui/tabs/fixtures_tab.gd", "res://src/ui/tabs/settings_tab.gd"]

var failures: int = 0
var quick: bool = false


func _init() -> void:
	quick = OS.get_cmdline_user_args().has("--quick")
	var t0 := Time.get_ticks_msec()
	print("\nScripts")
	var compiled := true
	var sim_only: bool = OS.get_cmdline_user_args().has("--sim-only")
	for path in SCRIPTS:
		if sim_only and path.begins_with("res://src/ui/"):
			continue
		var sc = load(path)
		if sc == null or not sc.can_instantiate():
			print("  could not compile " + path)
			compiled = false
	check(compiled, "all scripts compile")
	if failures > 0:
		quit(1)
		return
	test_matchup_table()
	test_world()
	test_cup_structure()
	test_career()
	test_lineups()
	test_transfers()
	test_development()
	test_quick_sim_matches_engine()
	test_determinism()
	test_league_averages()
	test_tactics_matter()
	test_formation_balance()
	test_long_run()
	print("\nFinished in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		failures += 1


# ---------------------------------------------------------------- helpers

func make_club(id: String, level: float, seed_value: int, bias: Dictionary = {}):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var c = Club.new()
	c.id = id
	c.name = id
	c.players = Gen.make_squad(rng, id, level, bias)
	return c


func make_tactics(formation: String, style: int, mentality: int = Tactics.Mentality.BALANCED, familiarity: float = 0.85):
	var t = Tactics.new()
	t.formation = formation
	t.style = style
	t.mentality = mentality
	t.familiarity = familiarity
	return t


func play(home_club, away_club, ht, at, rng: RandomNumberGenerator, home_ai = null, away_ai = null) -> Dictionary:
	var hl = Lineup.new()
	hl.auto_pick(home_club.players, ht.formation)
	var al = Lineup.new()
	al.auto_pick(away_club.players, at.formation)
	var e = MatchEngine.new()
	e.setup(home_club.name, hl, ht.copy(), away_club.name, al, at.copy(), rng)
	if home_ai != null:
		e.set_ai(0, home_ai)
	if away_ai != null:
		e.set_ai(1, away_ai)
	return e.simulate()


## Win/draw/loss rates for club_a over n games, half at home and half away.
func record(club_a, club_b, ta, tb, n: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var w := 0
	var d := 0
	var goals_for := 0
	var goals_against := 0
	for i in n:
		var a_home := i % 2 == 0
		var r: Dictionary
		var gf: int
		var ga: int
		if a_home:
			r = play(club_a, club_b, ta, tb, rng)
			gf = r["home_goals"]
			ga = r["away_goals"]
		else:
			r = play(club_b, club_a, tb, ta, rng)
			gf = r["away_goals"]
			ga = r["home_goals"]
		goals_for += gf
		goals_against += ga
		if gf > ga:
			w += 1
		elif gf == ga:
			d += 1
	return {"win": float(w) / n, "draw": float(d) / n, "loss": float(n - w - d) / n,
		"gf": float(goals_for) / n, "ga": float(goals_against) / n}


func fmt(r: Dictionary) -> String:
	return "win %4.1f%%  draw %4.1f%%  loss %4.1f%%   goals %.2f - %.2f" % [r["win"] * 100, r["draw"] * 100, r["loss"] * 100, r["gf"], r["ga"]]


func _world(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return WorldGen.make_world(rng)


func _first_division() -> Array:
	return _world(3)["clubs"].filter(func(c): return c.league == "ENG1")


func _lineup_strength(l) -> float:
	var total := 0.0
	for slot in l.slots:
		total += Lineup.role_score(slot["player"], slot["role"])
	return total / l.slots.size()


func _new_career(seed_value: int, league_id: String = "ENG4", index: int = 5):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var world := WorldGen.make_world(rng)
	var mine = world["clubs"].filter(func(c): return c.league == league_id)[index]
	var s = Season.new()
	s.new_game(world, mine.id, rng, "Tester")
	return [s, rng]


# ---------------------------------------------------------------- tests

func test_matchup_table() -> void:
	print("\nStyle matchups")
	var ok := true
	for a in 5:
		var wins := 0
		var losses := 0
		for b in 5:
			var m := Tactics.matchup(a, b)
			if m != -Tactics.matchup(b, a):
				ok = false
			if m == 1:
				wins += 1
			elif m == -1:
				losses += 1
		if wins != 2 or losses != 2:
			ok = false
	check(ok, "each style beats two styles and loses to two, symmetrically")


func test_determinism() -> void:
	print("\nDeterminism")
	var a = make_club("A", 72, 1)
	var b = make_club("B", 70, 2)
	var t = make_tactics("4-4-2", Tactics.Style.POSSESSION)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 99
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	var x := play(a, b, t, t, r1)
	var y := play(a, b, t, t, r2)
	check(x["home_goals"] == y["home_goals"] and x["away_goals"] == y["away_goals"] and x["events"].size() == y["events"].size(),
		"same seed gives the same match")


func test_league_averages() -> void:
	print("\nA first division, %d seasons with AI managers" % (2 if quick else 5))
	var clubs: Array = _first_division()
	check(clubs.size() == 20, "the first division has 20 clubs")
	if clubs.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var managers: Array = []
	for c in clubs:
		var m = AiManager.new()
		m.setup_random(rng)
		managers.append(m)
	var games := 0
	var goals := 0
	var hw := 0
	var dr := 0
	var shots := 0
	var cards := 0
	var injuries := 0
	var table := {}
	for c in clubs:
		table[c.name] = 0
	for _season in (2 if quick else 5):
		for i in clubs.size():
			for j in clubs.size():
				if i == j:
					continue
				var ht = managers[i].pick_tactics(-1, rng)
				var at = managers[j].pick_tactics(ht.style if rng.randf() < 0.5 else -1, rng)
				var r := play(clubs[i], clubs[j], ht, at, rng, managers[i], managers[j])
				games += 1
				goals += r["home_goals"] + r["away_goals"]
				shots += r["home_shots"] + r["away_shots"]
				injuries += r["injuries"].size()
				for ev in r["events"]:
					if ev["type"] == "yellow" or ev["type"] == "red":
						cards += 1
				if r["home_goals"] > r["away_goals"]:
					hw += 1
					table[clubs[i].name] += 3
				elif r["home_goals"] == r["away_goals"]:
					dr += 1
					table[clubs[i].name] += 1
					table[clubs[j].name] += 1
				else:
					table[clubs[j].name] += 3
	var avg_goals := float(goals) / games
	var home_rate := float(hw) / games
	var draw_rate := float(dr) / games
	print("  %d games: %.2f goals/game, %.1f shots/game, %.2f cards/game, %.2f injuries/game" % [games, avg_goals, float(shots) / games, float(cards) / games, float(injuries) / games])
	print("  home wins %.1f%%, draws %.1f%%, away wins %.1f%%" % [home_rate * 100, draw_rate * 100, (1.0 - home_rate - draw_rate) * 100])
	check(avg_goals >= 2.3 and avg_goals <= 3.2, "average goals per game between 2.3 and 3.2")
	check(home_rate >= 0.38 and home_rate <= 0.55, "home win rate between 38% and 55%")
	check(draw_rate >= 0.18 and draw_rate <= 0.33, "draw rate between 18% and 33%")

	# Points over 5 seasons should follow squad strength, but not perfectly.
	var by_strength: Array = clubs.duplicate()
	by_strength.sort_custom(func(a, b): return a.average_overall() > b.average_overall())
	var top5 := 0
	var bottom5 := 0
	for k in 5:
		top5 += table[by_strength[k].name]
		bottom5 += table[by_strength[by_strength.size() - 1 - k].name]
	print("  points over %d seasons: strongest 5 clubs avg %.0f, weakest 5 avg %.0f" % [2 if quick else 5, top5 / 5.0, bottom5 / 5.0])
	check(top5 > bottom5 * 1.4, "stronger squads earn clearly more points")


func test_tactics_matter() -> void:
	print("\nUnderdog vs favourite (8 overall points apart)")
	var strong = make_club("Favourite", 76, 11)
	var weak = make_club("Underdog", 68, 12)
	print("  favourite avg overall %.1f, underdog %.1f" % [strong.average_overall(), weak.average_overall()])
	var fav_t = make_tactics("4-3-3", Tactics.Style.POSSESSION)
	var n := 2000 if quick else 4000
	var same := record(weak, strong, make_tactics("4-3-3", Tactics.Style.POSSESSION), fav_t, n, 21)
	var counter := record(weak, strong, make_tactics("4-3-3", Tactics.Style.COUNTER), fav_t, n, 22)
	var press := record(weak, strong, make_tactics("4-3-3", Tactics.Style.HIGH_PRESS), fav_t, n, 23)
	var wrong := record(weak, strong, make_tactics("4-3-3", Tactics.Style.LONG_BALL), fav_t, n, 24)
	print("  underdog, same style (possession):   " + fmt(same))
	print("  underdog, counter-attack (beats it): " + fmt(counter))
	print("  underdog, high press (beats it):     " + fmt(press))
	print("  underdog, long ball (loses to it):   " + fmt(wrong))
	check(counter["win"] > same["win"] and same["win"] > wrong["win"], "right tactic > same tactic > wrong tactic")
	check(counter["win"] >= 0.25 and counter["win"] <= 0.35, "underdog with the right tactic wins 25-35%")
	check(same["win"] < 0.22, "underdog with no tactical edge wins under 22%")

	var fit_weak = make_club("Fast underdog", 68, 12, {"pace": 4, "shooting": 2})
	var fitted := record(fit_weak, strong, make_tactics("4-3-3", Tactics.Style.COUNTER, Tactics.Mentality.BALANCED, 1.0), fav_t, n, 25)
	print("  pacey underdog, well-drilled counter: " + fmt(fitted))
	check(fitted["win"] > counter["win"], "players who suit the style and full familiarity add to the edge")


func test_formation_balance() -> void:
	print("\nFormations (equal squads, same style, vs 4-4-2)")
	var a = make_club("A", 72, 31)
	var b = make_club("B", 72, 31)
	var base = make_tactics("4-4-2", Tactics.Style.POSSESSION)
	var ok := true
	for f in Tactics.formation_names():
		var r := record(a, b, make_tactics(f, Tactics.Style.POSSESSION), base, 800 if quick else 2000, 40 + f.length())
		print("  %-8s %s" % [f, fmt(r)])
		if r["win"] < 0.25 or r["win"] > 0.52:
			ok = false
	check(ok, "no formation is broken against 4-4-2 (win rate 25-52%)")


func test_world() -> void:
	print("\nThe generated world")
	var w := _world(1)
	var clubs: Array = w["clubs"]
	var count := func(lid): return clubs.filter(func(c): return c.league == lid).size()
	check(count.call("ENG1") == 20 and count.call("ENG2") == 24 and count.call("ENG3") == 24 and count.call("ENG4") == 24, "England has four divisions (20, 24, 24, 24)")
	check(count.call("ESP1") == 20 and count.call("ESP2") == 22, "Spain has two divisions (20, 22)")
	check(count.call("GER1") == 18 and count.call("GER2") == 18 and count.call("GER3") == 20, "Germany has three divisions (18, 18, 20)")
	var foreign: Array = clubs.filter(func(c): return c.league == "")
	check(foreign.size() >= 75, "enough foreign clubs to fill three European cups (%d)" % foreign.size())
	var names := {}
	var dup := false
	for c in clubs:
		if names.has(c.name):
			dup = true
		names[c.name] = true
	check(not dup, "every club name is unique")
	var avg := func(lid):
		var cs: Array = clubs.filter(func(c): return c.league == lid)
		return cs.reduce(func(a, c): return a + c.average_overall(), 0.0) / cs.size()
	print("  average squad: ENG1 %.1f, ENG2 %.1f, ENG3 %.1f, ENG4 %.1f" % [avg.call("ENG1"), avg.call("ENG2"), avg.call("ENG3"), avg.call("ENG4")])
	check(avg.call("ENG1") > avg.call("ENG2") and avg.call("ENG2") > avg.call("ENG3") and avg.call("ENG3") > avg.call("ENG4"), "higher divisions have stronger squads")
	# A world written to a file and read back is the same.
	var path := "user://test_world.json"
	WorldLoader.save_world(path, w)
	var back := WorldLoader.load_world(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not back.has("error") and back["clubs"].size() == clubs.size(), "a world file saves and loads")


func test_cup_structure() -> void:
	print("\nKnockout cups")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for n in [92, 42, 56, 32]:
		var ids: Array = []
		for i in n:
			ids.append("c%d" % i)
		var cup = CompCup.new()
		cup.setup({"id": "T", "name": "Test"}, ids, rng)
		var r := 0
		while not cup.is_complete() and r < 10:
			var res: Array = []
			for f in cup.fixtures(r):
				res.append({"home": f["home"], "away": f["away"], "hg": 1, "ag": 0, "winner": f["home"]})
			cup.record(r, res, rng)
			r += 1
		check(cup.is_complete() and r == cup.round_count(), "a %d-club cup finishes in %d rounds" % [n, cup.round_count()])


func test_career() -> void:
	print("\nA career season (all competitions)")
	var pair: Array = _new_career(11)
	var s = pair[0]
	var rng: RandomNumberGenerator = pair[1]
	check(s.comps.size() == 15, "15 competitions: 9 leagues, 3 cups, 3 European cups (%d)" % s.comps.size())
	check(s.calendar.size() > 46, "the calendar has league weeks plus cup and European days (%d days)" % s.calendar.size())
	var cash_start := {}
	for c in s.clubs:
		cash_start[c.id] = c.cash
	s.advance_to_next_match(rng)
	var e = s.prepare_user_match(rng)
	check(e != null, "the human's first match is ready")
	var paused := false
	while not e.finished:
		e.step()
		if e.is_half_time():
			paused = true
			e.resume()
	s.play_day(rng, e)
	check(paused and s.user_results.size() == 1, "the human's live match pauses at half-time and is recorded")
	var path := "user://test_career.json"
	check(s.save(path) == OK, "career saves")
	var loaded = Season.new()
	check(loaded.load_from(path), "career loads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(loaded.day == s.day and loaded.user_league().standings() == s.user_league().standings() and loaded.clubs.size() == s.clubs.size(), "the loaded career matches the saved one")
	var t0 := Time.get_ticks_msec()
	while not s.is_finished():
		s.play_day(rng)
	print("  season played in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var all_done := true
	var points_ok := true
	for id in s.comps:
		var k = s.comps[id]
		if not k.is_complete():
			all_done = false
			print("  not finished: " + k.name)
		if k.kind == "league":
			var n: int = k.clubs.size()
			for cid in k.table:
				var t: Array = k.table[cid]
				if t[0] != 2 * (n - 1) or t[6] != 3 * t[1] + t[2]:
					points_ok = false
	check(all_done, "every league, cup and European competition finishes")
	check(points_ok, "every club plays each league rival twice and the points add up")
	check(s.season_over and s.season_summary["promoted"].size() == 19 and s.season_summary["relegated"].size() == 19, "19 clubs go up and 19 go down")
	check(s.awards.size() >= 9 * 3, "awards are given in every league (%d)" % s.awards.size())
	# Money by division
	var ok_money := true
	for lid in ["ENG1", "ENG4", "ESP1", "GER3"]:
		var cs: Array = s.clubs.filter(func(c): return c.league == lid)
		var wages: Array = cs.map(func(c): return -int(c.ledger.get("wages", 0)))
		var income: Array = cs.map(func(c): return int(c.ledger.get("gate", 0)) + int(c.ledger.get("tv", 0)) + int(c.ledger.get("sponsor", 0)) + int(c.ledger.get("prize", 0)))
		wages.sort()
		income.sort()
		var ratio: float = float(wages[wages.size() / 2]) / maxf(1.0, float(income[income.size() / 2]))
		var in_debt: int = cs.filter(func(c): return c.cash < 0).size()
		print("  %s: median wages %.1fM, median income %.1fM (%.0f%%), %d clubs in debt" % [lid, wages[wages.size() / 2] / 1e6, income[income.size() / 2] / 1e6, ratio * 100.0, in_debt])
		if ratio < 0.35 or ratio > 1.1 or in_debt > cs.size() / 4:
			ok_money = false
	check(ok_money, "wages take a sensible share of income in every division, and few clubs go into debt")
	var user_league_id: String = s.user_club().league
	s.next_season(rng)
	var sizes_ok := true
	for def in s.league_defs:
		var expected: int = {"ENG1": 20, "ENG2": 24, "ENG3": 24, "ENG4": 24, "ESP1": 20, "ESP2": 22, "GER1": 18, "GER2": 18, "GER3": 20}[def["id"]]
		if s.clubs.filter(func(c): return c.league == def["id"]).size() != expected:
			sizes_ok = false
	check(sizes_ok, "division sizes stay the same after promotion and relegation")
	check(s.year == 2027 and s.day == 0 and not s.season_over and s.comps.size() == 15, "the next season starts with all competitions")
	var squads: Array = s.clubs.filter(func(c): return c.id != s.user_club_id).map(func(c): return c.players.size())
	squads.sort()
	check(squads[0] >= 18, "AI squads stay large enough (smallest %d)" % squads[0])
	check(user_league_id != "", "the human's club had a league")


func test_lineups() -> void:
	print("\nPicking your own team")
	var pair: Array = _new_career(8, "ENG2", 3)
	var season = pair[0]
	var rng: RandomNumberGenerator = pair[1]
	var club = season.user_club()
	check(Tactics.LAYOUT.size() == Tactics.FORMATIONS.size(), "every formation has pitch positions")
	var layout_ok := true
	for f in Tactics.FORMATIONS:
		if Tactics.LAYOUT[f].size() != 11:
			layout_ok = false
	check(layout_ok, "each layout has 11 positions")
	var auto = season.user_lineup()
	var picked = Lineup.new()
	picked.from_ids(club.players, "4-4-2", auto.slot_ids(), auto.bench_ids())
	var bench_star = auto.bench[0]
	var striker_slot := 9
	var benched_id: String = picked.slots[striker_slot]["player"].id
	var ids: Array = picked.slot_ids()
	ids[striker_slot] = bench_star.id
	picked.from_ids(club.players, "4-4-2", ids, [benched_id])
	season.set_user_selection(picked)
	var used = season.user_lineup()
	check(not season.user_auto_pick and used.slots[striker_slot]["player"].id == bench_star.id, "your chosen player starts")
	check(used.bench[0].id == benched_id, "your chosen bench is kept")
	bench_star.injury_weeks = 2
	used = season.user_lineup()
	check(used.slots[striker_slot]["player"].id != bench_star.id and used.slot_ids().size() == 11, "an injured pick is replaced")
	var kept := 0
	for i in 11:
		if i != striker_slot and used.slots[i]["player"].id == ids[i]:
			kept += 1
	check(kept == 10, "the other ten picks are unchanged")
	bench_star.injury_weeks = 0
	var before_l = season.user_lineup()
	var before: Array = before_l.players_on_pitch().map(func(p): return p.id)
	var before_score := _lineup_strength(before_l)
	season.set_user_formation("3-5-2")
	var after_l = season.user_lineup()
	var after: Array = after_l.players_on_pitch().map(func(p): return p.id)
	var stayed := after.filter(func(id): return before.has(id)).size()
	print("  4-4-2 to 3-5-2: %d of 11 kept, average role fit %.1f -> %.1f" % [stayed, before_score, _lineup_strength(after_l)])
	check(after_l.formation == "3-5-2" and after.size() == 11 and stayed >= 7, "changing formation keeps most of your team")
	check(_lineup_strength(after_l) >= before_score - 4.0, "nobody is badly out of position after the change")
	after.sort()
	season.advance_to_next_match(rng)
	var e = season.prepare_user_match(rng)
	var f: Dictionary = season.today_user_fixture()["fixture"]
	var side = e.home if f["home"] == season.user_club_id else e.away
	var in_match: Array = side.lineup.players_on_pitch().map(func(p): return p.id)
	in_match.sort()
	check(in_match == after, "matches use your chosen eleven")


func test_transfers() -> void:
	print("\nTransfers and contracts")
	var pair: Array = _new_career(21, "ENG3", 2)
	var s = pair[0]
	var rng: RandomNumberGenerator = pair[1]
	var uc = s.user_club()
	uc.cash = 50000000
	check(s.window_open(), "the transfer window is open in pre-season")
	# A target from a smaller club.
	var targets: Array = s.clubs.filter(func(c): return c.league == "ENG4")[0].players.duplicate()
	targets.sort_custom(func(a, b): return a.overall > b.overall)
	var p = targets[0]
	var seller_id: String = s.club_of(p.id)
	var low: Dictionary = s.bid(p, 1000)
	check(low["answer"] == "reject", "a silly bid is rejected")
	var ask: int = int(low["fee"])
	var ok_bid: Dictionary = s.bid(p, ask)
	check(ok_bid["answer"] == "accept", "a bid at the asking price is accepted")
	var cheap: Dictionary = s.offer_contract(p, ask, 100, 3)
	check(cheap["answer"] != "accept", "a tiny wage offer is refused")
	var cash_before: int = uc.cash
	var deal: Dictionary = s.offer_contract(p, ask, int(cheap["wage"]), 3)
	check(deal["answer"] == "accept" and s.club_of(p.id) == uc.id and uc.cash == cash_before - ask, "the player joins and the fee is paid")
	check(s.club(seller_id).players.find(p) == -1, "the seller no longer has him")
	# Search
	var found: Array = s.search_players({"position": "ST", "min_ovr": 70, "exclude_club": uc.id})
	var all_st := true
	for r in found:
		if r["player"].position != "ST" or r["player"].overall < 70:
			all_st = false
	check(not found.is_empty() and all_st, "search filters by position and overall (%d strikers 70+)" % found.size())
	# Renewal and release
	var mine = uc.players[0]
	var old_end: int = mine.contract_end
	var demand: Dictionary = s.renew(mine, 1, 2)
	var renewed: Dictionary = s.renew(mine, int(demand["wage"]), 2)
	check(renewed["answer"] == "accept" and mine.contract_end == s.year + 2, "a contract renewal at the asked wage is accepted (was until %d)" % old_end)
	var spare = uc.players[uc.players.size() - 1]
	s.release_player(spare)
	check(s.free_agents.has(spare) and s.club_of(spare.id) == "", "a released player becomes a free agent")
	# AI clubs do business in the window.
	var moved := 0
	var before := {}
	for c in s.clubs:
		for pl in c.players:
			before[pl.id] = c.id
	for _d in 6:
		s.play_day(rng)
	for c in s.clubs:
		for pl in c.players:
			if before.has(pl.id) and before[pl.id] != c.id:
				moved += 1
	print("  %d players changed club in the first days of the window" % moved)
	check(moved > 5, "AI clubs buy and sell players")


func test_development() -> void:
	print("\nTraining and ageing")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var young = Club.new()
	young.id = "Y"
	young.staff = {"head_coach": {"name": "", "skill": 70, "wage": 0, "end": 2030}}
	young.facilities = {"stadium": 1, "training": 3, "youth": 1, "medical": 1, "scouting": 1}
	var old = Club.new()
	old.id = "O"
	old.staff = young.staff
	old.facilities = young.facilities
	for i in 60:
		young.players.append(Gen.make_player(rng, "y%d" % i, "CM", 55.0, {}, "", 2026, 18))
		old.players.append(Gen.make_player(rng, "o%d" % i, "CM", 70.0, {}, "", 2026, 33))
	var y0: float = young.players.reduce(func(a, p): return a + p.overall, 0.0) / 60.0
	var o0: float = old.players.reduce(func(a, p): return a + p.overall, 0.0) / 60.0
	for _w in 46:
		Development.train_club(young, rng)
		Development.train_club(old, rng)
	var y1: float = young.players.reduce(func(a, p): return a + p.overall, 0.0) / 60.0
	var o1: float = old.players.reduce(func(a, p): return a + p.overall, 0.0) / 60.0
	print("  18-year-olds: %.1f -> %.1f in a season; 33-year-olds: %.1f -> %.1f" % [y0, y1, o0, o1])
	check(y1 - y0 >= 2.0 and y1 - y0 <= 9.0, "young players improve by a few points a season")
	check(o1 < o0, "veterans decline")
	var club = Club.new()
	club.id = "A"
	club.country = "ENG"
	club.facilities = {"stadium": 1, "training": 1, "youth": 5, "medical": 1, "scouting": 1}
	var good: Array = Development.youth_intake(club, 70.0, 2026, rng)
	club.facilities["youth"] = 1
	var poor: Array = Development.youth_intake(club, 70.0, 2026, rng)
	var avg_pot := func(arr): return arr.reduce(func(a, p): return a + p.potential, 0.0) / arr.size()
	print("  youth intake: level 5 academy %d prospects (potential %.0f), level 1 academy %d (%.0f)" % [good.size(), avg_pot.call(good), poor.size(), avg_pot.call(poor)])
	check(good.size() >= poor.size() and avg_pot.call(good) > avg_pot.call(poor), "a better academy brings more and better prospects")


func test_quick_sim_matches_engine() -> void:
	print("\nFast results agree with the full engine")
	var strong = make_club("Strong", 76, 61)
	var weak = make_club("Weak", 68, 62)
	var t = make_tactics("4-4-2", Tactics.Style.POSSESSION)
	var n := 1500 if quick else 3000
	var eng := record(strong, weak, t, t, n, 63)
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	var sl = Lineup.new()
	sl.auto_pick(strong.players, "4-4-2")
	var wl = Lineup.new()
	wl.auto_pick(weak.players, "4-4-2")
	var ss: float = _lineup_strength(sl)
	var ws: float = _lineup_strength(wl)
	var w := 0
	var goals := 0
	for i in n:
		var r: Dictionary
		if i % 2 == 0:
			r = QuickSim.play(sl.slots, wl.slots, ss, ws, rng)
			w += 1 if r["home_goals"] > r["away_goals"] else 0
		else:
			r = QuickSim.play(wl.slots, sl.slots, ws, ss, rng)
			w += 1 if r["away_goals"] > r["home_goals"] else 0
		goals += r["home_goals"] + r["away_goals"]
	var qw := float(w) / n
	print("  favourite wins: engine %.1f%%, fast model %.1f%%; goals per game engine %.2f, fast %.2f" % [eng["win"] * 100, qw * 100, eng["gf"] + eng["ga"], float(goals) / n])
	check(absf(qw - eng["win"]) < 0.1, "the fast model's favourite win rate is within 10 points of the engine's")


# ---------------------------------------------------------------- long run

func _league_level(season, lid: String) -> float:
	var cs: Array = season.clubs.filter(func(c): return c.league == lid)
	return cs.reduce(func(a, c): return a + c.average_overall(), 0.0) / cs.size()


## Several seasons back to back: squads, ratings and money must stay in sensible ranges.
func test_long_run() -> void:
	var seasons := 2 if quick else 4
	print("\nA whole world over %d seasons" % seasons)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var w := WorldGen.make_world(rng)
	var s = Season.new()
	s.new_game(w, w["clubs"].filter(func(c): return c.league == "ENG4")[0].id, rng, "Test")
	var start := {}
	for lid in ["ENG1", "ENG2", "ENG3", "ENG4"]:
		start[lid] = _league_level(s, lid)
	var players0 := 0
	for c in s.clubs:
		players0 += c.players.size()
	for _i in seasons:
		while not s.is_finished():
			s.play_day(rng)
		if s.sacked:
			s.accept_job(s.job_offers[0]["club"], rng)
		s.next_season(rng)
	var sizes: Array = s.clubs.filter(func(c): return c.id != s.user_club_id).map(func(c): return c.players.size())
	sizes.sort()
	print("  AI squad sizes %d to %d, your squad %d" % [sizes[0], sizes[-1], s.user_club().players.size()])
	check(sizes[0] >= Transfers.MIN_SQUAD and sizes[-1] <= Transfers.MAX_SQUAD, "AI squads stay between %d and %d players" % [Transfers.MIN_SQUAD, Transfers.MAX_SQUAD])
	check(s.user_club().players.size() >= 16, "your squad never drops below 16 players")
	var drift_ok := true
	for lid in start:
		var now: float = _league_level(s, lid)
		print("  %s level %.1f -> %.1f" % [lid, start[lid], now])
		if absf(now - start[lid]) > 2.0 * seasons + 1.0:
			drift_ok = false
	check(drift_ok, "league levels stay close to where they started")
	var players1 := 0
	var young := 0
	var goalkeepers_ok := true
	for c in s.clubs:
		players1 += c.players.size()
		young += c.players.filter(func(p): return p.age <= 21).size()
		if c.players.filter(func(p): return p.position == "GK").size() < 1:
			goalkeepers_ok = false
	print("  players %d -> %d, %.0f%% aged 21 or under" % [players0, players1, young * 100.0 / players1])
	check(absf(players1 - players0) < players0 * 0.1, "the number of players stays steady")
	check(young * 1.0 / players1 > 0.03 and young * 1.0 / players1 < 0.35, "a healthy share of young players")
	check(goalkeepers_ok, "every club has a goalkeeper")
	var cash: Array = s.clubs.filter(func(c): return c.league == "ENG1").map(func(c): return c.cash)
	cash.sort()
	print("  first-division median cash %s" % Season._money(cash[cash.size() / 2]))
	check(cash[cash.size() / 2] < 150000000, "top clubs do not pile up endless cash")
	var copy = Season.new()
	copy.load_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(copy.to_dict().hash() == s.to_dict().hash() or JSON.stringify(copy.to_dict()) == JSON.stringify(s.to_dict()), "a long career saves and loads unchanged")
