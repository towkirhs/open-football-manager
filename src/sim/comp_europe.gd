extends RefCounted
## A European cup for 32 clubs: 8 groups of 4 (home and away), the top two of each
## group go into the last 16. Knockout ties have two legs (aggregate score, then
## penalties); the final is a single match.
##
## Rounds: 0-5 group matchdays, 6-7 last 16, 8-9 quarter-finals, 10-11 semi-finals, 12 final.

const GROUP_ROUNDS := 6
const KO_NAMES := ["Last 16", "Quarter-finals", "Semi-finals"]
## Matchday pairs for a group of four [a, b, c, d] (indexes), home team first.
const GROUP_SCHEDULE := [[[0, 1], [2, 3]], [[3, 0], [1, 2]], [[0, 2], [3, 1]], [[1, 0], [3, 2]], [[0, 3], [2, 1]], [[2, 0], [1, 3]]]

var kind: String = "europe"
var id: String = ""
var name: String = ""
var clubs: Array = []
var groups: Array = []
## Group tables: club_id -> [p, w, d, l, gf, ga, pts]
var table: Dictionary = {}
## Results per round: [[home, away, hg, ag, winner], ...]
var results: Array = []
## Knockout ties per stage: [[a, b], ...]; a is at home in the first leg.
var ko: Array = []
var final_tie: Array = []
var winner: String = ""


## club_ids should be ordered strongest first (they are drawn from four pots).
func setup(def: Dictionary, club_ids: Array, rng: RandomNumberGenerator, country_of: Dictionary = {}) -> void:
	id = def["id"]
	name = def["name"]
	clubs = club_ids.duplicate()
	results = []
	ko = []
	final_tie = []
	winner = ""
	table = {}
	for c in clubs:
		table[c] = [0, 0, 0, 0, 0, 0, 0]
	var n_groups: int = clubs.size() / 4
	groups = []
	for _g in n_groups:
		groups.append([])
	for pot in 4:
		var pot_clubs: Array = clubs.slice(pot * n_groups, (pot + 1) * n_groups)
		_shuffle(pot_clubs, rng)
		# Try to keep clubs from the same country apart.
		for c in pot_clubs:
			var best := -1
			for g in n_groups:
				if groups[g].size() != pot:
					continue
				var clash := false
				for other in groups[g]:
					if country_of.get(other, "?") == country_of.get(c, "!"):
						clash = true
				if not clash:
					best = g
					break
			if best < 0:
				for g in n_groups:
					if groups[g].size() == pot:
						best = g
						break
			groups[best].append(c)


func round_count() -> int:
	return GROUP_ROUNDS + 7


func round_name(r: int) -> String:
	if r < GROUP_ROUNDS:
		return "Group matchday %d" % (r + 1)
	if r == GROUP_ROUNDS + 6:
		return "Final"
	var stage: int = (r - GROUP_ROUNDS) / 2
	return "%s, %s leg" % [KO_NAMES[stage], "first" if (r - GROUP_ROUNDS) % 2 == 0 else "second"]


func fixtures(r: int) -> Array:
	if r < GROUP_ROUNDS:
		var out: Array = []
		for g in groups:
			if g.size() < 4:
				continue
			for pair in GROUP_SCHEDULE[r]:
				out.append({"home": g[pair[0]], "away": g[pair[1]], "decisive": false})
		return out
	if r == GROUP_ROUNDS + 6:
		if final_tie.is_empty():
			return []
		return [{"home": final_tie[0], "away": final_tie[1], "decisive": true, "neutral": true}]
	var stage: int = (r - GROUP_ROUNDS) / 2
	if stage >= ko.size():
		return []
	var second: bool = (r - GROUP_ROUNDS) % 2 == 1
	var out2: Array = []
	for t in ko[stage]:
		if second:
			var first := _leg_result(r - 1, t[0], t[1])
			out2.append({"home": t[1], "away": t[0], "decisive": true, "first_leg": first})
		else:
			out2.append({"home": t[0], "away": t[1], "decisive": false})
	return out2


func _leg_result(r: int, home: String, away: String) -> Array:
	if r < results.size():
		for x in results[r]:
			if x[0] == home and x[1] == away:
				return [x[2], x[3]]
	return [0, 0]


## Winner of a deciding match, or "" when level (penalties decide).
func decide(f: Dictionary, hg: int, ag: int) -> String:
	if not f.get("decisive", false):
		return ""
	var h_total := hg
	var a_total := ag
	if f.has("first_leg"):
		# In the second leg the home side was away in the first leg.
		h_total += int(f["first_leg"][1])
		a_total += int(f["first_leg"][0])
	if h_total > a_total:
		return f["home"]
	if a_total > h_total:
		return f["away"]
	return ""


func record(r: int, res: Array, rng: RandomNumberGenerator = null) -> void:
	while results.size() <= r:
		results.append([])
	results[r] = res.map(func(x): return [x["home"], x["away"], x["hg"], x["ag"], x.get("winner", "")])
	if r < GROUP_ROUNDS:
		for x in res:
			_row(x["home"], x["hg"], x["ag"])
			_row(x["away"], x["ag"], x["hg"])
		if r == GROUP_ROUNDS - 1:
			_draw_last16(rng)
		return
	if r == GROUP_ROUNDS + 6:
		if not res.is_empty():
			winner = res[0]["winner"]
		return
	if (r - GROUP_ROUNDS) % 2 == 1:
		var through: Array = res.map(func(x): return x["winner"])
		_shuffle(through, rng)
		var stage: int = (r - GROUP_ROUNDS) / 2
		if stage == KO_NAMES.size() - 1:
			if through.size() >= 2:
				final_tie = [through[0], through[1]]
		else:
			var next: Array = []
			for i in range(0, through.size() - 1, 2):
				next.append([through[i], through[i + 1]])
			ko.append(next)


func _row(c: String, gf: int, ga: int) -> void:
	var t: Array = table[c]
	t[0] += 1
	t[4] += gf
	t[5] += ga
	if gf > ga:
		t[1] += 1
		t[6] += 3
	elif gf < ga:
		t[3] += 1
	else:
		t[2] += 1
		t[6] += 1


func group_standings(g: int) -> Array:
	var ids: Array = groups[g].duplicate()
	ids.sort_custom(_ranks_above)
	return ids


func _ranks_above(a: String, b: String) -> bool:
	var ta: Array = table[a]
	var tb: Array = table[b]
	if ta[6] != tb[6]:
		return ta[6] > tb[6]
	if ta[4] - ta[5] != tb[4] - tb[5]:
		return ta[4] - ta[5] > tb[4] - tb[5]
	if ta[4] != tb[4]:
		return ta[4] > tb[4]
	return a < b


func _draw_last16(rng: RandomNumberGenerator) -> void:
	var winners: Array = []
	var runners: Array = []
	for g in groups.size():
		var s := group_standings(g)
		winners.append(s[0])
		runners.append(s[1])
	_shuffle(runners, rng)
	# Group winners play the second leg at home; avoid rematches from the same group.
	var ties: Array = []
	for i in winners.size():
		var pick := -1
		for j in runners.size():
			if _group_of(runners[j]) != _group_of(winners[i]):
				pick = j
				break
		if pick < 0:
			pick = 0
		ties.append([runners[pick], winners[i]])
		runners.remove_at(pick)
	ko = [ties]


func _group_of(c: String) -> int:
	for g in groups.size():
		if groups[g].has(c):
			return g
	return -1


func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	if rng == null:
		return
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func is_complete() -> bool:
	return winner != ""


func involves(club_id: String) -> bool:
	return table.has(club_id)


## Still in the competition?
func alive(club_id: String) -> bool:
	if winner != "":
		return winner == club_id
	if not table.has(club_id):
		return false
	if results.size() < GROUP_ROUNDS:
		return true
	if not final_tie.is_empty():
		return final_tie.has(club_id)
	if ko.is_empty():
		return false
	for t in ko[ko.size() - 1]:
		if t.has(club_id):
			return true
	return false


func reached(club_id: String) -> String:
	if winner == club_id:
		return "Winner"
	if final_tie.has(club_id):
		return "Final"
	for s in range(ko.size() - 1, -1, -1):
		for t in ko[s]:
			if t.has(club_id):
				return KO_NAMES[s]
	if table.has(club_id):
		return "Group stage"
	return ""


func to_dict() -> Dictionary:
	return {"kind": kind, "id": id, "name": name, "clubs": clubs, "groups": groups, "table": table,
		"results": results, "ko": ko, "final_tie": final_tie, "winner": winner}


func load_dict(d: Dictionary) -> void:
	id = d["id"]
	name = d["name"]
	clubs = d.get("clubs", [])
	groups = d.get("groups", [])
	table = {}
	var td: Dictionary = d.get("table", {})
	for c in td:
		table[c] = td[c].map(func(v): return int(v))
	results = []
	for rr in d.get("results", []):
		results.append(rr.map(func(x): return [x[0], x[1], int(x[2]), int(x[3]), x[4]]))
	ko = d.get("ko", [])
	final_tie = d.get("final_tie", [])
	winner = str(d.get("winner", ""))
