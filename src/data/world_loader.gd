extends RefCounted
## Reads and writes league files (JSON). This layer holds no game rules.
## Later the real-data build will load from world.db (SQLite) through this same layer.

const Club = preload("res://src/sim/club.gd")


## Returns {"name": String, "clubs": Array of Club}.
static func load_league(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open league file %s" % path)
		return {"name": "", "clubs": []}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("League file %s is not a JSON object" % path)
		return {"name": "", "clubs": []}
	var clubs: Array = []
	for cd in parsed.get("clubs", []):
		var c = Club.new()
		c.load_dict(cd)
		clubs.append(c)
	return {"name": str(parsed.get("name", "")), "clubs": clubs}


static func save_league(path: String, league_name: String, clubs: Array) -> Error:
	var out: Array = []
	for c in clubs:
		out.append(c.to_dict())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write league file %s" % path)
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"name": league_name, "fictional": true, "clubs": out}, "\t"))
	return OK
