extends RefCounted
## A starting eleven in a formation, plus the bench.

const Tactics = preload("res://src/sim/tactics.gd")
const Balance = preload("res://src/sim/balance.gd")

## Roles are filled in this order, so specialists are not used up in other roles.
const FILL_ORDER: Array[String] = ["GK", "CB", "FB", "WB", "DM", "ST", "WG", "AM", "CM"]
const BENCH_SIZE := 9

var formation: String = "4-4-2"
## One entry per position on the pitch: {"role": String, "player": Player}
var slots: Array = []
var bench: Array = []


## Picks the best available eleven for a formation, then a bench.
func auto_pick(players: Array, formation_name: String, bench_size: int = BENCH_SIZE) -> void:
	_empty_slots(formation_name)
	var available: Array = players.filter(func(p): return p.injury_weeks <= 0)
	_fill_empty(available)
	_fill_bench(available, [], bench_size)


## Rebuilds a chosen team from player ids. Chosen players who are injured or no longer
## at the club are replaced by the best available player for that role.
## Returns the ids of chosen starters who had to be replaced.
func from_ids(players: Array, formation_name: String, slot_ids: Array, bench_ids: Array, bench_size: int = BENCH_SIZE) -> Array:
	_empty_slots(formation_name)
	var available: Array = players.filter(func(p): return p.injury_weeks <= 0)
	var by_id := {}
	for p in available:
		by_id[p.id] = p
	var replaced: Array = []
	for i in mini(slots.size(), slot_ids.size()):
		var id: String = slot_ids[i]
		if id == "":
			continue
		if by_id.has(id) and available.has(by_id[id]):
			slots[i]["player"] = by_id[id]
			available.erase(by_id[id])
		else:
			replaced.append(id)
	_fill_empty(available)
	_fill_bench(available, bench_ids, bench_size)
	return replaced


## Moves the team into a new formation. Current starters are preferred, but a bench
## player takes a role when he is clearly better suited to it (say, a third centre-back
## when switching to a back three). Anyone left out goes to the front of the bench.
func reshape(formation_name: String, use_bench: bool = true) -> void:
	var keep: Array = players_on_pitch()
	var old_bench: Array = bench.duplicate()
	var pool: Array = keep.duplicate()
	if use_bench:
		pool.append_array(old_bench.filter(func(p): return p.injury_weeks <= 0))
	var favoured := {}
	for p in keep:
		favoured[p.id] = true
	_empty_slots(formation_name)
	_fill_empty(pool, favoured)
	var on_pitch: Array = players_on_pitch()
	bench = []
	for p in keep + old_bench:
		if not on_pitch.has(p) and not bench.has(p):
			bench.append(p)
	if bench.size() > BENCH_SIZE:
		bench.resize(BENCH_SIZE)


func slot_ids() -> Array:
	return slots.map(func(s): return s["player"].id if s["player"] != null else "")


func bench_ids() -> Array:
	return bench.map(func(p): return p.id)


static func score_for(p, role: String, weights: Dictionary) -> float:
	return p.role_rating(role, weights) * Tactics.position_fit(p.position, role) * (0.85 + 0.15 * p.fitness / 100.0)


## How good a player is in a role, as a 1-99 number shown to the manager
## (includes playing out of position, not fitness).
static func role_score(p, role: String) -> int:
	var weights: Dictionary = Balance.data()["role_weights"]
	return roundi(p.role_rating(role, weights) * Tactics.position_fit(p.position, role))


func players_on_pitch() -> Array:
	var out: Array = []
	for s in slots:
		if s["player"] != null:
			out.append(s["player"])
	return out


func slot_index_of(player_id: String) -> int:
	for i in slots.size():
		var p = slots[i]["player"]
		if p != null and p.id == player_id:
			return i
	return -1


func _empty_slots(formation_name: String) -> void:
	formation = formation_name
	slots = []
	bench = []
	var roles: Array = ["GK"]
	roles.append_array(Tactics.FORMATIONS[formation_name])
	for r in roles:
		slots.append({"role": r, "player": null})


## Fills empty slots from `available`. Players in `favoured` get a small bonus,
## so they keep their place unless someone is clearly better for the role.
func _fill_empty(available: Array, favoured: Dictionary = {}) -> void:
	var weights: Dictionary = Balance.data()["role_weights"]
	for role in FILL_ORDER:
		for slot in slots:
			if slot["role"] != role or slot["player"] != null:
				continue
			var best = null
			var best_score := -1.0
			for p in available:
				var s := score_for(p, role, weights)
				if favoured.has(p.id):
					s *= 1.1
				if s > best_score:
					best_score = s
					best = p
			if best != null:
				slot["player"] = best
				available.erase(best)


func _fill_bench(available: Array, preferred_ids: Array, bench_size: int) -> void:
	bench = []
	for id in preferred_ids:
		for p in available:
			if p.id == id:
				bench.append(p)
				available.erase(p)
				break
	available.sort_custom(func(a, b): return a.overall > b.overall)
	# Keep a spare goalkeeper on the bench when there is one.
	var has_gk := bench.any(func(p): return p.position == "GK")
	if not has_gk:
		for p in available:
			if p.position == "GK":
				bench.append(p)
				available.erase(p)
				break
	for p in available:
		if bench.size() >= bench_size:
			break
		bench.append(p)
