extends RefCounted
## Formations, playing styles, mentality, and which styles beat which.
## One instance holds one team's set-up for a match.

const Balance = preload("res://src/sim/balance.gd")

enum Style { COUNTER, POSSESSION, HIGH_PRESS, LONG_BALL, LOW_BLOCK }
enum Mentality { DEFENSIVE, BALANCED, ATTACKING }

const STYLE_NAMES: Array[String] = ["Counter-attack", "Possession", "High press", "Long ball", "Low block"]
const STYLE_KEYS: Array[String] = ["counter", "possession", "high_press", "long_ball", "low_block"]
const MENTALITY_NAMES: Array[String] = ["Defensive", "Balanced", "Attacking"]
const MENTALITY_KEYS: Array[String] = ["defensive", "balanced", "attacking"]

## The ten outfield roles of each formation (the goalkeeper is always added first).
const FORMATIONS := {
	"4-4-2": ["CB", "CB", "FB", "FB", "CM", "CM", "WG", "WG", "ST", "ST"],
	"4-3-3": ["CB", "CB", "FB", "FB", "DM", "CM", "CM", "WG", "WG", "ST"],
	"4-2-3-1": ["CB", "CB", "FB", "FB", "DM", "DM", "AM", "WG", "WG", "ST"],
	"4-5-1": ["CB", "CB", "FB", "FB", "DM", "DM", "CM", "WG", "WG", "ST"],
	"3-5-2": ["CB", "CB", "CB", "WB", "WB", "DM", "CM", "CM", "ST", "ST"],
	"3-4-3": ["CB", "CB", "CB", "WB", "WB", "CM", "CM", "WG", "WG", "ST"],
	"5-3-2": ["CB", "CB", "CB", "FB", "FB", "DM", "CM", "CM", "ST", "ST"],
	"5-4-1": ["CB", "CB", "CB", "FB", "FB", "DM", "DM", "WG", "WG", "ST"],
}

## Where each slot stands on the pitch, as [x, y] from 0 to 1 (y = 0 is the opponent's goal).
## Same order as FORMATIONS, with the goalkeeper added first.
const LAYOUT := {
	"4-4-2": [[0.5, 0.92], [0.38, 0.77], [0.62, 0.77], [0.12, 0.7], [0.88, 0.7], [0.38, 0.5], [0.62, 0.5], [0.12, 0.44], [0.88, 0.44], [0.38, 0.18], [0.62, 0.18]],
	"4-3-3": [[0.5, 0.92], [0.38, 0.77], [0.62, 0.77], [0.12, 0.7], [0.88, 0.7], [0.5, 0.6], [0.3, 0.45], [0.7, 0.45], [0.15, 0.22], [0.85, 0.22], [0.5, 0.15]],
	"4-2-3-1": [[0.5, 0.92], [0.38, 0.77], [0.62, 0.77], [0.12, 0.7], [0.88, 0.7], [0.38, 0.58], [0.62, 0.58], [0.5, 0.37], [0.15, 0.33], [0.85, 0.33], [0.5, 0.14]],
	"4-5-1": [[0.5, 0.92], [0.38, 0.77], [0.62, 0.77], [0.12, 0.7], [0.88, 0.7], [0.35, 0.58], [0.65, 0.58], [0.5, 0.42], [0.12, 0.42], [0.88, 0.42], [0.5, 0.16]],
	"3-5-2": [[0.5, 0.92], [0.27, 0.77], [0.5, 0.79], [0.73, 0.77], [0.08, 0.5], [0.92, 0.5], [0.5, 0.6], [0.32, 0.43], [0.68, 0.43], [0.38, 0.17], [0.62, 0.17]],
	"3-4-3": [[0.5, 0.92], [0.27, 0.77], [0.5, 0.79], [0.73, 0.77], [0.1, 0.5], [0.9, 0.5], [0.38, 0.5], [0.62, 0.5], [0.18, 0.22], [0.82, 0.22], [0.5, 0.15]],
	"5-3-2": [[0.5, 0.92], [0.3, 0.79], [0.5, 0.81], [0.7, 0.79], [0.08, 0.7], [0.92, 0.7], [0.5, 0.58], [0.3, 0.44], [0.7, 0.44], [0.38, 0.17], [0.62, 0.17]],
	"5-4-1": [[0.5, 0.92], [0.3, 0.79], [0.5, 0.81], [0.7, 0.79], [0.08, 0.7], [0.92, 0.7], [0.38, 0.55], [0.62, 0.55], [0.12, 0.42], [0.88, 0.42], [0.5, 0.16]],
}

## Roles that a position plays naturally even though the names differ
## (a full-back is a natural wing-back).
const NATURAL := {"WB": ["FB"]}

## Each style is strong against two styles and weak against the other two.
const BEATS := {
	Style.COUNTER: [Style.POSSESSION, Style.HIGH_PRESS],
	Style.POSSESSION: [Style.LOW_BLOCK, Style.LONG_BALL],
	Style.HIGH_PRESS: [Style.POSSESSION, Style.LOW_BLOCK],
	Style.LONG_BALL: [Style.HIGH_PRESS, Style.COUNTER],
	Style.LOW_BLOCK: [Style.COUNTER, Style.LONG_BALL],
}

## Positions a player can cover with only a small penalty.
const RELATED := {
	"CB": ["FB", "DM"],
	"FB": ["CB", "WG"],
	"DM": ["CB", "CM"],
	"CM": ["DM", "AM"],
	"AM": ["CM", "WG", "ST"],
	"WG": ["FB", "WB", "AM", "ST"],
	"ST": ["AM", "WG"],
}

var formation: String = "4-4-2"
var style: int = Style.POSSESSION
var mentality: int = Mentality.BALANCED
## 0.5 to 1.0: how well the squad knows this style. Grows with training and use.
var familiarity: float = 0.8


func copy():
	var t = get_script().new()
	t.formation = formation
	t.style = style
	t.mentality = mentality
	t.familiarity = familiarity
	return t


func to_dict() -> Dictionary:
	return {"formation": formation, "style": style, "mentality": mentality, "familiarity": familiarity}


func load_dict(d: Dictionary) -> void:
	formation = str(d.get("formation", "4-4-2"))
	if not FORMATIONS.has(formation):
		formation = "4-4-2"
	style = int(d.get("style", Style.POSSESSION))
	mentality = int(d.get("mentality", Mentality.BALANCED))
	familiarity = float(d.get("familiarity", 0.8))


func describe() -> String:
	return "%s, %s, %s" % [formation, STYLE_NAMES[style], MENTALITY_NAMES[mentality]]


func same_as(other) -> bool:
	return formation == other.formation and style == other.style and mentality == other.mentality


## +1 when style a beats style b, -1 when it loses, 0 otherwise.
static func matchup(a: int, b: int) -> int:
	if BEATS[a].has(b):
		return 1
	if BEATS[b].has(a):
		return -1
	return 0


## The styles that beat the given style.
static func counters_to(s: int) -> Array:
	var out: Array = []
	for k in BEATS:
		if BEATS[k].has(s):
			out.append(k)
	return out


## Multiplier for playing a player of position `pos` in role `role`.
static func position_fit(pos: String, role: String) -> float:
	var f: Dictionary = Balance.data().get("position_fit", {})
	if pos == role or NATURAL.get(role, []).has(pos):
		return float(f.get("same", 1.0))
	if role == "GK":
		return float(f.get("outfield_in_goal", 0.25))
	if pos == "GK":
		return float(f.get("keeper_outfield", 0.35))
	var rel: Array = RELATED.get(pos, [])
	if rel.has(role):
		return float(f.get("related", 0.88))
	return float(f.get("other", 0.72))


static func style_cfg(s: int) -> Dictionary:
	return Balance.data()["styles"][STYLE_KEYS[s]]


static func mentality_cfg(m: int) -> Dictionary:
	return Balance.data()["mentality"][MENTALITY_KEYS[m]]


static func formation_names() -> Array:
	return FORMATIONS.keys()
