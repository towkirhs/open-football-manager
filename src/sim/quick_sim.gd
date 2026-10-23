extends RefCounted
## Fast results for matches away from the human manager's club (other leagues, other
## cup ties). Goals follow a Poisson model from the two elevens' strength, tuned to
## match the full engine. It still produces scorers, assists, ratings and injuries,
## so every league has real stats.

const Balance = preload("res://src/sim/balance.gd")

const SHOOT := {"ST": 1.0, "WG": 0.65, "AM": 0.6, "CM": 0.3, "WB": 0.15, "DM": 0.12, "FB": 0.12, "CB": 0.1, "GK": 0.0}
const PASS := {"AM": 1.0, "WG": 0.9, "CM": 0.8, "WB": 0.7, "ST": 0.5, "FB": 0.5, "DM": 0.4, "CB": 0.15, "GK": 0.05}


## home_xi / away_xi: Arrays of {"role", "player"} slots (from Lineup.slots).
## home_strength / away_strength: average role rating of each eleven.
static func play(home_xi: Array, away_xi: Array, home_strength: float, away_strength: float, rng: RandomNumberGenerator, neutral: bool = false) -> Dictionary:
	var q: Dictionary = Balance.data().get("quick_sim", {})
	var diff: float = home_strength - away_strength
	var k: float = float(q.get("strength_factor", 0.055))
	var hx: float = float(q.get("neutral_goals" if neutral else "home_goals", 1.45)) * exp(k * diff)
	var ax: float = float(q.get("neutral_goals" if neutral else "away_goals", 1.15)) * exp(-k * diff)
	var hg := _poisson(hx, rng)
	var ag := _poisson(ax, rng)
	var events: Array = []
	var ratings := {}
	var injuries: Array = []
	for pair in [[home_xi, hg, ag, "home"], [away_xi, ag, hg, "away"]]:
		var xi: Array = pair[0]
		var scored: int = pair[1]
		var conceded: int = pair[2]
		var base := 6.5 + (0.4 if scored > conceded else (-0.3 if scored < conceded else 0.0))
		for slot in xi:
			if slot["player"] != null:
				ratings[slot["player"].id] = base + rng.randf_range(-0.6, 0.6)
		for _g in scored:
			var shooter = _pick(xi, SHOOT, "shooting", rng)
			if shooter == null:
				continue
			ratings[shooter.id] = ratings.get(shooter.id, 6.5) + 1.0
			var assist_id := ""
			if rng.randf() < 0.75:
				var others: Array = xi.filter(func(s): return s["player"] != shooter)
				var helper = _pick(others, PASS, "passing", rng)
				if helper != null:
					assist_id = helper.id
					ratings[helper.id] = ratings.get(helper.id, 6.5) + 0.6
			events.append({"minute": rng.randi_range(1, 90), "type": "goal", "side": pair[3], "player": shooter.id, "assist": assist_id, "text": ""})
		if conceded == 0:
			for slot in xi:
				if slot["player"] != null and slot["role"] in ["GK", "CB", "FB", "WB", "DM"]:
					ratings[slot["player"].id] += 0.5
		if rng.randf() < float(q.get("injury_chance", 0.1)) and not xi.is_empty():
			var hurt = xi[rng.randi_range(0, xi.size() - 1)]["player"]
			if hurt != null:
				injuries.append({"id": hurt.id, "weeks": rng.randi_range(1, 5)})
	for id in ratings:
		ratings[id] = snappedf(clampf(ratings[id], 4.0, 10.0), 0.1)
	return {"home_goals": hg, "away_goals": ag, "ratings": ratings, "events": events, "injuries": injuries, "condition": {}}


static func _pick(xi: Array, weights: Dictionary, attr: String, rng: RandomNumberGenerator):
	var total := 0.0
	var ws: Array = []
	for slot in xi:
		var p = slot["player"]
		var w: float = 0.0 if p == null else float(weights.get(slot["role"], 0.1)) * pow(p.attr(attr) / 70.0, 2.0)
		ws.append(w)
		total += w
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for i in xi.size():
		r -= ws[i]
		if r <= 0.0:
			return xi[i]["player"]
	return xi[xi.size() - 1]["player"]


static func _poisson(lam: float, rng: RandomNumberGenerator) -> int:
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= l:
			return k
		k += 1
		if k > 12:
			return k
	return k
