extends VBoxContainer
## Fixtures: your season, every competition, played and to come.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var hub = null
var season = null


func _ready() -> void:
	season = hub.season
	add_child(W.label("Cup ties appear once they are drawn. European ties appear as the competition goes on.", 13, "muted"))
	var t := W.table(["When", "Competition", "Round", "", "Opponent", "Result"], [130, 0, 0, 40, 0, 110])
	add_child(t)
	var by_day := {}
	for r in season.user_results:
		by_day[int(r["day"])] = r
	for d in season.calendar.size():
		var label: String = season.calendar[d]["label"]
		if by_day.has(d):
			var r: Dictionary = by_day[d]
			var home: bool = r["home"] == season.user_club_id
			var opp: String = r["away"] if home else r["home"]
			var gf: int = r["hg"] if home else r["ag"]
			var ga: int = r["ag"] if home else r["hg"]
			var won: bool = gf > ga or (r.get("pens", false) and r["winner"] == season.user_club_id)
			var lost: bool = gf < ga or (r.get("pens", false) and r["winner"] != season.user_club_id)
			var res := "%s %d-%d%s" % ["W" if won else ("L" if lost else "D"), gf, ga, " p" if r.get("pens", false) else ""]
			var it := W.row(t, [label, season.comp(r["comp"]).name, r.get("label", ""), "H" if home else "A", season.club(opp).name, res])
			it.set_custom_color(5, UiTheme.c("good" if won else ("bad" if lost else "warn")))
		elif d >= season.day:
			var f: Dictionary = season.user_fixture_on(d)
			if f.is_empty():
				continue
			var fx: Dictionary = f["fixture"]
			var home2: bool = fx["home"] == season.user_club_id
			var opp2: String = fx["away"] if home2 else fx["home"]
			var k = season.comp(f["comp"])
			W.row(t, [label, k.name, k.round_name(f["round"]), "N" if fx.get("neutral", false) else ("H" if home2 else "A"), season.club(opp2).name, ""],
				"", "highlight" if d == season.day else "")
