extends RefCounted
## One footballer. Attributes run from 1 to 99.
## Positions: GK, CB, FB, DM, CM, AM, WG, ST.

const ATTRS: Array[String] = ["pace", "shooting", "passing", "dribbling", "defending", "physical", "goalkeeping"]
const OUTFIELD_ATTRS: Array[String] = ["pace", "shooting", "passing", "dribbling", "defending", "physical"]
const TRAINING_FOCUS: Array[String] = ["balanced", "attacking", "defending", "physical", "technical", "goalkeeping"]

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
## Weekly wage.
var wage: int = 0
var value: int = 0
## The contract runs until the end of this season (a year, e.g. 2028 means the 2028/29 season).
var contract_end: int = 2027
## Path or URL of the player's photo; empty means "use a template portrait".
var photo: String = ""
## Weekly training focus, one of TRAINING_FOCUS.
var training: String = "balanced"
## Training progress stored per attribute until it adds up to a whole point.
var progress: Dictionary = {}
## On loan from this club id ("" when not on loan); the loan ends at the end of the season.
var loan_from: String = ""
## Share of the wage the borrowing club pays while on loan (0 to 1).
var loan_wage_share: float = 1.0
## Transfer-listed by the club.
var listed: bool = false
## Past seasons: {"year", "club", "apps", "goals", "assists", "avg"}
var career: Array = []


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
	contract_end = int(d.get("contract_end", 2027))
	photo = str(d.get("photo", ""))
	training = str(d.get("training", "balanced"))
	progress = {}
	var pr: Dictionary = d.get("progress", {})
	for k in pr:
		progress[k] = float(pr[k])
	loan_from = str(d.get("loan_from", ""))
	loan_wage_share = float(d.get("loan_wage_share", 1.0))
	listed = bool(d.get("listed", false))
	career = d.get("career", [])


func to_dict() -> Dictionary:
	var d := {
		"id": id, "name": name, "age": age, "nationality": nationality,
		"position": position, "attrs": attrs.duplicate(), "overall": overall,
		"potential": potential, "fitness": snappedf(fitness, 0.1), "morale": snappedf(morale, 0.1),
		"injury_weeks": injury_weeks, "wage": wage, "value": value, "contract_end": contract_end,
	}
	# Optional fields are only written when set, which keeps save files small.
	if photo != "":
		d["photo"] = photo
	if training != "balanced":
		d["training"] = training
	if not progress.is_empty():
		var pr := {}
		for k in progress:
			pr[k] = snappedf(progress[k], 0.001)
		d["progress"] = pr
	if loan_from != "":
		d["loan_from"] = loan_from
		d["loan_wage_share"] = loan_wage_share
	if listed:
		d["listed"] = true
	if not career.is_empty():
		d["career"] = career
	return d


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


## Recomputes overall from attributes (after training or ageing).
func refresh_overall(role_weights: Dictionary) -> void:
	overall = clampi(roundi(role_rating(position, role_weights)), 1, 99)
	potential = maxi(potential, overall)
