extends RefCounted
## A football club: squad, stadium, money, facilities and staff.

const Player = preload("res://src/sim/player.gd")

const FACILITIES: Array[String] = ["stadium", "training", "youth", "medical", "scouting"]

var id: String = ""
var name: String = ""
var short_name: String = ""
## Two hex colours, used for the club shield and template shirts.
var colours: Array = ["#1f7a4d", "#ffffff"]
var reputation: int = 50
var country: String = ""
## League id, or "" for clubs that only appear in European competitions.
var league: String = ""
var players: Array = []

var stadium: int = 10000
## Typical home crowd before results and ticket prices are taken into account.
var fans: int = 8000
var cash: int = 1000000
var ticket_price: int = 20
## Facility levels, 1 to 5.
var facilities: Dictionary = {"stadium": 1, "training": 1, "youth": 1, "medical": 1, "scouting": 1}
## Current sponsor deal: {"name", "weekly", "bonus_target", "bonus"}
var sponsor: Dictionary = {}
## Staff: role -> {"name", "skill", "wage", "end"}
var staff: Dictionary = {}
## Loans: {"kind", "principal", "weekly", "weeks_left", "rate"}
var loans: Array = []
## This season's money in and out by category.
var ledger: Dictionary = {}
## Seasons and finishing positions: {"year", "league", "position", "trophies": []}
var history: Array = []
var trophies: Array = []
## Youth academy prospects, not yet in the first-team squad.
var youth: Array = []
## Owner's view of the manager, 0 to 100 (used for the human manager's club).
var confidence: float = 60.0
## Missed loan payments this season (affects the credit rating).
var missed_payments: int = 0


func load_dict(d: Dictionary) -> void:
	id = str(d.get("id", ""))
	name = str(d.get("name", ""))
	short_name = str(d.get("short_name", name.left(3).to_upper()))
	colours = d.get("colours", colours)
	reputation = int(d.get("reputation", 50))
	country = str(d.get("country", ""))
	league = str(d.get("league", ""))
	stadium = int(d.get("stadium", 10000))
	fans = int(d.get("fans", int(stadium * 0.7)))
	cash = int(d.get("cash", 1000000))
	ticket_price = int(d.get("ticket_price", 20))
	facilities = {}
	var fd: Dictionary = d.get("facilities", {})
	for k in FACILITIES:
		facilities[k] = int(fd.get(k, 1))
	sponsor = d.get("sponsor", {})
	staff = {}
	var sd: Dictionary = d.get("staff", {})
	for role in sd:
		var s: Dictionary = sd[role]
		staff[role] = {"name": str(s.get("name", "")), "skill": int(s.get("skill", 50)), "wage": int(s.get("wage", 0)), "end": int(s.get("end", 2027))}
	loans = []
	for l in d.get("loans", []):
		loans.append({"kind": str(l.get("kind", "loan")), "principal": int(l.get("principal", 0)), "weekly": int(l.get("weekly", 0)),
			"weeks_left": int(l.get("weeks_left", 0)), "rate": float(l.get("rate", 0.0))})
	ledger = {}
	var ld: Dictionary = d.get("ledger", {})
	for k in ld:
		ledger[k] = int(ld[k])
	history = d.get("history", [])
	trophies = d.get("trophies", [])
	players = []
	for pd in d.get("players", []):
		var p = Player.new()
		p.load_dict(pd)
		players.append(p)
	youth = []
	for pd in d.get("youth", []):
		var y = Player.new()
		y.load_dict(pd)
		youth.append(y)
	confidence = float(d.get("confidence", 60.0))
	missed_payments = int(d.get("missed_payments", 0))


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "short_name": short_name, "colours": colours,
		"reputation": reputation, "country": country, "league": league,
		"stadium": stadium, "fans": fans, "cash": cash, "ticket_price": ticket_price,
		"facilities": facilities, "sponsor": sponsor, "staff": staff, "loans": loans,
		"ledger": ledger, "history": history, "trophies": trophies,
		"players": players.map(func(p): return p.to_dict()),
		"youth": youth.map(func(p): return p.to_dict()),
		"confidence": confidence, "missed_payments": missed_payments,
	}


func average_overall(top_n: int = 16) -> float:
	var ovs: Array = players.map(func(p): return p.overall)
	ovs.sort()
	ovs.reverse()
	var n: int = mini(top_n, ovs.size())
	if n == 0:
		return 0.0
	var total := 0.0
	for i in n:
		total += ovs[i]
	return total / n


func wage_bill() -> int:
	var total := 0
	for p in players:
		total += int(p.wage * (p.loan_wage_share if p.loan_from != "" else 1.0))
	for role in staff:
		total += int(staff[role]["wage"])
	return total


func squad_value() -> int:
	var total := 0
	for p in players:
		if p.loan_from == "":
			total += p.value
	return total


func debt() -> int:
	var total := 0
	for l in loans:
		total += int(l["weekly"]) * int(l["weeks_left"])
	return total


func staff_skill(role: String) -> int:
	if staff.has(role):
		return int(staff[role]["skill"])
	return 30


func book(category: String, amount: int) -> void:
	cash += amount
	ledger[category] = int(ledger.get(category, 0)) + amount
