extends RefCounted
## Makes fictional players. Used for the generated world, youth intakes, tests,
## and filler players where real squad data runs out.

const Player = preload("res://src/sim/player.gd")
const Balance = preload("res://src/sim/balance.gd")

const SQUAD_TEMPLATE := {"GK": 3, "CB": 4, "FB": 4, "DM": 2, "CM": 3, "AM": 2, "WG": 3, "ST": 3}

## Typical strengths and weaknesses per position, relative to the player's level.
const ROLE_OFFSETS := {
	"GK": {"goalkeeping": 5, "pace": -15, "shooting": -30, "passing": -10, "dribbling": -20, "defending": -25, "physical": -5},
	"CB": {"defending": 8, "physical": 6, "pace": -6, "shooting": -20, "passing": -6, "dribbling": -14, "goalkeeping": -50},
	"FB": {"pace": 6, "defending": 3, "passing": -2, "physical": -2, "dribbling": -4, "shooting": -14, "goalkeeping": -50},
	"DM": {"defending": 5, "passing": 3, "physical": 4, "pace": -6, "shooting": -10, "dribbling": -6, "goalkeeping": -50},
	"CM": {"passing": 6, "dribbling": 1, "physical": 0, "defending": -4, "shooting": -5, "pace": -4, "goalkeeping": -50},
	"AM": {"passing": 5, "dribbling": 6, "shooting": 2, "defending": -18, "physical": -8, "pace": 0, "goalkeeping": -50},
	"WG": {"pace": 8, "dribbling": 6, "shooting": -2, "passing": -2, "defending": -20, "physical": -8, "goalkeeping": -50},
	"ST": {"shooting": 8, "physical": 2, "pace": 2, "dribbling": 0, "passing": -8, "defending": -24, "goalkeeping": -50},
}

## Name pools by language. All combinations are invented.
const NAMES := {
	"en": [["Adam", "Ben", "Callum", "Dan", "Ethan", "Finn", "George", "Harry", "Jack", "Kieran", "Liam", "Mason", "Nathan", "Oliver", "Reece", "Sam", "Tom", "Will", "Jordan", "Lewis"],
		["Ashby", "Bramwell", "Carver", "Dunmore", "Ellwood", "Fairlie", "Gatling", "Hartley", "Ingram", "Jessop", "Kingsley", "Lowther", "Mayhew", "Northcott", "Oakes", "Pryor", "Radley", "Stannard", "Thorne", "Whitcombe"]],
	"es": [["Adrián", "Álvaro", "Carlos", "Diego", "Javier", "Jorge", "Luis", "Marcos", "Mario", "Pablo", "Raúl", "Sergio", "Iker", "Unai", "Rubén", "Hugo", "Dani", "Nacho", "Óscar", "Íñigo"],
		["Alcaraz", "Barrera", "Cabello", "Delgado", "Escobar", "Ferrán", "Galán", "Herrero", "Iglesia", "Juárez", "Lozano", "Marín", "Navas", "Ortega", "Paredes", "Quintana", "Robles", "Salcedo", "Toledo", "Valverde"]],
	"de": [["Jonas", "Leon", "Lukas", "Felix", "Maximilian", "Niklas", "Tim", "Jan", "Florian", "Kai", "Moritz", "Paul", "Julian", "Fabian", "Marco", "Tobias", "Sebastian", "Dominik", "Lars", "Timo"],
		["Achterberg", "Brandauer", "Dietrich", "Eckert", "Falkner", "Gerlach", "Haller", "Imhof", "Jansen", "Kessler", "Lindemann", "Mertens", "Neubauer", "Oberle", "Pfeiffer", "Reinholz", "Schober", "Tauber", "Vogt", "Wendland"]],
	"fr": [["Antoine", "Baptiste", "Clément", "Damien", "Enzo", "Florian", "Gaël", "Hugo", "Jules", "Kylian", "Lucas", "Mathis", "Noé", "Ousmane", "Rayan", "Théo", "Yanis", "Malik", "Nolan", "Aurélien"],
		["Aubert", "Bonnard", "Chevalier", "Delorme", "Fabre", "Gauthier", "Hamon", "Joly", "Lacroix", "Marchal", "Noël", "Perrin", "Renaud", "Saunier", "Texier", "Vasseur", "Kanté", "Diallo", "Traoré", "Camara"]],
	"it": [["Alessandro", "Andrea", "Davide", "Federico", "Gianluca", "Lorenzo", "Luca", "Marco", "Matteo", "Nicolò", "Riccardo", "Simone", "Stefano", "Tommaso", "Giacomo", "Pietro", "Filippo", "Edoardo", "Manuel", "Samuele"],
		["Bellandi", "Castagna", "Donnarumi", "Ferraresi", "Galletti", "Lombardo", "Mancuso", "Natali", "Orsini", "Pellegrino", "Ricciardi", "Santoro", "Tarantino", "Vitale", "Zanetti", "Barone", "Colombo", "De Santis", "Fiore", "Greco"]],
	"pt": [["André", "Bruno", "Diogo", "Gonçalo", "João", "Rafael", "Rúben", "Tiago", "Vitinha", "Pedro", "Nuno", "Ricardo", "Gabriel", "Matheus", "Thiago", "Lucas", "Caio", "Felipe", "Renato", "Vinícius"],
		["Almeida", "Barbosa", "Carvalho", "Duarte", "Esteves", "Figueira", "Gomes", "Henriques", "Lopes", "Macedo", "Neves", "Pacheco", "Quaresma", "Rocha", "Sampaio", "Teixeira", "Vieira", "Moura", "Batista", "Cardoso"]],
	"nl": [["Bram", "Daan", "Jesse", "Joris", "Lars", "Luuk", "Milan", "Ruben", "Sem", "Stijn", "Teun", "Thijs", "Wout", "Jelle", "Bart", "Kees", "Niels", "Sven", "Pim", "Rick"],
		["Bakker", "de Boer", "Dekker", "van Dijkhuis", "Hendriks", "Jansma", "de Jong", "Kuipers", "Meijer", "Mulder", "Peters", "de Roos", "Smit", "Verhoef", "Visser", "de Wit", "Brouwer", "Koster", "van Leeuwen", "Postma"]],
	"tr": [["Arda", "Burak", "Can", "Emre", "Hakan", "Kerem", "Mert", "Ozan", "Selim", "Yusuf", "Berk", "Cenk", "Efe", "Kaan", "Okan", "Ömer", "Serkan", "Tolga", "Volkan", "Yiğit"],
		["Akgün", "Aydın", "Balcı", "Çelik", "Demir", "Erdem", "Güler", "Kaya", "Korkmaz", "Öztürk", "Polat", "Şahin", "Taşkın", "Ünal", "Yıldız", "Yılmaz", "Arslan", "Bulut", "Koç", "Uçar"]],
	"world": [["Amadou", "Kwame", "Moussa", "Ibrahim", "Kofi", "Samuel", "Emeka", "Youssef", "Hiroki", "Takumi", "Mateus", "Nikola", "Luka", "Ivan", "Dmitri", "Marek", "Kasper", "Erik", "Oskar", "Andrei"],
		["Adeyemi", "Boateng", "Diop", "Eze", "Haddad", "Ito", "Kovač", "Lindgren", "Mensah", "Nakamura", "Novák", "Okoro", "Petrović", "Sørensen", "Takeda", "Wójcik", "Yamada", "Zielinski", "Andersen", "Popescu"]],
}

const LANGUAGE := {
	"ENG": "en", "SCO": "en", "ESP": "es", "ARG": "es", "GER": "de", "AUT": "de", "SUI": "de",
	"FRA": "fr", "BEL": "fr", "SEN": "fr", "CIV": "fr", "ITA": "it", "POR": "pt", "BRA": "pt",
	"NED": "nl", "TUR": "tr",
}
const FOREIGN_NATIONS: Array[String] = ["BRA", "ARG", "FRA", "POR", "NED", "BEL", "SEN", "CIV", "NGA", "GHA", "JPN", "KOR", "USA", "SWE", "DEN", "NOR", "POL", "CRO", "SRB", "URU", "COL", "MAR"]


## level is roughly the player's overall minus 5. bias adds to chosen attributes, e.g. {"pace": 3}.
static func make_player(rng: RandomNumberGenerator, id: String, position: String, level: float, bias: Dictionary = {}, nation: String = "", year: int = 2026, age: int = -1):
	var p = Player.new()
	p.id = id
	if nation == "":
		nation = FOREIGN_NATIONS[rng.randi_range(0, FOREIGN_NATIONS.size() - 1)]
	p.nationality = nation
	var pool: Array = NAMES[LANGUAGE.get(nation, "world")]
	p.name = "%s %s" % [pool[0][rng.randi_range(0, pool[0].size() - 1)], pool[1][rng.randi_range(0, pool[1].size() - 1)]]
	p.position = position
	p.age = age if age > 0 else _random_age(rng)
	var offsets: Dictionary = ROLE_OFFSETS[position]
	p.attrs = {}
	for k in Player.ATTRS:
		var v: float = level + float(offsets.get(k, 0)) + float(bias.get(k, 0)) + rng.randfn(0.0, 4.0)
		p.attrs[k] = clampi(roundi(v), 10, 95)
	var weights: Dictionary = Balance.data()["role_weights"]
	p.overall = clampi(roundi(p.role_rating(position, weights)), 1, 99)
	p.potential = potential_for(p.overall, p.age, rng)
	p.value = value_for(p.overall, p.age, p.potential)
	p.wage = wage_for(p.value)
	p.morale = rng.randf_range(60.0, 85.0)
	p.contract_end = year + rng.randi_range(0, 4)
	return p


## The squad is built around a strength: first choices near `level`, depth a little below.
## Most players come from the club's own country.
static func make_squad(rng: RandomNumberGenerator, club_id: String, level: float, bias: Dictionary = {}, nation: String = "", year: int = 2026) -> Array:
	var squad: Array = []
	var n := 1
	for pos in SQUAD_TEMPLATE:
		for i in SQUAD_TEMPLATE[pos]:
			var depth_drop: float = 0.0 if i == 0 else rng.randf_range(1.0, 6.0)
			var lvl: float = level - depth_drop + rng.randfn(0.0, 2.0)
			var nat: String = nation if (nation != "" and rng.randf() < 0.7) else ""
			squad.append(make_player(rng, "%s-p%02d" % [club_id, n], pos, lvl, bias, nat, year))
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


## Market value in euros: grows steeply with quality, higher for young players with potential.
static func value_for(overall: int, age: int, potential: int = -1) -> int:
	var e: Dictionary = Balance.data().get("economy", {})
	var base: float = float(e.get("value_base", 20000.0)) * exp(float(e.get("value_growth", 0.2)) * (overall - 50))
	var age_factor := 1.0
	if age <= 21:
		age_factor = 1.35
	elif age <= 24:
		age_factor = 1.2
	elif age >= 33:
		age_factor = 0.35
	elif age >= 30:
		age_factor = 1.0 - (age - 29) * 0.15
	if potential > overall:
		age_factor *= 1.0 + minf(0.8, (potential - overall) * 0.04)
	return int(round(base * age_factor / 1000.0) * 1000.0)


## Weekly market wage for a player of this value.
static func wage_for(value: int) -> int:
	var e: Dictionary = Balance.data().get("economy", {})
	var share: float = float(e.get("wage_share_of_value", 1.4))
	var low_value: float = float(e.get("wage_low_value", 150000))
	var s: float = share
	if value < low_value:
		s = lerpf(float(e.get("wage_low_share", share)), share, float(value) / low_value)
	var wage: float = s * value / 52.0
	var cv: float = float(e.get("wage_curve_value", 3000000))
	if value > cv:
		wage = share * cv / 52.0 * pow(float(value) / cv, float(e.get("wage_curve_exponent", 0.6)))
	return maxi(int(e.get("min_wage", 400)), int(round(wage / 10.0) * 10))


static func _random_age(rng: RandomNumberGenerator) -> int:
	# Most players are 21-30, with some teenagers and veterans.
	return clampi(roundi(rng.randfn(26.0, 4.0)), 17, 36)
