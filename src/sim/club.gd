extends RefCounted
## A football club and its squad.

const Player = preload("res://src/sim/player.gd")

var id: String = ""
var name: String = ""
var short_name: String = ""
## Two hex colours, used for the club shield and template shirts.
var colours: Array = ["#1f7a4d", "#ffffff"]
var reputation: int = 50
var players: Array = []


func load_dict(d: Dictionary) -> void:
	id = str(d.get("id", ""))
	name = str(d.get("name", ""))
	short_name = str(d.get("short_name", name.left(3).to_upper()))
	colours = d.get("colours", colours)
	reputation = int(d.get("reputation", 50))
	players = []
	for pd in d.get("players", []):
		var p = Player.new()
		p.load_dict(pd)
		players.append(p)


func to_dict() -> Dictionary:
	var pl: Array = []
	for p in players:
		pl.append(p.to_dict())
	return {
		"id": id, "name": name, "short_name": short_name,
		"colours": colours, "reputation": reputation, "players": pl,
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
