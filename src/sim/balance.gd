extends RefCounted
## Loads the tunable numbers in data/balance.json.
## Every formula reads its numbers from here, so balancing never needs a code change.

const PATH := "res://data/balance.json"

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f == null:
			push_error("Cannot open %s" % PATH)
			return {}
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("%s is not a JSON object" % PATH)
			return {}
		_cache = parsed
	return _cache


static func match_cfg() -> Dictionary:
	return data().get("match", {})


static func ratings_cfg() -> Dictionary:
	return data().get("ratings", {})


## Forget the cached file, e.g. after editing balance.json while the game runs.
static func reload() -> void:
	_cache = {}
