extends RefCounted
## A domestic knockout cup. Single matches; a draw goes to penalties.
## When the number of clubs is not a power of two, the lowest-ranked clubs play a
## first round and the rest get a bye.

var kind: String = "cup"
var id: String = ""
var name: String = ""
var country: String = ""
var clubs: Array = []
## Ties per round: [[home_id, away_id], ...]; a round is drawn when the previous one ends.
var ties: Array = []
## Results per round: [[home, away, hg, ag, winner], ...]
var results: Array = []
var byes: Array = []
var total_rounds: int = 0
var winner: String = ""


## club_ids should be ordered strongest first.
func setup(def: Dictionary, club_ids: Array, rng: RandomNumberGenerator) -> void:
	id = def["id"]
	name = def["name"]
	country = def.get("country", "")
	clubs = club_ids.duplicate()
	ties = []
	results = []
	winner = ""
	var n: int = clubs.size()
	var p := 1
	while p * 2 <= n:
		p *= 2
	var log2 := 0
	var q := p
	while q > 1:
		q /= 2
		log2 += 1
	if n > p:
		var extra: int = n - p
		var playing: Array = clubs.slice(n - extra * 2)
		byes = clubs.slice(0, n - extra * 2)
		ties.append(_draw(playing, rng))
		total_rounds = log2 + 1
	else:
		byes = []
		ties.append(_draw(clubs, rng))
		total_rounds = log2


func round_count() -> int:
	return total_rounds


func round_name(r: int) -> String:
	var left: int = total_rounds - r
	match left:
		1: return "Final"
		2: return "Semi-finals"
		3: return "Quarter-finals"
		4: return "Last 16"
	return "Round %d" % (r + 1)


func fixtures(r: int) -> Array:
	if r >= ties.size():
		return []
	return ties[r].map(func(t): return {"home": t[0], "away": t[1], "decisive": true, "neutral": r == total_rounds - 1})


## Winner of a single match, or "" when it was a draw (penalties decide).
func decide(_f: Dictionary, hg: int, ag: int) -> String:
	if hg > ag:
		return _f["home"]
	if ag > hg:
		return _f["away"]
	return ""


## res entries need "winner" set (by penalties if needed).
func record(r: int, res: Array, rng: RandomNumberGenerator = null) -> void:
	while results.size() <= r:
		results.append([])
	results[r] = res.map(func(x): return [x["home"], x["away"], x["hg"], x["ag"], x["winner"]])
	var through: Array = res.map(func(x): return x["winner"])
	if r == 0:
		through.append_array(byes)
	if through.size() == 1:
		winner = through[0]
	elif through.size() > 1 and rng != null:
		ties.append(_draw(through, rng))


func _draw(pool: Array, rng: RandomNumberGenerator) -> Array:
	var p: Array = pool.duplicate()
	for i in range(p.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = p[i]
		p[i] = p[j]
		p[j] = tmp
	var out: Array = []
	for i in range(0, p.size() - 1, 2):
		out.append([p[i], p[i + 1]])
	return out


func is_complete() -> bool:
	return winner != ""


func involves(club_id: String) -> bool:
	return clubs.has(club_id)


## Still in the cup?
func alive(club_id: String) -> bool:
	if winner != "":
		return winner == club_id
	if ties.is_empty():
		return clubs.has(club_id)
	var last: Array = ties[ties.size() - 1]
	for t in last:
		if t[0] == club_id or t[1] == club_id:
			return true
	return ties.size() == 1 and byes.has(club_id)


## How far a club got: the name of the last round it played (or "Winner").
func reached(club_id: String) -> String:
	if winner == club_id:
		return "Winner"
	var last := ""
	for r in results.size():
		for x in results[r]:
			if x[0] == club_id or x[1] == club_id:
				last = round_name(r)
	return last


func to_dict() -> Dictionary:
	return {"kind": kind, "id": id, "name": name, "country": country, "clubs": clubs, "ties": ties,
		"results": results, "byes": byes, "total_rounds": total_rounds, "winner": winner}


func load_dict(d: Dictionary) -> void:
	id = d["id"]
	name = d["name"]
	country = d.get("country", "")
	clubs = d.get("clubs", [])
	ties = d.get("ties", [])
	results = []
	for rr in d.get("results", []):
		results.append(rr.map(func(x): return [x[0], x[1], int(x[2]), int(x[3]), x[4]]))
	byes = d.get("byes", [])
	total_rounds = int(d.get("total_rounds", 0))
	winner = str(d.get("winner", ""))
