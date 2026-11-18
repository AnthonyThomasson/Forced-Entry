extends GameTest
## G17 (amended, #194 D10): GRENADE is offered when the thrower would be safe from it: the piece of
## furniture that hides the hostile from a bullet lies on the 3D line from the burst (on the floor,
## at the hostile) to the thrower, and a low piece shadows a standing body far enough behind it and
## a ducked one anywhere behind it, so a thrower in the zone has a safe place wherever such cover
## hides the hostile (a table that hides a ducked hostile shields a ducked thrower, and a standing
## one far enough behind it; the grenade is not dropped for want of a safe place). Two
## walled rooms, the same layout in each: an invader with a frag, a hostile 260 px away (inside a
## frag's 370 px zone) that ducked behind a piece of furniture the invader saw it duck behind, so
## it is known but out of its line of fire. In one room the piece is a coffee table (52 px tall) and
## the room has nothing else; in the other it is a couch (44 px) a few steps away. GRENADE is
## offered in both, and in each the thrower's place by the cover is shielded from the burst at the
## hostile (by the same 3D line the blast uses). The negative, no cover to be found, is judged by
## `ai/grenade/escape_judges_real_geometry`. Scripted Von; the NPCs walk (they are not held) because
## "in time" depends on being able to move.

const Hiding := preload("res://tests/_ai/hiding_piece.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const BARE_N := Vector2(100, 150)
const BARE_H := Vector2(360, 150)
const COVER_N := Vector2(100, 450)
const COVER_H := Vector2(360, 450)


func describe() -> Dictionary:
	return {
		"name": "A grenade is offered when the hostile's cover shadows the thrower",
		"description": "An invader 260 px from a hidden hostile with only a coffee table near, and "
			+ "one with a couch a few steps away, are both offered GRENADE: the cover that hides "
			+ "the hostile shields the thrower from the burst on the floor.",
		"tags": ["ai", "grenade", "combat", "cover", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Hiding.von_out(s)
	# Two rooms with a wall between and no door, one outer door each at the far end. Each room ends
	# 360 px past its hostile, inside a frag's 370 px zone: no spot out of the zone lies in it, so
	# wherever the invader walks (an advance brings it past the hostile's cover) there is no way
	# out of the blast but behind furniture that shields it.
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 720, 300) },
		{ "key": "south", "type": "kitchen", "rect": Rect2(0, 300, 720, 300) },
	], [{ "pos": Vector2(700, 0), "width": 60.0 }, { "pos": Vector2(700, 600), "width": 60.0 }])
	s.object(&"table", Hiding.low_cover("coffee_table", 52.0), Vector2(230, 150))
	s.object(&"couch", Hiding.low_cover("sofa"), Vector2(230, 450))
	Flank.rules(
		s,
		[{ "pick": "combat" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }],
	)
	for pair in [
			[&"bare_n", BARE_N, BARE_H, &"bare_h"],
			[&"cover_n", COVER_N, COVER_H, &"cover_h"],
	]:
		s.actor(pair[0], &"invader", pair[1], { "facing": Vector2.RIGHT })
		s.set_props(
			pair[0],
			"GoalController",
			{
				"tuning:decision:max_commit_time": 0.4,
				"tuning:decision:tactic_interval": 0.4,
				"tuning:decision:decide_interval": 0.4,
			},
		)
		GrenadeAi.hostile(s, pair[3], pair[2], pair[1])


func run(t: TestContext) -> void:
	for id in [&"bare_n", &"cover_n"]:
		Probe.arm(t.actor(id), 0, 1)
	if not t.require(
			Probe.count(t.actor(&"bare_n"), Probe.FRAG) == 1
				and Probe.count(t.actor(&"cover_n"), Probe.FRAG) == 1,
			"both invaders carry a frag grenade",
	):
		return
	if not await Hiding.duck_after_seen(
			t, [&"bare_h", &"cover_h"], [&"bare_n", &"cover_n"]
	):
		return
	# the tactic level offered at each frame the invader was inside the zone
	var seen := { &"bare": [], &"cover": [] }
	# whether the invader was shielded from a burst at its hostile on a frame GRENADE was offered
	var shadowed := { &"bare": false, &"cover": false }
	var pairs := { &"bare": [&"bare_n", &"bare_h"], &"cover": [&"cover_n", &"cover_h"] }
	var end := t.time + 8.0
	while t.time < end:
		for key in pairs:
			var n := t.actor(pairs[key][0])
			var h := t.actor(pairs[key][1])
			var offered := GrenadeAi.offered(t.controller(pairs[key][0], &"current_act"))
			if (not offered.is_empty()
					and n.global_position.distance_to(h.global_position) <= Probe.FRAG_ZONE - 20.0):
				seen[key].append(offered)
				if offered.has("grenade") and GrenadeAi.shielded(t, h.global_position, n):
					shadowed[key] = true
		await t.frames(1)
	var real := func(key: StringName) -> Array:
		return seen[key].filter(func(o): return o.has("engage") or o.has("advance"))
	if not t.require(
			real.call(&"bare").size() >= 30 and real.call(&"cover").size() >= 30,
			"set-up: both invaders were deciding inside the zone (%d and %d frames)"
				% [real.call(&"bare").size(), real.call(&"cover").size()],
	):
		return
	t.check(
		seen[&"cover"].any(func(o): return o.has("grenade")),
		"the invader with a couch at hand is offered GRENADE",
	)
	t.check(
		seen[&"bare"].any(func(o): return o.has("grenade")),
		"so is the invader with only a coffee table: the table that hides the hostile shields it",
	)
	t.check(
		shadowed[&"bare"] and shadowed[&"cover"],
		"and where each was offered it, the piece between it and its hostile shielded it from a "
			+ "burst there (the blast's own 3D line)",
	)
