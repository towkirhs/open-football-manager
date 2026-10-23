extends RefCounted
## A starting eleven in a formation, plus the bench.

const Tactics = preload("res://src/sim/tactics.gd")
const Balance = preload("res://src/sim/balance.gd")

## Roles are filled in this order, so specialists are not used up in other roles.
const FILL_ORDER: Array[String] = ["GK", "CB", "FB", "WB", "DM", "ST", "WG", "AM", "CM"]

var formation: String = "4-4-2"
## One entry per position on the pitch: {"role": String, "player": Player}
var slots: Array = []
var bench: Array = []


## Picks the best available eleven for a formation, then a bench.
func auto_pick(players: Array, formation_name: String, bench_size: int = 9) -> void:
	formation = formation_name
	slots = []
	bench = []
	var weights: Dictionary = Balance.data()["role_weights"]
	var roles: Array = ["GK"]
	roles.append_array(Tactics.FORMATIONS[formation_name])
	for r in roles:
		slots.append({"role": r, "player": null})

	var available: Array = players.filter(func(p): return p.injury_weeks <= 0)
	for role in FILL_ORDER:
		for slot in slots:
			if slot["role"] != role or slot["player"] != null:
				continue
			var best = null
			var best_score := -1.0
			for p in available:
				var s := score_for(p, role, weights)
				if s > best_score:
					best_score = s
					best = p
			if best != null:
				slot["player"] = best
				available.erase(best)

	available.sort_custom(func(a, b): return a.overall > b.overall)
	# Keep a spare goalkeeper on the bench when there is one.
	for p in available:
		if p.position == "GK":
			bench.append(p)
			available.erase(p)
			break
	for p in available:
		if bench.size() >= bench_size:
			break
		bench.append(p)


static func score_for(p, role: String, weights: Dictionary) -> float:
	return p.role_rating(role, weights) * Tactics.position_fit(p.position, role) * (0.85 + 0.15 * p.fitness / 100.0)


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
