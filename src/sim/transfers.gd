extends RefCounted
## Transfers and contracts: asking prices, bids, wage demands, loans, free agents,
## renewals, the global player search, and what AI clubs do in a transfer window.

const Balance = preload("res://src/sim/balance.gd")
const Gen = preload("res://src/sim/player_generator.gd")
const Lineup = preload("res://src/sim/lineup.gd")

const MIN_SQUAD := 20
const MAX_SQUAD := 30


# ---------------------------------------------------------------- prices and wages

## How much a club wants for a player. Key players cost more; listed players and
## players near the end of their contract cost less.
static func asking_price(season, seller, p) -> int:
	if seller == null:
		return 0
	var factor := 1.15
	if season.is_key_player(seller, p):
		factor = 1.5
	if p.listed:
		factor *= 0.8
	var years_left: int = p.contract_end - season.year
	if years_left <= 0:
		factor *= 0.6
	elif years_left == 1:
		factor *= 0.85
	return int(round(p.value * factor / 1000.0) * 1000)


## Discount on fees thanks to the buyer's scouting network.
static func scouting_discount(buyer) -> float:
	return 0.02 * (int(buyer.facilities.get("scouting", 1)) - 1)


## "accept", "counter" or "reject", with the fee the seller would accept.
static func evaluate_bid(season, seller, p, fee: int, buyer) -> Dictionary:
	var ask := int(asking_price(season, seller, p) * (1.0 - scouting_discount(buyer)))
	if fee >= ask:
		return {"answer": "accept", "fee": fee}
	if fee >= ask * 0.75:
		return {"answer": "counter", "fee": ask}
	return {"answer": "reject", "fee": ask}


## Weekly wage a player wants to join (or stay at) a club.
static func wage_demand(season, p, club) -> int:
	# Based on market value; a player whose value has dropped accepts a little less than now.
	var base: int = maxi(Gen.wage_for(p.value), int(p.wage * 0.85))
	# Joining a smaller club costs more; a bigger club is an attraction.
	var gap: float = float(p.overall - club.reputation)
	var factor: float = 1.1 + clampf(gap / 25.0, -0.15, 0.6)
	if p.loan_from == "" and season.club_of(p.id) == club.id:
		factor -= 0.05
	return int(round(base * factor / 10.0) * 10)


## Would the player consider the club at all?
static func interested(p, club) -> bool:
	return club.reputation >= p.overall - 18 or p.age >= 31


## Personal terms: "accept", "counter" (wants more) or "reject".
static func evaluate_terms(season, p, club, wage: int, years: int) -> Dictionary:
	var want := wage_demand(season, p, club)
	# Older players like longer deals, young players shorter ones.
	if p.age >= 30:
		want = int(want * (1.0 - 0.04 * (years - 1)))
	elif p.age <= 22:
		want = int(want * (1.0 + 0.02 * (years - 1)))
	if wage >= want:
		return {"answer": "accept", "wage": wage}
	if wage >= want * 0.85:
		return {"answer": "counter", "wage": want}
	return {"answer": "reject", "wage": want}


# ---------------------------------------------------------------- search

## filters: name, position, min_ovr, max_ovr, min_age, max_age, max_value, min_pot,
## nationality, league, club (name contains), listed_only, free_only, exclude_club.
static func search(season, f: Dictionary, limit: int = 300) -> Array:
	var out: Array = []
	var name_q: String = str(f.get("name", "")).to_lower()
	var club_q: String = str(f.get("club", "")).to_lower()
	var pos: String = f.get("position", "")
	var league: String = f.get("league", "")
	var nat: String = str(f.get("nationality", "")).to_upper()
	var min_ovr: int = int(f.get("min_ovr", 0))
	var max_ovr: int = int(f.get("max_ovr", 99))
	var min_age: int = int(f.get("min_age", 0))
	var max_age: int = int(f.get("max_age", 99))
	var max_value: int = int(f.get("max_value", 0))
	var min_pot: int = int(f.get("min_pot", 0))
	var listed_only: bool = f.get("listed_only", false)
	var free_only: bool = f.get("free_only", false)
	var exclude: String = f.get("exclude_club", "")
	var sources: Array = []
	if not free_only:
		for c in season.clubs:
			if c.id == exclude:
				continue
			if league != "" and c.league != league:
				continue
			if club_q != "" and not c.name.to_lower().contains(club_q):
				continue
			sources.append([c, c.players])
	if league == "" and club_q == "":
		sources.append([null, season.free_agents])
	for src in sources:
		for p in src[1]:
			if pos != "" and p.position != pos:
				continue
			if p.overall < min_ovr or p.overall > max_ovr or p.age < min_age or p.age > max_age:
				continue
			if min_pot > 0 and p.potential < min_pot:
				continue
			if max_value > 0 and p.value > max_value:
				continue
			if nat != "" and p.nationality != nat:
				continue
			if listed_only and not p.listed:
				continue
			if name_q != "" and not p.name.to_lower().contains(name_q):
				continue
			out.append({"player": p, "club": src[0]})
	out.sort_custom(func(a, b): return a["player"].overall > b["player"].overall)
	if out.size() > limit:
		out.resize(limit)
	return out


# ---------------------------------------------------------------- moving players

## Moves a player between clubs (seller null = free agent). Fee and wage in euros.
static func complete(season, p, seller, buyer, fee: int, wage: int, years: int, loan: bool = false, wage_share: float = 1.0) -> void:
	if seller != null:
		seller.players.erase(p)
		if fee > 0:
			seller.book("transfers", fee)
	else:
		season.free_agents.erase(p)
	if fee > 0:
		buyer.book("transfers", -fee)
	buyer.players.append(p)
	p.listed = false
	if loan:
		p.loan_from = seller.id if seller != null else ""
		p.loan_wage_share = wage_share
	else:
		p.loan_from = ""
		p.loan_wage_share = 1.0
		p.wage = wage
		p.contract_end = season.year + maxi(1, years) - 1
	season.on_player_moved(p, seller, buyer, fee, loan)


static func release(season, club, p) -> void:
	club.players.erase(p)
	# Releasing a player pays out half of what is left on his contract.
	var years_left: int = maxi(0, p.contract_end - season.year + 1)
	var payout: int = int(p.wage * 52 * years_left * 0.5)
	if payout > 0:
		club.book("transfers", -payout)
	p.listed = false
	p.loan_from = ""
	season.free_agents.append(p)
	season.on_player_moved(p, club, null, 0, false)


# ---------------------------------------------------------------- AI clubs

## A few AI clubs look for one signing each day of an open window.
static func ai_window_day(season, rng: RandomNumberGenerator) -> void:
	var weights: Dictionary = Balance.data()["role_weights"]
	for c in season.clubs:
		if c.id == season.user_club_id:
			continue
		if c.players.size() > MAX_SQUAD:
			_ai_trim(season, c)
		if rng.randf() > 0.12 and c.players.size() >= MIN_SQUAD:
			continue
		_ai_try_signing(season, c, rng, weights)


static func _ai_trim(season, c) -> void:
	var sorted: Array = c.players.filter(func(p): return p.loan_from == "")
	sorted.sort_custom(func(a, b): return a.overall < b.overall)
	while c.players.size() > MAX_SQUAD and not sorted.is_empty():
		release(season, c, sorted.pop_front())


static func _ai_try_signing(season, c, rng: RandomNumberGenerator, weights: Dictionary) -> void:
	if c.cash <= 0 and c.players.size() >= MIN_SQUAD:
		return
	# Find the weakest position among the starting eleven.
	var xi = season.best_xi(c.id)
	var weakest_role := ""
	var weakest := 999.0
	for slot in xi.slots:
		if slot["player"] == null:
			weakest_role = slot["role"]
			weakest = 0.0
			break
		var s: float = Lineup.role_score(slot["player"], slot["role"])
		if s < weakest:
			weakest = s
			weakest_role = slot["role"]
	if weakest_role == "":
		return
	var budget: int = maxi(0, int(c.cash * 0.35))
	var best = null
	var best_seller = null
	var best_score := weakest + 2.0
	# Look at a random sample of the market: other clubs and free agents.
	for _i in 70:
		var seller = null
		var p = null
		if rng.randf() < 0.25 and not season.free_agents.is_empty():
			p = season.free_agents[rng.randi_range(0, season.free_agents.size() - 1)]
		else:
			seller = season.clubs[rng.randi_range(0, season.clubs.size() - 1)]
			if seller == c or seller.players.is_empty():
				continue
			p = seller.players[rng.randi_range(0, seller.players.size() - 1)]
		if p.loan_from != "" or p.injury_weeks > 3 or p.age >= 33:
			continue
		# AI clubs shop at their own level; this keeps the leagues from drifting apart.
		if p.overall > c.reputation + 5:
			continue
		var score: float = Lineup.role_score(p, weakest_role)
		if score <= best_score or not interested(p, c):
			continue
		var fee: int = 0 if seller == null else asking_price(season, seller, p)
		if fee > budget:
			continue
		if seller != null and season.is_key_player(seller, p) and rng.randf() < 0.7:
			# Clubs rarely sell their starters (bids for the human's go to the inbox).
			continue
		best = p
		best_seller = seller
		best_score = score
	if best == null:
		return
	var fee2: int = 0 if best_seller == null else asking_price(season, best_seller, best)
	var wage: int = wage_demand(season, best, c)
	# AI clubs keep their wage bill under 70% of their income.
	if (c.wage_bill() + wage) * 52 > season.yearly_income(c) * 0.7:
		return
	if best_seller != null and best_seller.id == season.user_club_id:
		season.add_offer(c, best, fee2, wage)
		return
	complete(season, best, best_seller, c, fee2, wage, rng.randi_range(2, 4))
	if best_seller != null and best_seller.players.size() < MIN_SQUAD and best_seller.id != season.user_club_id:
		_ai_sign_free(season, best_seller, rng)


static func _ai_sign_free(season, c, rng: RandomNumberGenerator) -> void:
	var pool: Array = season.free_agents.filter(func(p): return p.age < 34)
	pool.sort_custom(func(a, b): return a.overall > b.overall)
	for p in pool:
		if interested(p, c) and p.overall <= c.reputation + 5:
			complete(season, p, null, c, 0, wage_demand(season, p, c), rng.randi_range(1, 2))
			return


## End of season (before the year changes): AI clubs keep the players they want
## and let the rest go when their contract runs out.
static func ai_contracts(season, c, rng: RandomNumberGenerator) -> void:
	var avg: float = c.average_overall()
	for p in c.players.duplicate():
		if p.loan_from != "" or p.contract_end > season.year:
			continue
		var wanted: bool = p.overall >= avg - 8.0 and p.age < 34
		var new_wage: int = wage_demand(season, p, c)
		var affordable: bool = (c.wage_bill() - p.wage + new_wage) * 52 <= season.yearly_income(c) * 0.85
		if wanted and affordable and rng.randf() < 0.9:
			p.wage = new_wage
			p.contract_end = season.year + rng.randi_range(1, 3)
		else:
			c.players.erase(p)
			season.free_agents.append(p)
			season.on_player_moved(p, c, null, 0, false)


## Summer top-up for a club below its target squad size: the best affordable free agents
## who fit the club's level first, then academy prospects who are good enough.
static func fill_squad(season, c, target: int, rng: RandomNumberGenerator) -> Array:
	var signed: Array = []
	var avg: float = c.average_overall()
	var pool: Array = season.free_agents.filter(func(p): return p.age < 34 and p.overall >= avg - 10.0 and p.overall <= avg + 6.0)
	pool.sort_custom(func(a, b): return a.overall > b.overall)
	for p in pool:
		if c.players.size() >= target:
			break
		var wage: int = wage_demand(season, p, c)
		if (c.wage_bill() + wage) * 52 > season.yearly_income(c) * 0.9 and c.players.size() >= MIN_SQUAD:
			continue
		complete(season, p, null, c, 0, wage, rng.randi_range(1, 3))
		signed.append(p)
	# Prospects already close to first-team level are promoted.
	for y in c.youth.duplicate():
		if y.overall >= avg - 8.0 and c.players.size() < target:
			c.youth.erase(y)
			c.players.append(y)
	# Still short: unattached players from outside the modelled leagues, a little below
	# the club's level, in the positions where the squad is thinnest.
	var n := 0
	while c.players.size() < target or c.players.filter(func(q): return q.position == "GK").size() < 2:
		n += 1
		var p = new_unattached(season, c, "%s-n%d%02d" % [c.id, season.year, n], season.generation_level(c) - rng.randf_range(2.0, 8.0), rng)
		complete(season, p, null, c, 0, wage_demand(season, p, c), rng.randi_range(1, 3))
		signed.append(p)
	return signed


## A generated player with roughly the given overall, for the position the club needs most.
static func new_unattached(season, c, id: String, target_overall: float, rng: RandomNumberGenerator):
	var need := ""
	var gap := -99.0
	if c.players.filter(func(q): return q.position == "GK").size() < 2:
		need = "GK"
		gap = 99.0
	for pos in Gen.SQUAD_TEMPLATE:
		var have: int = c.players.filter(func(q): return q.position == pos).size()
		var g: float = Gen.SQUAD_TEMPLATE[pos] - have + rng.randf() * 0.5
		if g > gap:
			gap = g
			need = pos
	var age: int = rng.randi_range(20, 30)
	var p = Gen.make_player(rng, id, need, target_overall - 14.0, {}, c.country if rng.randf() < 0.5 else "", season.year, age)
	# Shift the attributes so the overall lands on the target.
	var weights: Dictionary = Balance.data()["role_weights"]
	var shift: int = roundi(target_overall - p.overall)
	for k in p.attrs:
		p.attrs[k] = clampi(int(p.attrs[k]) + shift, 10, 95)
	p.refresh_overall(weights)
	p.potential = Gen.potential_for(p.overall, p.age, rng)
	p.value = Gen.value_for(p.overall, p.age, p.potential)
	season.free_agents.append(p)
	return p
