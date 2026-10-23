extends RefCounted
## Makes fictional players. Used for the sample league, for tests, and later
## for filler players in lower divisions where real squad data runs out.

const Player = preload("res://src/sim/player.gd")
const Balance = preload("res://src/sim/balance.gd")

const SQUAD_TEMPLATE := {"GK": 3, "CB": 4, "FB": 4, "DM": 2, "CM": 3, "AM": 2, "WG": 3, "ST": 3}

## Typical strengths and weaknesses per position, relative to the player's level.
const ROLE_OFFSETS := {
	"GK": {"goalkeeping": 8, "pace": -15, "shooting": -30, "passing": -10, "dribbling": -20, "defending": -25, "physical": -5},
	"CB": {"defending": 8, "physical": 6, "pace": -6, "shooting": -20, "passing": -6, "dribbling": -14, "goalkeeping": -50},
	"FB": {"pace": 6, "defending": 3, "passing": -2, "physical": -2, "dribbling": -4, "shooting": -14, "goalkeeping": -50},
	"DM": {"defending": 5, "passing": 3, "physical": 4, "pace": -6, "shooting": -10, "dribbling": -6, "goalkeeping": -50},
	"CM": {"passing": 6, "dribbling": 1, "physical": 0, "defending": -4, "shooting": -5, "pace": -4, "goalkeeping": -50},
	"AM": {"passing": 5, "dribbling": 6, "shooting": 2, "defending": -18, "physical": -8, "pace": 0, "goalkeeping": -50},
	"WG": {"pace": 8, "dribbling": 6, "shooting": -2, "passing": -2, "defending": -20, "physical": -8, "goalkeeping": -50},
	"ST": {"shooting": 8, "physical": 2, "pace": 2, "dribbling": 0, "passing": -8, "defending": -24, "goalkeeping": -50},
}

const FIRST_NAMES: Array[String] = [
	"Adrian", "Bruno", "Caleb", "Dario", "Emil", "Felix", "Gabriel", "Hugo", "Ivan", "Jonas",
	"Kofi", "Luca", "Mateo", "Nico", "Oscar", "Pablo", "Quentin", "Rafael", "Samir", "Tomas",
	"Umar", "Viktor", "Wesley", "Xavier", "Yusuf", "Zane", "Amadou", "Bastian", "Cyril", "Diego",
	"Elias", "Farid", "Goran", "Henrik", "Ismael", "Jamal", "Kenji", "Lars", "Milan", "Noah",
]
const LAST_NAMES: Array[String] = [
	"Ardent", "Bellamy", "Castell", "Dorvan", "Esterby", "Falcone", "Garrow", "Hallen", "Ivers", "Jaskow",
	"Kettering", "Lindqvist", "Morenz", "Nakamori", "Oduya", "Pellard", "Quarles", "Rossetti", "Sandoval", "Tavernier",
	"Ulrich", "Valdane", "Whitcombe", "Yarrow", "Zelenko", "Abara", "Brennick", "Corvino", "Dumont", "Eskel",
	"Fairholt", "Gundersen", "Hollins", "Ibarra", "Joubert", "Kowal", "Lemaire", "Mbeki", "Norgaard", "Okafor",
]
const NATIONALITIES: Array[String] = ["ENG", "ESP", "GER", "FRA", "ITA", "POR", "NED", "BRA", "ARG", "NGA", "SEN", "JPN", "USA", "SWE", "POL"]


## level is roughly the player's overall. bias adds to chosen attributes, e.g. {"pace": 3}.
static func make_player(rng: RandomNumberGenerator, id: String, position: String, level: float, bias: Dictionary = {}):
	var p = Player.new()
	p.id = id
	p.name = "%s %s" % [FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)], LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]]
	p.nationality = NATIONALITIES[rng.randi_range(0, NATIONALITIES.size() - 1)]
	p.position = position
	p.age = _random_age(rng)
	var offsets: Dictionary = ROLE_OFFSETS[position]
	p.attrs = {}
	for k in Player.ATTRS:
		var v: float = level + float(offsets.get(k, 0)) + float(bias.get(k, 0)) + rng.randfn(0.0, 4.0)
		p.attrs[k] = clampi(roundi(v), 10, 95)
	var weights: Dictionary = Balance.data()["role_weights"]
	p.overall = clampi(roundi(p.role_rating(position, weights)), 1, 99)
	p.potential = potential_for(p.overall, p.age, rng)
	p.value = value_for(p.overall, p.age)
	p.wage = int(p.value * 0.12 / 52.0)
	p.morale = rng.randf_range(60.0, 85.0)
	return p


static func make_squad(rng: RandomNumberGenerator, club_id: String, level: float, bias: Dictionary = {}) -> Array:
	var squad: Array = []
	var n := 1
	for pos in SQUAD_TEMPLATE:
		for i in SQUAD_TEMPLATE[pos]:
			# First choices sit near the club level, depth players a little below.
			var depth_drop: float = 0.0 if i == 0 else rng.randf_range(1.0, 6.0)
			var lvl: float = level - depth_drop + rng.randfn(0.0, 2.0)
			squad.append(make_player(rng, "%s-p%02d" % [club_id, n], pos, lvl, bias))
			n += 1
	return squad


static func potential_for(overall: int, age: int, rng: RandomNumberGenerator) -> int:
	var bonus := 0.0
	if age <= 18:
		bonus = 15.0
	elif age <= 21:
		bonus = 15.0 - (age - 18) * 2.3
	elif age <= 26:
		bonus = 8.0 - (age - 21) * 1.6
	return clampi(roundi(overall + bonus * rng.randf_range(0.5, 1.2)), overall, 99)


## Placeholder market value; the economy pass will replace this formula.
static func value_for(overall: int, age: int) -> int:
	var base: float = 50000.0 * pow(1.16, overall - 50)
	var age_factor := 1.0
	if age <= 23:
		age_factor = 1.3
	elif age >= 31:
		age_factor = maxf(0.3, 1.0 - (age - 30) * 0.15)
	return int(round(base * age_factor / 1000.0) * 1000.0)


static func _random_age(rng: RandomNumberGenerator) -> int:
	# Most players are 21-30, with some teenagers and veterans.
	return clampi(roundi(rng.randfn(26.0, 4.0)), 17, 36)
