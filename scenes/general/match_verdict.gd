class_name MatchVerdict
## General domain: who has won a match, the one rule the UI's MatchHUD (its banner) and the dev
## command server's `match` verb (`tools/match.py`'s scoring) both decide by. It reads the
## combatants through the Character API only (`faction`, `is_dead`; a freed one counts as
## fallen). A match is undecided while every side (faction) still has someone alive; once a side is
## wiped out it is decided: won by the one side left standing, or a draw when nobody, or more than
## one side, is left. Each caller words the result its own way (the HUD names a lone survivor; the
## `match` verb names one only in a 1v1).


## The verdict over `combatants`: {} while every side still has someone alive; once a side is
## wiped out, `{ winner, survivors, sides }`: `winner` the faction left standing (null for a draw),
## `survivors` the living combatants and `sides` each faction -> how many combatants it fields.
static func decide(combatants: Array) -> Dictionary:
	var sides := {}
	var standing := {}
	var survivors: Array = []
	for c in combatants:
		if not is_instance_valid(c):
			continue
		var faction = c.get("faction")
		sides[faction] = int(sides.get(faction, 0)) + 1
		if c.get("is_dead") != true:
			standing[faction] = true
			survivors.append(c)
	if standing.size() == sides.size():
		return {}
	return {
		"winner": standing.keys()[0] if standing.size() == 1 else null,
		"survivors": survivors,
		"sides": sides,
	}
