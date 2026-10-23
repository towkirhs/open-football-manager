extends RefCounted
## Builds the fictional world: three playable countries with full league pyramids,
## plus the top clubs of other European countries, who appear in European cups and
## the transfer market. Every club and player name is invented.
##
## A real-data world (built on your own machine) uses the same layout; see tools/.

const Club = preload("res://src/sim/club.gd")
const Gen = preload("res://src/sim/player_generator.gd")
const Balance = preload("res://src/sim/balance.gd")
const Economy = preload("res://src/sim/economy.gd")

## [league name, number of clubs, [weakest, strongest] average squad overall]
const PLAYABLE := {
	"ENG": {"name": "England", "cup": "England Cup", "relegate": [3, 3, 4], "tiers": [
		["English Premier Division", 20, [71, 84]],
		["English Second Division", 24, [63, 72]],
		["English Third Division", 24, [57, 66]],
		["English Fourth Division", 24, [52, 61]]]},
	"ESP": {"name": "Spain", "cup": "Spain Cup", "relegate": [3], "tiers": [
		["Spanish First Division", 20, [70, 84]],
		["Spanish Second Division", 22, [62, 71]]]},
	"GER": {"name": "Germany", "cup": "Germany Cup", "relegate": [3, 3], "tiers": [
		["German First Division", 18, [69, 83]],
		["German Second Division", 18, [62, 71]],
		["German Third Division", 20, [56, 65]]]},
}

## Countries whose top clubs exist for European competition only: [name, clubs, [low, high]]
const FOREIGN := {
	"FRA": ["France", 8, [68, 82]], "ITA": ["Italy", 8, [69, 83]], "POR": ["Portugal", 6, [64, 79]],
	"NED": ["Netherlands", 6, [64, 78]], "TUR": ["Turkey", 6, [63, 76]], "BEL": ["Belgium", 6, [62, 75]],
	"SCO": ["Scotland", 6, [60, 73]], "AUT": ["Austria", 6, [61, 73]], "SUI": ["Switzerland", 6, [60, 72]],
	"GRE": ["Greece", 6, [60, 72]], "CZE": ["Czechia", 6, [60, 71]], "DEN": ["Denmark", 6, [60, 72]],
	"UKR": ["Ukraine", 5, [60, 72]], "CRO": ["Croatia", 5, [60, 71]], "SRB": ["Serbia", 5, [59, 70]],
}

const EUROPE := [
	{"id": "EC1", "name": "European Champions Cup", "teams": 32},
	{"id": "EC2", "name": "European League", "teams": 32},
	{"id": "EC3", "name": "European Conference Cup", "teams": 32},
]

## Town-name parts and club-name patterns per country ("%s" is the town).
const TOWNS := {
	"ENG": [["Ash", "Brack", "Cald", "Dun", "Elm", "Fallow", "Glen", "Halver", "Ivel", "Kestrel", "Larch", "Mire", "North", "Oak", "Pem", "Quarry", "Riven", "Salt", "Thistle", "Vell", "Wren", "Har", "Lin", "Stan", "Ever", "Bram", "Cran", "Marl", "Ted", "Wolver", "Hollin", "Bex", "Chad", "Ather", "Ruth"],
		["moor", "haven", "mere", "worth", "by", "rook", "ford", "port", "ton", "wick", "field", "bury", "ley", "ham", "dale", "gate", "bridge", "stow"],
		["%s Athletic", "%s FC", "%s City", "%s United", "%s Rovers", "%s Town", "%s Wanderers", "%s Albion", "%s County", "%s Rangers"]],
	"ESP": [["Vall", "Mont", "Sant", "Alt", "Riba", "Cas", "Torre", "Pal", "Ver", "Llan", "Mira", "Ser", "Cal", "Bel", "Ro", "Al", "Ba", "Lu", "Ta", "Zar"],
		["ada", "era", "illo", "ona", "ares", "ejo", "oza", "ana", "ida", "uelas", "edo", "anca", "ella"],
		["CD %s", "Real %s", "Atlético %s", "%s CF", "UD %s", "SD %s", "Racing %s", "Deportivo %s"]],
	"GER": [["Al", "Bad", "Bern", "Dorn", "Eber", "Falk", "Gries", "Hein", "Kirch", "Lau", "Mar", "Neu", "Ober", "Ros", "Stein", "Wald", "Zell", "Lind", "Hoh", "Brem"],
		["stadt", "berg", "burg", "feld", "hausen", "heim", "dorf", "bach", "au", "ingen", "lingen", "rode"],
		["FC %s", "SV %s", "VfB %s", "TSG %s", "SC %s", "%s 04", "Eintracht %s", "Union %s", "SpVgg %s", "FSV %s"]],
	"FRA": [["Belle", "Mont", "Ver", "Saint-Al", "Lor", "Ch", "Bour", "Val", "Roc", "Mar"], ["ville", "court", "mont", "ange", "elle", "ac", "ieux"], ["%s FC", "AS %s", "Olympique %s", "Stade %s", "RC %s"]],
	"ITA": [["Mont", "Castel", "Val", "Roc", "Ser", "Fio", "Pal", "Ter", "Ven", "Arc"], ["ina", "ano", "ello", "esca", "ona", "ate", "ore"], ["AC %s", "US %s", "%s Calcio", "Sporting %s", "Real %s"]],
	"POR": [["Vila", "Porto", "Sant", "Ria", "Mar", "Bel"], ["mar", "ense", "inho", "ela", "ões"], ["Sporting %s", "FC %s", "SC %s", "CD %s"]],
	"NED": [["Ams", "Zand", "Heer", "Dor", "Vlie", "Gro"], ["dam", "voort", "veen", "hout", "dijk", "wijk"], ["%s FC", "SC %s", "VV %s", "Go Ahead %s"]],
	"TUR": [["Kara", "Ak", "Gül", "Bey", "Yeni", "Deniz"], ["köy", "dere", "tepe", "yurt", "kent"], ["%sspor", "%s SK", "%s FK"]],
	"BEL": [["Mech", "Lier", "Gen", "Oost", "Waas", "Ber"], ["elen", "ende", "beke", "hout", "gem"], ["KV %s", "Royal %s", "%s FC"]],
	"SCO": [["Kil", "Dun", "Inver", "Strath", "Glen", "Aber"], ["more", "burn", "lochy", "keld", "brae"], ["%s FC", "%s Thistle", "%s Athletic", "%s Rovers"]],
	"AUT": [["Alt", "Sankt", "Hall", "Mur", "Linz"], ["bach", "egg", "dorf", "au"], ["SK %s", "%s FC", "Austria %s"]],
	"SUI": [["Lau", "Win", "Thal", "Sion", "Ber"], ["wil", "thur", "berg", "ach"], ["FC %s", "BSC %s", "%s Sport"]],
	"GRE": [["Ath", "Kal", "Pel", "Arg", "Thes"], ["ikos", "ion", "ia", "onia"], ["%s FC", "AE %s", "PAE %s"]],
	"CZE": [["Brn", "Ost", "Hrad", "Plz", "Lib"], ["ava", "ec", "ov", "ice"], ["FK %s", "SK %s", "Sparta %s"]],
	"DEN": [["Hol", "Vej", "Rand", "Silk", "Brø"], ["sted", "borg", "le", "by"], ["%s BK", "%s IF", "FC %s"]],
	"UKR": [["Dni", "Zor", "Kryv", "Vors", "Pol"], ["pro", "ya", "ka", "tava"], ["FC %s", "%s Kyiv", "Metalist %s"]],
	"CRO": [["Rij", "Spl", "Osi", "Var", "Zad"], ["eka", "it", "jek", "ar"], ["HNK %s", "NK %s", "GNK %s"]],
	"SRB": [["Vojv", "Novi", "Rad", "Čuk", "Spar"], ["odina", "čki", "nički", "ak"], ["FK %s", "OFK %s", "%s Beograd"]],
}

const COLOURS: Array = [["#c62828", "#ffffff"], ["#1565c0", "#ffffff"], ["#2e7d32", "#ffffff"], ["#111111", "#ffffff"],
	["#f9a825", "#111111"], ["#6a1b9a", "#ffffff"], ["#ef6c00", "#111111"], ["#00838f", "#ffffff"], ["#ad1457", "#ffffff"],
	["#ffffff", "#c62828"], ["#ffffff", "#1565c0"], ["#4e342e", "#ffe0b2"], ["#0d47a1", "#ffeb3b"], ["#b71c1c", "#ffeb3b"],
	["#1b5e20", "#ffd54f"], ["#37474f", "#80cbc4"], ["#880e4f", "#f8bbd0"], ["#6cace4", "#0b1f3a"], ["#7a1f2b", "#f2e6c9"], ["#9e9e9e", "#1b1b1b"]]

const STAFF_ROLES: Array[String] = ["head_coach", "assistant", "fitness", "goalkeeping", "youth", "scout", "physio"]
const STAFF_NAMES: Array[String] = ["Alan", "Bernd", "Carlos", "Dmitri", "Erik", "Fabio", "Gerard", "Hans", "Ignacio", "Jurgen", "Kasper", "Lorenzo", "Marco", "Nuno", "Olaf", "Paolo", "Rui", "Stefan", "Thierry", "Ulrich", "Victor", "Walter", "Yannick", "Zoran"]
const STAFF_SURNAMES: Array[String] = ["Abbott", "Brandt", "Castro", "Dekker", "Eriksen", "Ferrante", "Grosso", "Halvorsen", "Iglesias", "Janssen", "Klopper", "Lindahl", "Moreau", "Novak", "Ortega", "Petrov", "Quinn", "Rademaker", "Salgado", "Tennant", "Varga", "Weller"]


## Returns {"name", "fictional", "countries", "leagues", "europe", "clubs" (Club objects)}.
static func make_world(rng: RandomNumberGenerator, year: int = 2026) -> Dictionary:
	var countries: Array = []
	var leagues: Array = []
	var clubs: Array = []
	var used_names := {}
	var n := 0
	for cid in PLAYABLE:
		var c: Dictionary = PLAYABLE[cid]
		countries.append({"id": cid, "name": c["name"], "playable": true, "cup": c["cup"]})
		var tiers: Array = c["tiers"]
		for t in tiers.size():
			var lid := "%s%d" % [cid, t + 1]
			var rel: int = c["relegate"][t] if t < c["relegate"].size() else 0
			leagues.append({"id": lid, "name": tiers[t][0], "country": cid, "tier": t + 1, "relegate": rel})
			var count: int = tiers[t][1]
			var lo: float = tiers[t][2][0]
			var hi: float = tiers[t][2][1]
			for i in count:
				n += 1
				var strength: float = hi - (hi - lo) * i / maxf(1.0, count - 1) + rng.randfn(0.0, 0.8)
				clubs.append(_make_club(rng, "c%04d" % n, cid, lid, t + 1, strength, used_names, year))
	for cid in FOREIGN:
		var f: Array = FOREIGN[cid]
		countries.append({"id": cid, "name": f[0], "playable": false, "cup": ""})
		for i in int(f[1]):
			n += 1
			var strength: float = f[2][1] - (f[2][1] - f[2][0]) * i / maxf(1.0, f[1] - 1) + rng.randfn(0.0, 0.8)
			clubs.append(_make_club(rng, "c%04d" % n, cid, "", 1, strength, used_names, year))
	return {"name": "Fictional world", "fictional": true, "start_year": year,
		"countries": countries, "leagues": leagues, "europe": EUROPE.duplicate(true), "clubs": clubs}


static func _make_club(rng: RandomNumberGenerator, id: String, country: String, league: String, tier: int, strength: float, used: Dictionary, year: int):
	var c = Club.new()
	c.id = id
	c.country = country
	c.league = league
	c.name = _unique_name(rng, country, used)
	var town: String = c.name
	for part in ["Real ", "Racing ", "Atlético ", "Deportivo ", "Sporting ", "Eintracht ", "Union ", "Olympique ", "Stade ", "Royal ", "Go Ahead ", "Austria ", "Metalist ", "Sparta "]:
		town = town.replace(part, "")
	var letters: String = town.replace(" ", "").to_upper()
	for prefix in ["FC", "CD", "UD", "SD", "SV", "VFB", "TSG", "SC", "AC", "US", "AS", "RC", "KV", "SK", "FK", "BSC", "AE", "PAE", "HNK", "NK", "GNK", "OFK", "VV", "SPVGG", "FSV"]:
		if letters.begins_with(prefix) and letters.length() > prefix.length() + 2:
			letters = letters.substr(prefix.length())
	c.short_name = letters.left(3)
	c.colours = COLOURS[rng.randi_range(0, COLOURS.size() - 1)].duplicate()
	c.reputation = clampi(roundi(strength), 1, 99)
	var level: float = strength - 5.0
	var identities := [{}, {"pace": 3}, {"passing": 3, "dribbling": 2}, {"physical": 3}, {"defending": 3}]
	c.players = Gen.make_squad(rng, id, level, identities[rng.randi_range(0, identities.size() - 1)], country, year)

	# Stadium, crowd and facilities follow the club's standing.
	var rank: float = clampf((strength - 50.0) / 35.0, 0.0, 1.0)
	c.stadium = int(round(lerpf(4000.0, 75000.0, pow(rank, 1.6)) * rng.randf_range(0.8, 1.2) / 500.0) * 500)
	c.fans = int(c.stadium * rng.randf_range(0.6, 0.85))
	c.ticket_price = [0, 45, 25, 18, 12][clampi(tier, 1, 4)]
	var fac_level: int = clampi(roundi(1.0 + rank * 4.0 + rng.randf_range(-0.6, 0.6)), 1, 5)
	for k in Club.FACILITIES:
		c.facilities[k] = clampi(fac_level + rng.randi_range(-1, 1), 1, 5)
	c.facilities["stadium"] = clampi(roundi(1.0 + rank * 4.0), 1, 5)
	for role in STAFF_ROLES:
		c.staff[role] = make_staff(rng, clampi(roundi(strength - 10.0 + rng.randfn(0.0, 6.0)), 20, 95), year)
	# Fit the wage bill to what the club can earn, so every club starts out viable.
	var home_games: int = 23 if (tier >= 2 and country == "ENG") else 19
	var income: int = Economy.estimate_income(c, tier, home_games)
	var e: Dictionary = Balance.data()["economy"]
	var upkeep := 0
	for k in Club.FACILITIES:
		upkeep += int(e["facility_upkeep"][int(c.facilities[k])])
	var staff_cost := 0
	for role in c.staff:
		staff_cost += int(c.staff[role]["wage"])
	var target: float = income * float(e.get("start_wage_share_of_income", 0.62)) - (upkeep + staff_cost) * 52.0
	var player_wages := 0
	for p in c.players:
		player_wages += p.wage
	var factor: float = clampf(target / maxf(1.0, player_wages * 52.0), 0.5, 1.6)
	for p in c.players:
		p.wage = maxi(int(e.get("min_wage", 400)), int(round(p.wage * factor / 10.0) * 10))
	# Starting money: about a third of a year's wages, more for bigger clubs.
	c.cash = int(round(c.wage_bill() * 52 * rng.randf_range(0.3, 0.5) / 10000.0) * 10000)
	return c


static func make_staff(rng: RandomNumberGenerator, skill: int, year: int) -> Dictionary:
	var e: Dictionary = Balance.data().get("economy", {})
	var e_wage: float = float(e.get("staff_wage_base", 100.0)) * exp(float(e.get("staff_wage_growth", 0.05)) * skill)
	return {
		"name": "%s %s" % [STAFF_NAMES[rng.randi_range(0, STAFF_NAMES.size() - 1)], STAFF_SURNAMES[rng.randi_range(0, STAFF_SURNAMES.size() - 1)]],
		"skill": skill, "wage": int(round(e_wage / 10.0) * 10), "end": year + rng.randi_range(1, 3),
	}


static func _unique_name(rng: RandomNumberGenerator, country: String, used: Dictionary) -> String:
	var parts: Array = TOWNS[country]
	for _try in 200:
		var town: String = parts[0][rng.randi_range(0, parts[0].size() - 1)] + parts[1][rng.randi_range(0, parts[1].size() - 1)]
		var pattern: String = parts[2][rng.randi_range(0, parts[2].size() - 1)]
		var full: String = pattern % town
		if not used.has(full) and not used.has(town):
			used[full] = true
			used[town] = true
			return full
	var fallback := "%s %d" % [country, used.size()]
	used[fallback] = true
	return fallback
