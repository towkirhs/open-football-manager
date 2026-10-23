extends RefCounted
## One footballer. Attributes run from 1 to 99.
## Positions: GK, CB, FB, DM, CM, AM, WG, ST.

const ATTRS: Array[String] = ["pace", "shooting", "passing", "dribbling", "defending", "physical", "goalkeeping"]
const OUTFIELD_ATTRS: Array[String] = ["pace", "shooting", "passing", "dribbling", "defending", "physical"]

var id: String = ""
var name: String = ""
var age: int = 25
var nationality: String = ""
var position: String = "CM"
var attrs: Dictionary = {}
var overall: int = 50
var potential: int = 50
var fitness: float = 100.0
var morale: float = 75.0
var injury_weeks: int = 0
var wage: int = 0
var value: int = 0
## Path or URL of the player's photo; empty means "use a template portrait".
var photo: String = ""


func load_dict(d: Dictionary) -> void:
	id = str(d.get("id", ""))
	name = str(d.get("name", ""))
	age = int(d.get("age", 25))
	nationality = str(d.get("nationality", ""))
	position = str(d.get("position", "CM"))
	attrs = {}
	var a: Dictionary = d.get("attrs", {})
	for k in ATTRS:
		attrs[k] = int(a.get(k, 40))
	overall = int(d.get("overall", 50))
	potential = int(d.get("potential", overall))
	fitness = float(d.get("fitness", 100.0))
	morale = float(d.get("morale", 75.0))
	injury_weeks = int(d.get("injury_weeks", 0))
	wage = int(d.get("wage", 0))
	value = int(d.get("value", 0))
	photo = str(d.get("photo", ""))


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "age": age, "nationality": nationality,
		"position": position, "attrs": attrs.duplicate(), "overall": overall,
		"potential": potential, "fitness": fitness, "morale": morale,
		"injury_weeks": injury_weeks, "wage": wage, "value": value, "photo": photo,
	}


## How good this player is in a role, before position familiarity and condition.
func role_rating(role: String, role_weights: Dictionary) -> float:
	return weighted(role_weights.get(role, {}))


## Weighted average of attributes, e.g. {"pace": 0.5, "shooting": 0.5}.
func weighted(weights: Dictionary) -> float:
	var total := 0.0
	var sum_w := 0.0
	for k in weights:
		total += float(attrs.get(k, 40)) * float(weights[k])
		sum_w += float(weights[k])
	if sum_w <= 0.0:
		return 40.0
	return total / sum_w


func outfield_average() -> float:
	var total := 0.0
	for k in OUTFIELD_ATTRS:
		total += float(attrs.get(k, 40))
	return total / OUTFIELD_ATTRS.size()


func attr(key: String) -> float:
	return float(attrs.get(key, 40))
