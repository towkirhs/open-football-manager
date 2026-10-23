extends RefCounted
## A league: every club plays every other club home and away; three points for a win.

const Fixtures = preload("res://src/sim/fixtures.gd")

var kind: String = "league"
var id: String = ""
var name: String = ""
var country: String = ""
var tier: int = 1
## How many clubs go down to the tier below (and come up from it).
var relegate: int = 0
var clubs: Array = []
## Rounds of [home_id, away_id] pairs.
var rounds: Array = []
## Rounds of [home_id, away_id, home_goals, away_goals].
var results: Array = []
## club_id -> [played, won, drawn, lost, goals_for, goals_against, points, form "WDL.."]
var table: Dictionary = {}


func setup(def: Dictionary, club_ids: Array, rng: RandomNumberGenerator) -> void:
	id = def["id"]
	name = def["name"]
	country = def.get("country", "")
	tier = int(def.get("tier", 1))
	relegate = int(def.get("relegate", 0))
	clubs = club_ids.duplicate()
	rounds = Fixtures.double_round_robin(clubs, rng)
	results = []
	table = {}
	for c in clubs:
		table[c] = [0, 0, 0, 0, 0, 0, 0, ""]


func round_count() -> int:
	return rounds.size()


func round_name(r: int) -> String:
	return "Round %d" % (r + 1)


## Fixtures of a round: {"home", "away", "decisive": false}
func fixtures(r: int) -> Array:
	if r >= rounds.size():
		return []
	return rounds[r].map(func(m): return {"home": m[0], "away": m[1], "decisive": false})


func record(r: int, res: Array, _rng: RandomNumberGenerator = null) -> void:
	while results.size() <= r:
		results.append([])
	results[r] = res.map(func(x): return [x["home"], x["away"], x["hg"], x["ag"]])
	for x in res:
		_row(x["home"], x["hg"], x["ag"])
		_row(x["away"], x["ag"], x["hg"])


func _row(c: String, gf: int, ga: int) -> void:
	var t: Array = table[c]
	t[0] += 1
	t[4] += gf
	t[5] += ga
	var mark := "D"
	if gf > ga:
		t[1] += 1
		t[6] += 3
		mark = "W"
	elif gf < ga:
		t[3] += 1
		mark = "L"
	else:
		t[2] += 1
		t[6] += 1
	t[7] = (str(t[7]) + mark).right(5)


func decide(_f: Dictionary, _hg: int, _ag: int) -> String:
	return ""


func standings() -> Array:
	var ids: Array = table.keys()
	ids.sort_custom(_ranks_above)
	return ids


func _ranks_above(a: String, b: String) -> bool:
	var ta: Array = table[a]
	var tb: Array = table[b]
	if ta[6] != tb[6]:
		return ta[6] > tb[6]
	var gda: int = ta[4] - ta[5]
	var gdb: int = tb[4] - tb[5]
	if gda != gdb:
		return gda > gdb
	if ta[4] != tb[4]:
		return ta[4] > tb[4]
	return a < b


func position_of(club_id: String) -> int:
	return standings().find(club_id) + 1


func is_complete() -> bool:
	return results.size() >= rounds.size()


func involves(club_id: String) -> bool:
	return table.has(club_id)


func to_dict() -> Dictionary:
	return {"kind": kind, "id": id, "name": name, "country": country, "tier": tier, "relegate": relegate,
		"clubs": clubs, "rounds": rounds, "results": results, "table": table}


func load_dict(d: Dictionary) -> void:
	id = d["id"]
	name = d["name"]
	country = d.get("country", "")
	tier = int(d.get("tier", 1))
	relegate = int(d.get("relegate", 0))
	clubs = d.get("clubs", [])
	rounds = d.get("rounds", [])
	results = []
	for rr in d.get("results", []):
		results.append(rr.map(func(x): return [x[0], x[1], int(x[2]), int(x[3])]))
	table = {}
	var td: Dictionary = d.get("table", {})
	for c in td:
		var t: Array = td[c]
		table[c] = [int(t[0]), int(t[1]), int(t[2]), int(t[3]), int(t[4]), int(t[5]), int(t[6]), str(t[7])]
