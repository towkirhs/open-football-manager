extends RefCounted
## Reads and writes world files (JSON). A world file holds countries, leagues,
## European cups and clubs with their players. This layer holds no game rules.
##
## The game normally generates a fictional world. A real-data world is built on your own
## machine by tools/build_world.py and stored outside the repository; the game loads it
## from user://custom_world.json (copied there by "Load world file" in the game).

const Club = preload("res://src/sim/club.gd")
const WorldGen = preload("res://src/sim/world_gen.gd")
const Gen = preload("res://src/sim/player_generator.gd")
const Balance = preload("res://src/sim/balance.gd")

const CUSTOM_PATH := "user://custom_world.json"


## Returns {"name", "fictional", "start_year", "countries", "leagues", "europe", "clubs" (Club objects)}
## or {} with an "error" key when the file cannot be used.
static func load_world(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "Cannot open %s" % path}
	return parse_world(f.get_as_text())


static func parse_world(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "The file is not a JSON object."}
	var d: Dictionary = parsed
	for key in ["countries", "leagues", "clubs"]:
		if not d.has(key):
			return {"error": "The file has no \"%s\" list." % key}
	var year: int = int(d.get("start_year", 2026))
	var tiers := {}
	for l in d["leagues"]:
		tiers[str(l.get("id", ""))] = int(l.get("tier", 1))
	var normalize: bool = bool(d.get("normalize_values", false))
	var weights: Dictionary = Balance.data()["role_weights"]
	var clubs: Array = []
	for cd in d["clubs"]:
		var c = Club.new()
		c.load_dict(cd)
		if c.players.size() < 11:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(c.id)
		if normalize:
			# Real-data values and wages are rescaled to this game's economy.
			for p in c.players:
				var formula: int = roundi(p.role_rating(p.position, weights))
				if not p.ovr_bonus and cd.get("keep_overall", true):
					p.ovr_bonus = clampi(p.overall - formula, -8, 8)
				p.value = Gen.value_for(p.overall, p.age, p.potential)
				p.wage = Gen.wage_for(p.value)
				if p.contract_end < year:
					p.contract_end = year + rng.randi_range(0, 3)
		if not cd.has("reputation"):
			c.reputation = clampi(roundi(c.average_overall()), 1, 99)
		if c.short_name == "":
			c.short_name = c.name.replace(" ", "").to_upper().left(3)
		if not cd.has("colours"):
			c.colours = WorldGen.COLOURS[rng.randi_range(0, WorldGen.COLOURS.size() - 1)].duplicate()
		var tier: int = tiers.get(c.league, 1)
		# Fill in what real-data files lack: stadium, crowd, facilities, staff, money.
		WorldGen.fill_economy(c, tier, c.average_overall(), rng, year, not cd.has("stadium"))
		clubs.append(c)
	if clubs.size() < 20:
		return {"error": "The world needs at least 20 clubs with 11 or more players."}
	return {
		"name": str(d.get("name", "Custom world")),
		"fictional": bool(d.get("fictional", false)),
		"start_year": int(d.get("start_year", 2026)),
		"countries": d["countries"],
		"leagues": d["leagues"],
		"europe": d.get("europe", WorldGen.EUROPE.duplicate(true)),
		"clubs": clubs,
	}


static func save_world(path: String, world: Dictionary) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var out := world.duplicate()
	out["clubs"] = world["clubs"].map(func(c): return c.to_dict())
	f.store_string(JSON.stringify(out))
	return OK


static func has_custom_world() -> bool:
	return FileAccess.file_exists(CUSTOM_PATH)
