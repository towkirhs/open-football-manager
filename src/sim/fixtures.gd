extends RefCounted
## Builds a league fixture list: every club plays every other club home and away.


## Returns an Array of weeks; each week is an Array of [home_id, away_id] pairs.
## The second half of the season mirrors the first with home and away swapped,
## so every club has exactly as many home games as away games.
static func double_round_robin(ids: Array, rng: RandomNumberGenerator) -> Array:
	var teams: Array = ids.duplicate()
	for i in range(teams.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = teams[i]
		teams[i] = teams[j]
		teams[j] = tmp
	if teams.size() % 2 == 1:
		teams.append("")  # a bye

	var n: int = teams.size()
	var first_half: Array = []
	var last_venue := {}   # club -> "H" or "A" in its previous game
	var homes := {}        # club -> home games so far
	for r in n - 1:
		var week: Array = []
		for i in n / 2:
			var a = teams[i]
			var b = teams[n - 1 - i]
			if a == "" or b == "":
				continue
			# Whoever was at home last time plays away now; on a tie, the club
			# with fewer home games so far gets this one.
			var la: String = last_venue.get(a, "")
			var lb: String = last_venue.get(b, "")
			var a_home := true
			if la == "H" and lb != "H":
				a_home = false
			elif la == lb:
				var ha: int = homes.get(a, 0)
				var hb: int = homes.get(b, 0)
				if ha > hb or (ha == hb and rng.randf() < 0.5):
					a_home = false
			var home = a if a_home else b
			var away = b if a_home else a
			week.append([home, away])
			homes[home] = homes.get(home, 0) + 1
			last_venue[home] = "H"
			last_venue[away] = "A"
		first_half.append(week)
		# Circle method: keep the first team fixed and rotate the rest.
		var last = teams.pop_back()
		teams.insert(1, last)

	var second_half: Array = []
	for week in first_half:
		var mirrored: Array = []
		for m in week:
			mirrored.append([m[1], m[0]])
		second_half.append(mirrored)
	return first_half + second_half
