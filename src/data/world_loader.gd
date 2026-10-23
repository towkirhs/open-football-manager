extends RefCounted
## Reads and writes world files (JSON). A world file holds countries, leagues,
## European cups and clubs with their players. This layer holds no game rules.
##
## The game normally generates a fictional world. A real-data world is built on your own
## machine by tools/build_world.py and stored outside the repository; the game loads it
## from user://custom_world.json (copied there by "Load world file" in the game).

const Club = preload("res://src/sim/club.gd")
const WorldGen = preload("res://src/sim/world_gen.gd")

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
	var clubs: Array = []
	for cd in d["clubs"]:
		var c = Club.new()
		c.load_dict(cd)
		if c.staff.is_empty():
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(c.id)
			for role in WorldGen.STAFF_ROLES:
				c.staff[role] = WorldGen.make_staff(rng, clampi(c.reputation - 10, 20, 95), int(d.get("start_year", 2026)))
		clubs.append(c)
	if clubs.size() < 20:
		return {"error": "The world needs at least 20 clubs."}
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
