extends RefCounted
## Match engine. A match is 18 five-minute slices.
##
## Live match screen: call step() on a timer. At half-time the engine waits until
## resume() is called, so the manager can change tactics or make subs.
## AI-only matches: call simulate() to play the whole match at once.
##
## In each slice:
##   1. Midfield strength (plus style and home advantage) decides possession.
##   2. Each side may create a chance: attack vs the other side's defence.
##   3. A chance becomes a goal based on attack vs defence, the shooter, the keeper,
##      and the style matchup (scaled by familiarity and how well the players fit the style).
##   4. Cards, injuries and fatigue are applied.

const Tactics = preload("res://src/sim/tactics.gd")
const Balance = preload("res://src/sim/balance.gd")

const DEFENSIVE_ROLES: Array[String] = ["GK", "CB", "FB", "WB", "DM"]
const SHOOT_WEIGHT := {"ST": 1.0, "WG": 0.65, "AM": 0.6, "CM": 0.3, "WB": 0.15, "DM": 0.12, "FB": 0.12, "CB": 0.1, "GK": 0.0}
const PASS_WEIGHT := {"AM": 1.0, "WG": 0.9, "CM": 0.8, "WB": 0.7, "ST": 0.5, "FB": 0.5, "DM": 0.4, "CB": 0.15, "GK": 0.05}
const CARD_WEIGHT := {"CB": 3.0, "DM": 3.0, "FB": 2.0, "WB": 2.0, "CM": 1.5, "AM": 1.0, "WG": 1.0, "ST": 1.0, "GK": 0.3}


class TeamSide:
	var name: String = ""
	var lineup = null
	var tactics = null
	var ai = null
	var goals: int = 0
	var shots: int = 0
	var on_target: int = 0
	var possession: float = 0.0
	var subs_left: int = 5
	var yellows: Dictionary = {}
	var sent_off: Dictionary = {}
	var injured: Dictionary = {}
	var ratings: Dictionary = {}
	var condition: Dictionary = {}
	var played: Dictionary = {}
	var lines: Dictionary = {"def": 50.0, "mid": 50.0, "att": 50.0, "gk": 50.0}
	var fit: float = 1.0


var home: TeamSide
var away: TeamSide
var rng: RandomNumberGenerator
var slice: int = 0
var finished: bool = false
var waiting_half_time: bool = false
var events: Array = []
var injuries: Array = []

var _cfg: Dictionary
var _rcfg: Dictionary
var _baseline: Array = [1.0, 1.0, 1.0]


func setup(home_name: String, home_lineup, home_tactics, away_name: String, away_lineup, away_tactics, random: RandomNumberGenerator) -> void:
	_cfg = Balance.match_cfg()
	_rcfg = Balance.ratings_cfg()
	rng = random
	_baseline = _coverage_for("4-4-2")
	home = _make_side(home_name, home_lineup, home_tactics)
	away = _make_side(away_name, away_lineup, away_tactics)
	slice = 0
	finished = false
	waiting_half_time = false
	events = []
	injuries = []


func set_ai(side_index: int, ai) -> void:
	_side(side_index).ai = ai


func set_tactics(side_index: int, t) -> void:
	_side(side_index).tactics = t


func resume() -> void:
	waiting_half_time = false


func is_half_time() -> bool:
	return waiting_half_time


func minute() -> int:
	return slice * 5


## Plays the whole match (AI games). Returns the same dictionary as result().
func simulate() -> Dictionary:
	while not finished:
		if waiting_half_time:
			resume()
		step()
	return result()


## Plays one five-minute slice and returns its events.
func step() -> Array:
	if finished or waiting_half_time:
		return []
	var out: Array = []
	_update_lines(home)
	_update_lines(away)
	var share_home := _home_share()
	home.possession += share_home
	away.possession += 1.0 - share_home
	var start_min := slice * 5
	_try_chance(home, away, share_home, start_min, out)
	_try_chance(away, home, 1.0 - share_home, start_min, out)
	for s in [home, away]:
		_discipline(s, start_min, out)
		_injury(s, start_min, out)
		_fatigue(s)
	slice += 1

	var sub_slices: Array = _cfg.get("ai_sub_slices", [])
	if sub_slices.has(slice):
		for s in [home, away]:
			if s.ai != null:
				_ai_subs(s, slice * 5, out)

	out.sort_custom(func(a, b): return a["minute"] < b["minute"])
	if slice == int(_cfg["half_time_slice"]):
		out.append(_event(45, "half_time", "", "Half-time: %s" % score_text()))
		_ai_half_time(home, away, out)
		_ai_half_time(away, home, out)
		waiting_half_time = true
	elif slice >= int(_cfg["slices"]):
		finished = true
		_finish()
		out.append(_event(90, "full_time", "", "Full-time: %s" % score_text()))
	events.append_array(out)
	return out


func score_text() -> String:
	return "%s %d - %d %s" % [home.name, home.goals, away.goals, away.name]


## Substitution for the human manager. Returns true if it happened.
func substitute(side_index: int, out_id: String, in_id: String) -> bool:
	var s := _side(side_index)
	if s.subs_left <= 0:
		return false
	var idx: int = s.lineup.slot_index_of(out_id)
	if idx < 0:
		return false
	var incoming = null
	for p in s.lineup.bench:
		if p.id == in_id:
			incoming = p
	if incoming == null:
		return false
	var out: Array = []
	_sub_in(s, idx, incoming, slice * 5, out, "")
	events.append_array(out)
	return true


func result() -> Dictionary:
	var ratings := {}
	var cond := {}
	for s in [home, away]:
		for id in s.played:
			ratings[id] = s.ratings.get(id, float(_rcfg["start"]))
		for id in s.condition:
			cond[id] = s.condition[id]
	var n: float = maxf(1.0, float(slice))
	return {
		"home_goals": home.goals,
		"away_goals": away.goals,
		"home_shots": home.shots,
		"away_shots": away.shots,
		"home_on_target": home.on_target,
		"away_on_target": away.on_target,
		"home_possession": roundi(home.possession / n * 100.0),
		"ratings": ratings,
		"condition": cond,
		"injuries": injuries,
		"events": events,
	}


# ---------------------------------------------------------------- set-up

func _side(i: int) -> TeamSide:
	return home if i == 0 else away


func _make_side(side_name: String, lineup, tactics) -> TeamSide:
	var s := TeamSide.new()
	s.name = side_name
	s.lineup = lineup
	s.tactics = tactics
	s.subs_left = int(_cfg.get("max_subs", 5))
	for p in lineup.players_on_pitch():
		s.played[p.id] = true
		s.ratings[p.id] = float(_rcfg["start"])
	for p in lineup.players_on_pitch() + lineup.bench:
		s.condition[p.id] = p.fitness
	return s


func _coverage_for(formation: String) -> Array:
	var contrib: Dictionary = Balance.data()["line_contribution"]
	var ws := [0.0, 0.0, 0.0]
	for role in Tactics.FORMATIONS[formation]:
		for i in 3:
			ws[i] += float(contrib[role][i])
	return ws


# ---------------------------------------------------------------- strength

func _active(s: TeamSide) -> Array:
	var out: Array = []
	for slot in s.lineup.slots:
		var p = slot["player"]
		if p != null and not s.sent_off.has(p.id) and not s.injured.has(p.id):
			out.append(slot)
	return out


func _condition_factor(s: TeamSide, p) -> float:
	var c: float = s.condition.get(p.id, p.fitness)
	return (0.8 + 0.2 * c / 100.0) * (0.96 + 0.08 * p.morale / 100.0)


func _update_lines(s: TeamSide) -> void:
	var weights: Dictionary = Balance.data()["role_weights"]
	var contrib: Dictionary = Balance.data()["line_contribution"]
	var fit_w: Dictionary = Tactics.style_cfg(s.tactics.style)["fit"]
	var sums := [0.0, 0.0, 0.0]
	var ws := [0.0, 0.0, 0.0]
	var gk := 30.0
	var attr_sum := 0.0
	var style_sum := 0.0
	var n := 0
	for slot in _active(s):
		var p = slot["player"]
		var role: String = slot["role"]
		var r: float = p.role_rating(role, weights) * Tactics.position_fit(p.position, role) * _condition_factor(s, p)
		if role == "GK":
			gk = r
			continue
		var c: Array = contrib[role]
		for i in 3:
			sums[i] += r * float(c[i])
			ws[i] += float(c[i])
		attr_sum += p.outfield_average()
		style_sum += p.weighted(fit_w)
		n += 1
	var cov_exp: float = _cfg["line_coverage_exponent"]
	var vals := [20.0, 20.0, 20.0]
	for i in 3:
		if ws[i] > 0.0:
			vals[i] = sums[i] / ws[i] * pow(ws[i] / _baseline[i], cov_exp)
	s.lines = {"def": vals[0], "mid": vals[1], "att": vals[2], "gk": gk}
	if n > 0:
		var raw: float = 1.0 + (style_sum - attr_sum) / n / float(_cfg["fit_scale"])
		s.fit = clampf(raw, float(_cfg["fit_min"]), float(_cfg["fit_max"]))


func _home_share() -> float:
	var k: float = _cfg["possession_exponent"]
	var mh: float = home.lines["mid"] * (1.0 + float(_cfg["home_advantage"]))
	var ma: float = away.lines["mid"]
	var share: float = pow(mh, k) / (pow(mh, k) + pow(ma, k))
	share += float(Tactics.style_cfg(home.tactics.style)["possession"])
	share -= float(Tactics.style_cfg(away.tactics.style)["possession"])
	return clampf(share, float(_cfg["possession_min"]), float(_cfg["possession_max"]))


# ---------------------------------------------------------------- chances

func _try_chance(a: TeamSide, b: TeamSide, share: float, start_min: int, out: Array) -> void:
	var ratio: float = a.lines["att"] / maxf(1.0, b.lines["def"])
	var mu: int = Tactics.matchup(a.tactics.style, b.tactics.style)
	# Losing the style matchup hurts less than winning it helps, so a wrong guess is not a disaster.
	var weight: float = 1.0 if mu >= 0 else float(_cfg.get("matchup_loser_share", 0.6))
	var edge: float = mu * weight * a.tactics.familiarity * a.fit
	var sa: Dictionary = Tactics.style_cfg(a.tactics.style)
	var sb: Dictionary = Tactics.style_cfg(b.tactics.style)
	var ma: Dictionary = Tactics.mentality_cfg(a.tactics.mentality)
	var mb: Dictionary = Tactics.mentality_cfg(b.tactics.mentality)

	# Possession helps, but less than one-to-one: counter-attacking sides create from little of the ball.
	var p: float = float(_cfg["chance_rate"]) * pow(share, float(_cfg["share_exponent"])) * pow(ratio, float(_cfg["creation_exponent"]))
	p *= float(sa["creation"]) * float(ma["creation"]) * float(sb["against"]) * float(mb["against"])
	p *= 1.0 + float(_cfg["matchup_creation_bonus"]) * edge
	if a == home:
		p *= 1.0 + float(_cfg["home_creation_bonus"])
	if rng.randf() >= clampf(p, 0.0, 0.95):
		return

	var shooter_slot = _pick(_active(a), func(slot): return float(SHOOT_WEIGHT[slot["role"]]) * pow(slot["player"].attr("shooting") / 70.0, 2.0))
	if shooter_slot == null:
		return
	var shooter = shooter_slot["player"]
	a.shots += 1
	var conv: float = float(_cfg["base_conversion"]) * pow(ratio, float(_cfg["quality_exponent"]))
	conv *= float(sa["quality"]) * (1.0 + float(_cfg["matchup_quality_bonus"]) * edge)
	if a == home:
		conv *= 1.0 + float(_cfg["home_quality_bonus"])
	conv *= pow(shooter.attr("shooting") / 70.0, float(_cfg["shooter_exponent"]))
	conv *= clampf(float(_cfg["gk_base"]) - b.lines["gk"] / float(_cfg["gk_divisor"]), 0.6, 1.4)
	conv = clampf(conv, 0.02, 0.5)

	var minute := start_min + rng.randi_range(1, 5)
	var side_key := "home" if a == home else "away"
	if rng.randf() < conv:
		a.goals += 1
		a.on_target += 1
		_add_rating(a, shooter.id, "goal")
		var text := "GOAL! %s scores for %s." % [shooter.name, a.name]
		var assist_id := ""
		if rng.randf() < float(_cfg["assist_rate"]):
			var others := _active(a).filter(func(slot): return slot["player"] != shooter)
			var assist_slot = _pick(others, func(slot): return float(PASS_WEIGHT[slot["role"]]) * pow(slot["player"].attr("passing") / 70.0, 2.0))
			if assist_slot != null:
				_add_rating(a, assist_slot["player"].id, "assist")
				assist_id = assist_slot["player"].id
				text += " Assist: %s." % assist_slot["player"].name
		for slot in _active(b):
			if DEFENSIVE_ROLES.has(slot["role"]):
				_add_rating(b, slot["player"].id, "conceded")
		var ev := _event(minute, "goal", side_key, text + "  (%d-%d)" % [home.goals, away.goals])
		ev["player"] = shooter.id
		ev["assist"] = assist_id
		out.append(ev)
	elif rng.randf() < float(_cfg["on_target_rate"]):
		a.on_target += 1
		var keeper = _keeper(b)
		if keeper != null:
			_add_rating(b, keeper.id, "save")
		out.append(_event(minute, "chance", side_key, "%s shoots, saved%s." % [shooter.name, (" by " + keeper.name) if keeper != null else ""]))
	else:
		out.append(_event(minute, "chance", side_key, "%s shoots wide." % shooter.name))


# ---------------------------------------------------------------- cards, injuries, fatigue

func _discipline(s: TeamSide, start_min: int, out: Array) -> void:
	var mult: float = Tactics.style_cfg(s.tactics.style)["cards"]
	var side_key := "home" if s == home else "away"
	if rng.randf() < float(_cfg["yellow_per_slice"]) * mult:
		var slot = _pick(_active(s), func(sl): return float(CARD_WEIGHT[sl["role"]]))
		if slot != null:
			var p = slot["player"]
			var minute := start_min + rng.randi_range(1, 5)
			if s.yellows.has(p.id):
				out.append(_event(minute, "red", side_key, "Second yellow! %s (%s) is sent off." % [p.name, s.name], p.id))
				_send_off(s, p, minute, out)
			else:
				s.yellows[p.id] = 1
				_add_rating(s, p.id, "yellow")
				out.append(_event(minute, "yellow", side_key, "Yellow card: %s (%s)." % [p.name, s.name], p.id))
	if rng.randf() < float(_cfg["red_per_slice"]) * mult:
		var slot = _pick(_active(s), func(sl): return float(CARD_WEIGHT[sl["role"]]))
		if slot != null:
			var minute := start_min + rng.randi_range(1, 5)
			out.append(_event(minute, "red", side_key, "Straight red! %s (%s) is sent off." % [slot["player"].name, s.name], slot["player"].id))
			_send_off(s, slot["player"], minute, out)


func _send_off(s: TeamSide, p, minute: int, out: Array) -> void:
	s.sent_off[p.id] = true
	_add_rating(s, p.id, "red")
	# A sent-off keeper is replaced by the bench keeper; an outfielder makes way.
	var idx: int = s.lineup.slot_index_of(p.id)
	if idx >= 0 and s.lineup.slots[idx]["role"] == "GK" and s.subs_left > 0:
		var spare = null
		for b in s.lineup.bench:
			if b.position == "GK":
				spare = b
		if spare != null:
			var outfield := _active(s).filter(func(sl): return sl["role"] != "GK")
			if outfield.size() > 0:
				# The most attacking player (last in formation order) makes way.
				var makes_way = outfield[outfield.size() - 1]
				var way_idx: int = s.lineup.slots.find(makes_way)
				var removed = makes_way["player"]
				s.lineup.slots[way_idx]["player"] = null
				s.lineup.slots[idx]["player"] = spare
				s.lineup.bench.erase(spare)
				s.subs_left -= 1
				s.played[spare.id] = true
				s.ratings[spare.id] = float(_rcfg["start"])
				out.append(_event(minute, "sub", "home" if s == home else "away", "%s comes on in goal for %s." % [spare.name, removed.name]))


func _injury(s: TeamSide, start_min: int, out: Array) -> void:
	if rng.randf() >= float(_cfg["injury_per_slice"]):
		return
	var act := _active(s)
	if act.is_empty():
		return
	var slot = act[rng.randi_range(0, act.size() - 1)]
	var p = slot["player"]
	var minute := start_min + rng.randi_range(1, 5)
	var weeks := rng.randi_range(1, 6)
	s.injured[p.id] = true
	injuries.append({"id": p.id, "weeks": weeks})
	out.append(_event(minute, "injury", "home" if s == home else "away", "%s (%s) is injured, out for about %d week%s." % [p.name, s.name, weeks, "" if weeks == 1 else "s"], p.id))
	# Injured players are always replaced when a sub is left, for both human and AI sides.
	var idx: int = s.lineup.slots.find(slot)
	var best = _best_bench_for(s, slot["role"])
	if best != null and s.subs_left > 0:
		_sub_in(s, idx, best, minute, out, "injury")


func _fatigue(s: TeamSide) -> void:
	var drain: float = float(_cfg["fatigue_per_slice"]) * float(Tactics.style_cfg(s.tactics.style)["fatigue"])
	for slot in _active(s):
		var p = slot["player"]
		var d: float = drain * (1.15 - p.attr("physical") / 200.0)
		if slot["role"] == "GK":
			d *= 0.3
		s.condition[p.id] = maxf(0.0, float(s.condition.get(p.id, p.fitness)) - d)


# ---------------------------------------------------------------- subs and AI

func _best_bench_for(s: TeamSide, role: String):
	var weights: Dictionary = Balance.data()["role_weights"]
	var best = null
	var best_score := -1.0
	for p in s.lineup.bench:
		if role != "GK" and p.position == "GK":
			continue
		var sc: float = p.role_rating(role, weights) * Tactics.position_fit(p.position, role) * (0.8 + 0.2 * float(s.condition.get(p.id, p.fitness)) / 100.0)
		if sc > best_score:
			best_score = sc
			best = p
	return best


func _sub_in(s: TeamSide, idx: int, incoming, minute: int, out: Array, reason: String) -> void:
	var leaving = s.lineup.slots[idx]["player"]
	s.lineup.slots[idx]["player"] = incoming
	s.lineup.bench.erase(incoming)
	s.subs_left -= 1
	s.played[incoming.id] = true
	s.ratings[incoming.id] = float(_rcfg["start"])
	if not s.condition.has(incoming.id):
		s.condition[incoming.id] = incoming.fitness
	var text := "Substitution %s: %s replaces %s." % [s.name, incoming.name, leaving.name if leaving != null else "?"]
	out.append(_event(minute, "sub", "home" if s == home else "away", text))


func _ai_subs(s: TeamSide, minute: int, out: Array) -> void:
	for _i in 2:
		if s.subs_left <= 0:
			return
		var tired = null
		var lowest := 70.0
		for slot in _active(s):
			if slot["role"] == "GK":
				continue
			var c: float = s.condition.get(slot["player"].id, 100.0)
			if c < lowest:
				lowest = c
				tired = slot
		if tired == null:
			return
		var best = _best_bench_for(s, tired["role"])
		if best == null:
			return
		_sub_in(s, s.lineup.slots.find(tired), best, minute, out, "tired")


func _ai_half_time(s: TeamSide, other: TeamSide, out: Array) -> void:
	if s.ai == null:
		return
	var t = s.ai.half_time(s.tactics, s.goals - other.goals, other.tactics.style, rng)
	if not t.same_as(s.tactics):
		s.tactics = t
		out.append(_event(45, "tactics", "home" if s == home else "away", "%s change tactics: %s." % [s.name, t.describe()]))


# ---------------------------------------------------------------- end of match

func _finish() -> void:
	for pair in [[home, away], [away, home]]:
		var s: TeamSide = pair[0]
		var o: TeamSide = pair[1]
		var res_key := ""
		if s.goals > o.goals:
			res_key = "win"
		elif s.goals < o.goals:
			res_key = "loss"
		var on_pitch_ids := {}
		for slot in _active(s):
			on_pitch_ids[slot["player"].id] = slot["role"]
		for id in s.played:
			if res_key != "":
				_add_rating(s, id, res_key)
			if o.goals == 0 and on_pitch_ids.has(id) and DEFENSIVE_ROLES.has(on_pitch_ids[id]):
				_add_rating(s, id, "clean_sheet")
			var noise: float = float(_rcfg["noise"])
			var r: float = float(s.ratings.get(id, _rcfg["start"])) + rng.randf_range(-noise, noise)
			s.ratings[id] = snappedf(clampf(r, 4.0, 10.0), 0.1)


# ---------------------------------------------------------------- helpers

func _add_rating(s: TeamSide, id: String, key: String) -> void:
	s.ratings[id] = float(s.ratings.get(id, _rcfg["start"])) + float(_rcfg[key])


func _keeper(s: TeamSide):
	for slot in _active(s):
		if slot["role"] == "GK":
			return slot["player"]
	return null


func _event(minute: int, type: String, side_key: String, text: String, player_id: String = "") -> Dictionary:
	return {"minute": minute, "type": type, "side": side_key, "player": player_id, "text": text}


## Weighted random pick from items; weight_fn returns each item's weight.
func _pick(items: Array, weight_fn: Callable):
	var total := 0.0
	var ws: Array = []
	for it in items:
		var w: float = maxf(0.0, weight_fn.call(it))
		ws.append(w)
		total += w
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for i in items.size():
		r -= ws[i]
		if r <= 0.0:
			return items[i]
	return items[items.size() - 1]
