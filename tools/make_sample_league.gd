extends SceneTree
## Generates the fictional sample league at data/sample/sample_league.json.
## All clubs and players are invented. The real-data build is created separately
## on your own machine and kept in private_data/ (never committed).
##
## Run:  godot --headless --path . -s res://tools/make_sample_league.gd

const Gen = preload("res://src/sim/player_generator.gd")
const Club = preload("res://src/sim/club.gd")
const WorldLoader = preload("res://src/data/world_loader.gd")

const OUT_PATH := "res://data/sample/sample_league.json"

const CLUBS := [
	["Brackenmoor Athletic", "BKM", "#7a1f2b", "#f2e6c9"],
	["Calderhaven FC", "CAL", "#1d4e89", "#ffffff"],
	["Dunmere Rovers", "DUN", "#0f5132", "#f5d547"],
	["Elmsworth Town", "ELM", "#c0392b", "#ffffff"],
	["Fallowby City", "FAL", "#6cace4", "#0b1f3a"],
	["Glenrook United", "GLR", "#111111", "#e5e5e5"],
	["Halvering FC", "HAL", "#ff7a00", "#1a1a1a"],
	["Ivelport Albion", "IVP", "#003b6f", "#f2c14e"],
	["Kestrelby Wanderers", "KES", "#5b2a86", "#ffffff"],
	["Larchmouth FC", "LAR", "#2e7d32", "#ffffff"],
	["Mirefield Sporting", "MIR", "#b71c1c", "#212121"],
	["Northwick Vale", "NWV", "#004d40", "#ffd54f"],
	["Oakhollow FC", "OAK", "#795548", "#fff8e1"],
	["Pembrill Rangers", "PEM", "#0d47a1", "#e53935"],
	["Quarrybank Athletic", "QBA", "#9e9e9e", "#1b1b1b"],
	["Rivenford City", "RIV", "#880e4f", "#f8bbd0"],
	["Saltmere Harbour", "SAL", "#00838f", "#ffffff"],
	["Thistlewood FC", "THI", "#4a148c", "#c5e1a5"],
	["Vellmoor United", "VEL", "#d32f2f", "#ffeb3b"],
	["Wrenshaw Town", "WRE", "#263238", "#80cbc4"],
]

## Each club gets a small identity bias so styles fit some squads better than others.
const IDENTITIES := [
	{}, {"pace": 3}, {"passing": 3, "dribbling": 2}, {"physical": 3}, {"defending": 3},
]


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var levels: Array = []
	for i in CLUBS.size():
		levels.append(62.0 + 16.0 * i / (CLUBS.size() - 1))
	# Shuffle with our own seeded generator so the file is the same every run.
	for i in range(levels.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = levels[i]
		levels[i] = levels[j]
		levels[j] = tmp

	var clubs: Array = []
	for i in CLUBS.size():
		var row: Array = CLUBS[i]
		var c = Club.new()
		c.id = "c%02d" % (i + 1)
		c.name = row[0]
		c.short_name = row[1]
		c.colours = [row[2], row[3]]
		var level: float = levels[i]
		c.reputation = roundi(level)
		c.players = Gen.make_squad(rng, c.id, level, IDENTITIES[rng.randi_range(0, IDENTITIES.size() - 1)])
		clubs.append(c)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/sample"))
	var err := WorldLoader.save_league(OUT_PATH, "Sample League (fictional)", clubs)
	if err != OK:
		push_error("Could not save sample league")
		quit(1)
		return
	print("Wrote %d clubs to %s" % [clubs.size(), OUT_PATH])
	for c in clubs:
		print("  %-22s avg overall %.1f" % [c.name, c.average_overall()])
	quit(0)
