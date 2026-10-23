extends RefCounted
## How players change: weekly training, ageing at the end of a season, retirements,
## and the yearly youth intake.

const Balance = preload("res://src/sim/balance.gd")
const Player = preload("res://src/sim/player.gd")
const Gen = preload("res://src/sim/player_generator.gd")

## Which attributes each training focus works on (weights).
const FOCUS := {
	"attacking": {"shooting": 1.0, "dribbling": 0.7, "pace": 0.4},
	"defending": {"defending": 1.0, "physical": 0.6},
	"physical": {"physical": 1.0, "pace": 0.8},
	"technical": {"passing": 1.0, "dribbling": 0.8},
	"goalkeeping": {"goalkeeping": 1.0},
}
const YOUTH_POSITIONS: Array[String] = ["GK", "CB", "CB", "FB", "FB", "DM", "CM", "CM", "AM", "WG", "WG", "ST", "ST"]


static func cfg() -> Dictionary:
	return Balance.data().get("development", {})


## Growth per training week for a player of this age, before focus and gap.
static func age_rate(age: int) -> float:
	var c := cfg()
	if age <= 21:
		return float(c["growth_young"])
	if age <= 24:
		return float(c["growth_prime"])
	if age <= 28:
		return float(c["growth_settled"])
	if age <= 30:
		return 0.0
	return float(c["decline_veteran"]) * (1.0 + (age - 31) * 0.3)


## One week of training for a whole club.
static func train_club(club, rng: RandomNumberGenerator) -> Array:
	var weights_all: Dictionary = Balance.data()["role_weights"]
	var coach: int = club.staff_skill("head_coach")
	var gk_coach: int = club.staff_skill("goalkeeping")
	var facility: int = int(club.facilities.get("training", 1))
	var improved: Array = []
	for p in club.players + club.youth:
		if p.injury_weeks > 0:
			continue
		var base := age_rate(p.age)
		if base == 0.0:
			continue
		var k_coach: int = gk_coach if p.position == "GK" else coach
		var mult: float = (0.7 + k_coach / 150.0) * (0.8 + 0.1 * facility)
		var gap: float = float(p.potential - p.overall)
		if base > 0.0:
			# Players grow towards their potential, slower as they get close.
			mult *= clampf(gap / 8.0, 0.0, 1.5)
		else:
			# Good coaching and facilities slow the decline.
			mult = 1.4 - mult * 0.4
		if mult == 0.0:
			continue
		var w: Dictionary = weights_all.get(p.position, {})
		var focus: Dictionary = FOCUS.get(p.training, {})
		var bonus: float = float(cfg()["focus_bonus"])
		var changed := false
		for k in Player.ATTRS:
			var weight: float = float(w.get(k, 0.0))
			if focus.has(k):
				weight = weight * 0.6 + float(focus[k]) * 0.4 * bonus
			if weight <= 0.0:
				continue
			var delta: float = base * mult * weight * 1.15 * rng.randf_range(0.6, 1.4)
			var acc: float = float(p.progress.get(k, 0.0)) + delta
			while acc >= 1.0:
				p.attrs[k] = mini(99, int(p.attrs[k]) + 1)
				acc -= 1.0
				changed = true
			while acc <= -1.0:
				p.attrs[k] = maxi(10, int(p.attrs[k]) - 1)
				acc += 1.0
				changed = true
			p.progress[k] = acc
		if changed:
			var before: int = p.overall
			p.refresh_overall(weights_all)
			if p.overall > before:
				improved.append(p)
	return improved


## End of season: everyone is a year older; veterans lose some pace and strength.
static func age_player(p, rng: RandomNumberGenerator) -> void:
	p.age += 1
	if p.age >= 31:
		var drop: float = float(cfg()["ageing_decline"]) * (p.age - 30) * 0.5
		for k in ["pace", "physical"]:
			p.attrs[k] = maxi(10, int(p.attrs[k]) - roundi(drop * rng.randf_range(0.5, 1.5)))
	if p.age >= 24:
		# The ceiling settles down as a player's career goes on.
		p.potential = maxi(p.overall, p.potential - rng.randi_range(0, 2))
	p.refresh_overall(Balance.data()["role_weights"])
	p.value = Gen.value_for(p.overall, p.age, p.potential)


static func retires(p, rng: RandomNumberGenerator) -> bool:
	if p.age >= 38:
		return true
	if p.age >= 34:
		return rng.randf() < (p.age - 33) * 0.22
	if p.age >= 31 and p.overall < 50:
		return rng.randf() < 0.3
	return false


## New academy prospects. Better youth facilities and youth coach bring more and better players.
static func youth_intake(club, strength: float, year: int, rng: RandomNumberGenerator) -> Array:
	var level: int = int(club.facilities.get("youth", 1))
	var coach: int = club.staff_skill("youth")
	var count: int = 2 + level / 2 + (1 if rng.randf() < coach / 200.0 else 0)
	var out: Array = []
	for i in count:
		var pos: String = YOUTH_POSITIONS[rng.randi_range(0, YOUTH_POSITIONS.size() - 1)]
		var lvl: float = strength - 34.0 + level * 1.5 + coach / 25.0 + rng.randfn(0.0, 4.0)
		var nation: String = club.country if rng.randf() < 0.8 else ""
		var p = Gen.make_player(rng, "%s-y%d%02d" % [club.id, year, i + 1], pos, lvl, {}, nation, year, rng.randi_range(16, 17))
		# Prospects come with a high ceiling; a top academy finds the best ones.
		# Most prospects top out around the club's level; a top academy finds the odd star.
		var ceiling: float = rng.randf_range(6.0, 18.0) + level * 1.2 + coach / 30.0
		if rng.randf() < 0.05 + level * 0.01:
			ceiling += rng.randf_range(4.0, 10.0)
		p.potential = clampi(p.overall + roundi(ceiling), p.overall, 94)
		p.value = Gen.value_for(p.overall, p.age, p.potential)
		p.wage = int(Gen.wage_for(p.value) * 0.5)
		p.contract_end = year + 3
		out.append(p)
	return out


## Style familiarity: grows for the style used, fades slowly for the others.
static func update_familiarity(fam: Dictionary, used_style: int, assistant_skill: int) -> void:
	var gain: float = float(cfg()["familiarity_gain"]) * (0.7 + assistant_skill / 150.0)
	var loss: float = float(cfg()["familiarity_loss"])
	for s in 5:
		var v: float = float(fam.get(str(s), 0.6))
		if s == used_style:
			v = minf(1.0, v + gain)
		else:
			v = maxf(0.5, v - loss)
		fam[str(s)] = snappedf(v, 0.001)
