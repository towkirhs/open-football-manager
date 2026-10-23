extends SceneTree
## Simulation tests and balance report. Runs without any UI.
##
## Run:  godot --headless --path . -s res://tests/run_tests.gd
## Exit code is 0 when every check passes.

const Tactics = preload("res://src/sim/tactics.gd")
const MatchEngine = preload("res://src/sim/match_engine.gd")
const Lineup = preload("res://src/sim/lineup.gd")
const AiManager = preload("res://src/sim/ai_manager.gd")
const Gen = preload("res://src/sim/player_generator.gd")
const Club = preload("res://src/sim/club.gd")
const WorldLoader = preload("res://src/data/world_loader.gd")
const Season = preload("res://src/sim/season.gd")

const SAMPLE := "res://data/sample/sample_league.json"
const UI_SCRIPTS := ["res://src/ui/app.gd", "res://src/ui/ui_theme.gd", "res://src/ui/new_game_screen.gd",
	"res://src/ui/hub_screen.gd", "res://src/ui/match_screen.gd", "res://src/ui/widgets.gd",
	"res://src/ui/portrait.gd", "res://src/ui/player_profile.gd", "res://src/ui/pitch_view.gd"]

var failures: int = 0
## --quick plays fewer games (used by the online build). Pass it after "--".
var quick: bool = false


func _init() -> void:
	quick = OS.get_cmdline_user_args().has("--quick")
	var t0 := Time.get_ticks_msec()
	print("\nScripts")
	var compiled := true
	for path in ["res://src/sim/match_engine.gd", "res://src/sim/tactics.gd", "res://src/sim/lineup.gd",
			"res://src/sim/ai_manager.gd", "res://src/sim/player_generator.gd", "res://src/sim/season.gd",
			"res://src/sim/fixtures.gd", "res://src/sim/lineup.gd"] + UI_SCRIPTS:
		var s = load(path)
		if s == null or not s.can_instantiate():
			print("  could not compile " + path)
			compiled = false
	check(compiled, "all scripts compile")
	if failures > 0:
		quit(1)
		return
	test_matchup_table()
	test_season()
	test_lineups()
	test_determinism()
	test_league_averages()
	test_tactics_matter()
	test_formation_balance()
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
	print("\nSample league, %d seasons with AI managers" % (2 if quick else 5))
	var clubs: Array = WorldLoader.load_league(SAMPLE)["clubs"]
	check(clubs.size() == 20, "sample league has 20 clubs")
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


func test_season() -> void:
	print("\nA full season")
	var league := WorldLoader.load_league(SAMPLE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var season = Season.new()
	var user_id: String = league["clubs"][0].id
	season.new_game(league, user_id, rng)
	check(season.total_weeks() == 38, "20 clubs play a 38-week season")

	# Week 1: watch the human's game live, with a half-time pause.
	var e = season.prepare_user_match(rng)
	var paused := false
	while not e.finished:
		e.step()
		if e.is_half_time():
			paused = true
			e.resume()
	season.play_week(rng, e)
	check(paused, "live match pauses at half-time")
	check(not season.user_result(0).is_empty(), "the human's live result is recorded")

	# Save mid-season and load into a fresh career.
	var path := "user://test_career.json"
	check(season.save(path) == OK, "career saves")
	var loaded = Season.new()
	check(loaded.load_from(path), "career loads")
	check(loaded.standings() == season.standings() and loaded.week == season.week, "loaded career matches the saved one")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	while not season.is_finished():
		season.play_week(rng)
	var games := 0
	for wk in season.results:
		games += wk.size()
	check(games == 380, "380 games played")
	var ok := true
	var home_games := {}
	var total_gf := 0
	var total_ga := 0
	for wk in season.results:
		for r in wk:
			home_games[r["home"]] = home_games.get(r["home"], 0) + 1
	for id in season.table:
		var t: Dictionary = season.table[id]
		total_gf += t["gf"]
		total_ga += t["ga"]
		if t["p"] != 38 or t["w"] + t["d"] + t["l"] != 38 or t["pts"] != 3 * t["w"] + t["d"] or home_games.get(id, 0) != 19:
			ok = false
	check(ok, "every club plays 38 (19 at home) and the points add up")
	var longest := 0
	for c in league["clubs"]:
		var run := 0
		var prev := ""
		for w in season.total_weeks():
			for m in season.fixtures[w]:
				if m[0] == c.id or m[1] == c.id:
					var v := "H" if m[0] == c.id else "A"
					run = run + 1 if v == prev else 1
					prev = v
					longest = maxi(longest, run)
	print("  longest run of home or away games: %d" % longest)
	check(longest <= 3, "no club plays more than 3 home or 3 away games in a row")
	check(total_gf == total_ga, "goals for and against balance across the league")
	var order: Array = season.standings()
	var top = season.club(order[0])
	var bottom = season.club(order[order.size() - 1])
	print("  champions %s (%d pts, squad %.1f), bottom %s (%d pts, squad %.1f)" % [top.name, season.table[order[0]]["pts"], top.average_overall(), bottom.name, season.table[order[order.size() - 1]]["pts"], bottom.average_overall()])
	var scorers: Array = season.top_scorers(3)
	if not scorers.is_empty():
		print("  top scorer %s (%s) %d goals" % [scorers[0]["name"], scorers[0]["club"], scorers[0]["goals"]])
	check(season.history.size() == 1, "season end is recorded in the club history")
	season.next_season(rng)
	check(season.week == 0 and season.table[user_id]["pts"] == 0 and season.total_weeks() == 38, "next season starts fresh")


func test_lineups() -> void:
	print("\nPicking your own team")
	var league := WorldLoader.load_league(SAMPLE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var season = Season.new()
	season.new_game(league, league["clubs"][3].id, rng)
	var club = season.user_club()
	check(Tactics.LAYOUT.size() == Tactics.FORMATIONS.size(), "every formation has pitch positions")
	var layout_ok := true
	for f in Tactics.FORMATIONS:
		if Tactics.LAYOUT[f].size() != 11:
			layout_ok = false
	check(layout_ok, "each layout has 11 positions")

	# Pick a deliberately odd team: the weakest outfielders up front.
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

	# An injured pick is replaced, the rest of the team stays.
	bench_star.injury_weeks = 2
	used = season.user_lineup()
	check(used.slots[striker_slot]["player"].id != bench_star.id and used.slot_ids().size() == 11, "an injured pick is replaced")
	var kept := 0
	for i in 11:
		if i != striker_slot and used.slots[i]["player"].id == ids[i]:
			kept += 1
	check(kept == 10, "the other ten picks are unchanged")
	bench_star.injury_weeks = 0

	# Formation change keeps most of the team, but brings in specialists where needed.
	var before_l = season.user_lineup()
	var before: Array = before_l.players_on_pitch().map(func(p): return p.id)
	var before_score := _lineup_strength(before_l)
	season.set_user_formation("3-5-2")
	var after_l = season.user_lineup()
	var after: Array = after_l.players_on_pitch().map(func(p): return p.id)
	var stayed := after.filter(func(id): return before.has(id)).size()
	print("  4-4-2 to 3-5-2: %d of 11 kept, average role fit %.1f -> %.1f" % [stayed, before_score, _lineup_strength(after_l)])
	check(after_l.formation == "3-5-2" and after.size() == 11 and stayed >= 8, "changing formation keeps most of your team")
	check(_lineup_strength(after_l) >= before_score - 4.0, "nobody is badly out of position after the change")
	after.sort()

	# The match uses your team.
	var e = season.prepare_user_match(rng)
	var side = e.home if season.user_fixture()["user_home"] else e.away
	var in_match: Array = side.lineup.players_on_pitch().map(func(p): return p.id)
	in_match.sort()
	check(in_match == after, "matches use your chosen eleven")

	# Saved and loaded.
	var path := "user://test_lineup.json"
	season.save(path)
	var loaded = Season.new()
	loaded.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not loaded.user_auto_pick and loaded.user_lineup().slot_ids() == season.user_lineup().slot_ids(), "your team is saved with the career")


func _lineup_strength(l) -> float:
	var total := 0.0
	for slot in l.slots:
		total += Lineup.role_score(slot["player"], slot["role"])
	return total / l.slots.size()
