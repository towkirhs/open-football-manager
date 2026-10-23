extends RefCounted
## Club money: match-day income, weekly wages and running costs, sponsors, TV money,
## prize money, facility upgrades, the bank (loans and advances) and the owner.
## Every club, human or AI, follows the same rules. All numbers are in balance.json.

const Balance = preload("res://src/sim/balance.gd")
const Club = preload("res://src/sim/club.gd")

const SPONSOR_NAMES: Array[String] = ["Northwind Energy", "Bluecrest Bank", "Orbit Telecom", "Harbor Freight Lines", "Summit Motors",
	"Greenfield Foods", "Atlas Insurance", "Nova Airlines", "Pinecone Software", "Redline Sports", "Silverleaf Hotels",
	"Quartz Electronics", "Cobalt Logistics", "Maple Breweries", "Zenith Health", "Crown Building Society"]


static func cfg() -> Dictionary:
	return Balance.data().get("economy", {})


# ---------------------------------------------------------------- income

## Fair ticket price for a club's division.
static func fair_price(tier: int) -> int:
	return int(cfg()["fair_ticket"].get(str(clampi(tier, 1, 4)), 20))


## Expected crowd for a home game. form is the fraction of points won in recent games (0 to 1).
static func attendance(club, tier: int, form: float, comp_kind: String) -> int:
	var fair: float = fair_price(tier)
	var price_ratio: float = float(club.ticket_price) / maxf(1.0, fair)
	var price_factor: float = clampf(pow(price_ratio, -float(cfg()["price_elasticity"])), 0.3, 1.5)
	var form_factor: float = 0.8 + 0.4 * form
	var comp_factor := 1.0
	if comp_kind == "europe":
		comp_factor = 1.25
	elif comp_kind == "cup":
		comp_factor = 0.85
	return clampi(int(club.fans * price_factor * form_factor * comp_factor), 0, club.stadium)


static func gate_income(club, tier: int, form: float, comp_kind: String) -> int:
	var crowd := attendance(club, tier, form, comp_kind)
	var price: int = club.ticket_price
	if comp_kind == "europe":
		price = int(price * 1.5)
	return crowd * price


## Season TV money for a league tier (paid in weekly parts during the league season).
static func tv_money(tier: int) -> int:
	return int(cfg()["tv_per_tier"].get(str(clampi(tier, 1, 4)), 0))


## Three sponsor offers: safe (all fixed), balanced, and bonus-heavy (less fixed, big bonus
## if the club finishes in the top half / top 4).
static func sponsor_offers(club, tier: int, rng: RandomNumberGenerator) -> Array:
	var base: float = float(club.fans) * float(cfg()["sponsor_per_fan"]) * (1.0 + 0.3 * (4 - clampi(tier, 1, 4)))
	base *= 0.8 + club.reputation / 250.0
	var names: Array = SPONSOR_NAMES.duplicate()
	var offers: Array = []
	var kinds := [["Safe", 1.0, 0, 0.0], ["Balanced", 0.85, 10, 0.25], ["Bonus-heavy", 0.6, 4, 0.8]]
	for k in kinds:
		var name: String = names[rng.randi_range(0, names.size() - 1)]
		names.erase(name)
		var weekly := int(round(base * float(k[1]) * rng.randf_range(0.92, 1.08) / 100.0) * 100)
		offers.append({"name": name, "kind": k[0], "weekly": weekly, "bonus_target": int(k[2]),
			"bonus": int(round(base * 46.0 * float(k[3]) / 1000.0) * 1000)})
	return offers


## Rough yearly income: TV, sponsor and home gates (foreign clubs: their share of TV).
static func estimate_income(club, tier: int, home_games: int) -> int:
	var tv: int = tv_money(tier)
	if club.league == "":
		tv = int(tv_money(1) * float(cfg().get("foreign_tv_share", 0.45)) * club.reputation / 80.0)
	var sponsor: float = float(club.fans) * float(cfg()["sponsor_per_fan"]) * (1.0 + 0.3 * (4 - clampi(tier, 1, 4))) * (0.8 + club.reputation / 250.0) * 0.85 * 46.0
	var gate: int = gate_income(club, tier, 0.5, "league") * home_games
	return tv + int(sponsor) + gate


# ---------------------------------------------------------------- weekly

## Weekly running costs and income outside match days. tv_weeks is the number of league weeks.
static func weekly(club, tier: int, tv_weeks: int) -> void:
	club.book("wages", -club.wage_bill())
	var upkeep := 0
	for k in Club.FACILITIES:
		upkeep += int(cfg()["facility_upkeep"][clampi(int(club.facilities[k]), 0, 5)])
	club.book("facilities", -upkeep)
	if not club.sponsor.is_empty():
		club.book("sponsor", int(club.sponsor.get("weekly", 0)))
	if club.league != "":
		club.book("tv", int(tv_money(tier) / maxi(1, tv_weeks)))
	# Loan repayments
	var remaining: Array = []
	for l in club.loans:
		var pay: int = int(l["weekly"])
		club.book("loans", -pay)
		l["weeks_left"] = int(l["weeks_left"]) - 1
		if club.cash < 0:
			club.missed_payments += 1
		if int(l["weeks_left"]) > 0:
			remaining.append(l)
	club.loans = remaining


# ---------------------------------------------------------------- facilities

static func upgrade_cost(club, facility: String) -> int:
	var lvl: int = int(club.facilities[facility])
	if lvl >= 5:
		return -1
	var cost: int = int(cfg()["facility_cost"][lvl + 1])
	if facility == "stadium":
		cost = int(cost * 1.5)
	return cost


## Pays for and applies an upgrade. Returns false when not affordable or already maxed.
static func upgrade(club, facility: String) -> bool:
	var cost := upgrade_cost(club, facility)
	if cost < 0 or club.cash < cost:
		return false
	club.book("facilities", -cost)
	club.facilities[facility] = int(club.facilities[facility]) + 1
	if facility == "stadium":
		var seats: int = int(cfg()["stadium_seats_per_level"]) * int(club.facilities["stadium"])
		club.stadium += seats
		club.fans = int(club.fans * 1.05)
	return true


static func facility_effect(facility: String, level: int) -> String:
	match facility:
		"stadium":
			return "More seats with each level"
		"training":
			return "Players improve %d%% faster" % ((level - 1) * 10)
		"youth":
			return "%d prospects a year, better quality" % (2 + level / 2)
		"medical":
			return "Injuries %d%% shorter, faster recovery" % ((level - 1) * 8)
		"scouting":
			return "See potential %s; %d%% off transfer fees" % ["exactly" if level >= 3 else "as a range", (level - 1) * 2]
	return ""


# ---------------------------------------------------------------- bank

## What the club owns, for working out how much it may borrow.
static func assets(club) -> int:
	var fac := 0
	for k in Club.FACILITIES:
		for l in range(2, int(club.facilities[k]) + 1):
			fac += int(cfg()["facility_cost"][l])
	return club.stadium * 1500 + fac + club.squad_value() / 2 + maxi(0, club.cash)


static func loan_limit(club) -> int:
	return maxi(0, int(assets(club) * float(cfg()["loan_asset_share"])) - club.debt())


## A (best) to E, from debt against yearly income and missed payments.
static func credit_rating(club, yearly_income: int) -> String:
	var ratio: float = float(club.debt()) / maxf(1.0, float(yearly_income))
	var score := 0
	if ratio > 0.25:
		score += 1
	if ratio > 0.5:
		score += 1
	if ratio > 1.0:
		score += 1
	score += mini(2, club.missed_payments)
	if club.cash < 0:
		score += 1
	return ["A", "B", "C", "D", "E"][clampi(score, 0, 4)]


static func interest_rate(rating: String) -> float:
	return float(cfg()["loan_rates"].get(rating, 0.15))


## Weekly repayment for a loan paid back over `weeks` weeks.
static func repayment(amount: int, rate: float, weeks: int) -> int:
	var total: float = amount * (1.0 + rate * weeks / 52.0)
	return int(ceil(total / maxi(1, weeks)))


static func take_loan(club, amount: int, seasons: int, rating: String) -> bool:
	if amount <= 0 or amount > loan_limit(club):
		return false
	var weeks: int = seasons * 52
	var rate := interest_rate(rating)
	club.loans.append({"kind": "loan", "principal": amount, "weekly": repayment(amount, rate, weeks), "weeks_left": weeks, "rate": rate})
	club.book("bank", amount)
	return true


## Advance on the TV money still to come this season, less a fee; repaid from the TV money.
static func advance_limit(club, tier: int, weeks_left: int, tv_weeks: int) -> int:
	for l in club.loans:
		if l["kind"] == "advance":
			return 0
	return int(tv_money(tier) * float(weeks_left) / maxi(1, tv_weeks) * 0.5)


static func take_advance(club, amount: int, weeks_left: int) -> bool:
	if amount <= 0 or weeks_left <= 0:
		return false
	var fee: float = float(cfg()["advance_fee"])
	club.loans.append({"kind": "advance", "principal": amount, "weekly": int(ceil(amount * (1.0 + fee) / weeks_left)), "weeks_left": weeks_left, "rate": fee})
	club.book("bank", amount)
	return true


static func repay_early(club, index: int) -> bool:
	if index < 0 or index >= club.loans.size():
		return false
	var l: Dictionary = club.loans[index]
	# Paying early saves the interest still to come on the remaining weeks.
	var remaining: float = float(l["weekly"]) * float(l["weeks_left"])
	var owed := int(remaining / (1.0 + float(l["rate"]) * float(l["weeks_left"]) / 52.0))
	if l["kind"] == "advance":
		owed = int(remaining)
	if club.cash < owed:
		return false
	club.book("bank", -owed)
	club.loans.remove_at(index)
	return true
