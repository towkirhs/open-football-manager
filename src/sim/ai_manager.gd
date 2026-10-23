extends RefCounted
## An AI club's manager: a preferred style, a backup, and how readily they adapt.
## They pick tactics before a match and may change them at half-time.

const Tactics = preload("res://src/sim/tactics.gd")

const FIRST: Array[String] = ["Alan", "Bernd", "Carlos", "Dmitri", "Erik", "Fabio", "Gerard", "Hans", "Ignacio", "Jurgen", "Kasper", "Lorenzo", "Marco", "Nuno", "Olaf", "Pep", "Rui", "Stefan", "Thierry", "Ulrich"]
const LAST: Array[String] = ["Abbott", "Brandt", "Castro", "Dekker", "Eriksen", "Ferrante", "Grosso", "Halvorsen", "Iglesias", "Janssen", "Klopper", "Lindahl", "Moreau", "Novak", "Ortega", "Petrov", "Quinn", "Rademaker", "Salgado", "Tennant"]

var name: String = "AI manager"
var preferred_style: int = Tactics.Style.POSSESSION
var backup_style: int = Tactics.Style.COUNTER
var preferred_formation: String = "4-4-2"
## 0 to 1: how often they set up to counter the opponent's style.
var adaptiveness: float = 0.5
## Chance of trying something unexpected before a match.
var surprise_rate: float = 0.2


func setup_random(rng: RandomNumberGenerator) -> void:
	preferred_style = rng.randi_range(0, 4)
	backup_style = (preferred_style + rng.randi_range(1, 4)) % 5
	var forms: Array = Tactics.formation_names()
	preferred_formation = forms[rng.randi_range(0, forms.size() - 1)]
	adaptiveness = rng.randf_range(0.2, 0.8)
	name = "%s %s" % [FIRST[rng.randi_range(0, FIRST.size() - 1)], LAST[rng.randi_range(0, LAST.size() - 1)]]


func to_dict() -> Dictionary:
	return {"name": name, "preferred_style": preferred_style, "backup_style": backup_style,
		"preferred_formation": preferred_formation, "adaptiveness": adaptiveness, "surprise_rate": surprise_rate}


func load_dict(d: Dictionary) -> void:
	name = str(d.get("name", name))
	preferred_style = int(d.get("preferred_style", preferred_style))
	backup_style = int(d.get("backup_style", backup_style))
	preferred_formation = str(d.get("preferred_formation", preferred_formation))
	adaptiveness = float(d.get("adaptiveness", adaptiveness))
	surprise_rate = float(d.get("surprise_rate", surprise_rate))


func familiarity_for(style: int) -> float:
	if style == preferred_style:
		return 0.9
	if style == backup_style:
		return 0.8
	return 0.65


## opponent_style is the style the opponent has used most lately, or -1 if unknown.
func pick_tactics(opponent_style: int, rng: RandomNumberGenerator):
	var t = Tactics.new()
	t.formation = preferred_formation
	t.mentality = Tactics.Mentality.BALANCED
	if rng.randf() < surprise_rate:
		t.style = rng.randi_range(0, 4)
	elif opponent_style >= 0 and rng.randf() < adaptiveness:
		var options: Array = Tactics.counters_to(opponent_style)
		# Prefer a counter they already know.
		if options.has(preferred_style):
			t.style = preferred_style
		elif options.has(backup_style):
			t.style = backup_style
		else:
			t.style = options[rng.randi_range(0, options.size() - 1)]
	else:
		t.style = preferred_style
	t.familiarity = familiarity_for(t.style)
	return t


## Returns new tactics for the second half (may be unchanged).
func half_time(current, goal_diff: int, opponent_style: int, rng: RandomNumberGenerator):
	var t = current.copy()
	if goal_diff < 0:
		# Losing: switch to a style that beats theirs (unless already using one), and push forward.
		var options: Array = Tactics.counters_to(opponent_style)
		if not options.has(current.style) and rng.randf() < adaptiveness + 0.3:
			if options.has(preferred_style):
				t.style = preferred_style
			elif options.has(backup_style):
				t.style = backup_style
			else:
				t.style = options[rng.randi_range(0, options.size() - 1)]
		t.mentality = Tactics.Mentality.ATTACKING
	elif goal_diff > 0:
		if rng.randf() < 0.5:
			t.style = Tactics.Style.LOW_BLOCK
			t.mentality = Tactics.Mentality.DEFENSIVE
	t.familiarity = familiarity_for(t.style)
	return t
