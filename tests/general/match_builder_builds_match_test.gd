extends GameTest
## The match-assembly module (`MatchBuilder.populate`, declared with `s.match`, read with
## `t.match()`): a match populated on a generated house is the match Main plays. The handle's
## world, rooms and openings are those of the house; each side has its count; the invaders carry
## Main's default kit (1 stun, 1 frag, a steel III plate front and back: `docs/outfits.md` O11) and
## are one police unit (`zenitex` or `trauma`, O15) ranked lead (2), sergeant (1), the rest troopers
## (0) in spawn order; one squad per faction, led by the rank rule (`docs/leadership.md` LD3: the
## highest rank, the first spawned among equals); and every NPC's controller has the house's rooms
## and openings and its side's squad, an invader the front entrance as its `entry_point`.
##
## The controllers are read at the start of `run`, before their first tick (a controller hands its
## `entry_point` to its perception on it). Von is down: the NPCs hold steady.

const SEED := 18
const ENTRANCE := Vector2(440, 350)
const DEFENDERS := 2
const INVADERS := 3
## The police units' styles (`docs/outfits.md` O15).
const POLICE_UNITS := [&"zenitex", &"trauma"]
## The plate Main's invaders wear front and back (O11).
const PLATE := &"steel_iii"


func describe() -> Dictionary:
	return {
		"name": "MatchBuilder builds the match Main plays",
		"description": "A match declared with s.match on a generated house: the handle names the "
			+ "house's world, rooms and openings; each side has its count; the invaders carry a "
			+ "stun, a frag and plates and are one police unit ranked lead and sergeant; one squad "
			+ "per side led by the rank rule; every NPC bound to the house and its squad.",
		"tags": ["setup", "match", "spawn", "squad", "leadership"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, "", ENTRANCE)
	s.von_down()
	s.match({ "defenders": { "count": DEFENDERS }, "invaders": { "count": INVADERS } })


func run(t: TestContext) -> void:
	var handle: Dictionary = t.match()
	if not t.require(not handle.is_empty(), "t.match() returns the match's handle"):
		return
	var brains := {}
	for c in handle.get("combatants", []):
		brains[c] = TestContext.controller_of(c)
	var openings: Array = t.world.get("openings")
	if not t.require(
			handle.get("world") == t.world and handle.get("house") == t.world.get("house"),
			"premise: the handle names the test world and its house",
	):
		return
	t.check(handle.get("rooms") == t.rooms, "the handle's rooms are the house's")
	t.check(handle.get("openings") == openings, "the handle's openings are the house's")
	var front := _front(openings)
	if not t.require(front != Vector2.ZERO, "premise: the house has a front entrance"):
		return

	var combatants: Array = handle.get("combatants", [])
	var defenders := _side(combatants, MatchBuilder.DEFENDER_FACTION)
	var invaders := _side(combatants, MatchBuilder.INVADER_FACTION)
	t.expect_eq(defenders.size(), DEFENDERS, "the defenders number their count")
	t.expect_eq(invaders.size(), INVADERS, "the invaders number their count")
	t.expect_eq(combatants.size(), DEFENDERS + INVADERS, "nobody else is in the match")
	_check_kit(t, defenders, invaders)
	_check_squads(t, handle.get("squads", {}), defenders, invaders)
	_check_bound(t, handle, brains, front)


## The position of the front entrance among `openings`, `Vector2.ZERO` with none.
func _front(openings: Array) -> Vector2:
	var front := Vector2.ZERO
	for o: Dictionary in openings:
		if o.get("front", false):
			front = o["pos"]
	return front


## The `combatants` of `faction`, in spawn order.
func _side(combatants: Array, faction: StringName) -> Array:
	return combatants.filter(func(c): return c.get("faction") == faction)


## The invaders carry Main's default kit and are one police unit ranked in spawn order; the
## defenders carry no grenades.
func _check_kit(t: TestContext, defenders: Array, invaders: Array) -> void:
	for c in invaders:
		t.expect_eq(c.item_count(ItemRegistry.STUN_SLOT), 1, "%s carries one stun" % c.name)
		t.expect_eq(c.item_count(ItemRegistry.FRAG_SLOT), 1, "%s carries one frag" % c.name)
		var kit: Dictionary = c.outfit_view()
		t.check(
			kit["front_plate"]["type"] == PLATE and kit["back_plate"]["type"] == PLATE,
			"%s wears a steel III plate front and back (%s, %s)"
				% [c.name, kit["front_plate"]["type"], kit["back_plate"]["type"]],
		)
	for c in defenders:
		t.check(
			c.item_count(ItemRegistry.STUN_SLOT) == 0 and c.item_count(ItemRegistry.FRAG_SLOT) == 0,
			"defender %s carries no grenades" % c.name,
		)
	var unit: StringName = invaders[0].style if not invaders.is_empty() else &""
	t.check(POLICE_UNITS.has(unit), "the invaders are a police unit (%s)" % unit)
	t.check(
		invaders.all(func(c): return c.style == unit),
		"every invader wears the one unit's style (%s)"
			% str(invaders.map(func(c): return c.style)),
	)
	t.expect_eq(
		invaders.map(func(c): return c.rank),
		[2, 1, 0],
		"the invaders are ranked lead, sergeant, trooper in spawn order",
	)


## One squad per faction in `squads`, each over its side's NPCs and led by the rank rule.
func _check_squads(t: TestContext, squads: Dictionary, defenders: Array, invaders: Array) -> void:
	t.expect_eq(squads.size(), 2, "one squad per faction")
	var sides := {
		MatchBuilder.DEFENDER_FACTION: defenders,
		MatchBuilder.INVADER_FACTION: invaders,
	}
	for faction in sides:
		var squad: Node = squads.get(faction)
		if not t.check(squad != null, "the %s side has a squad" % faction):
			continue
		var members: Array = sides[faction]
		t.check(squad.members() == members, "the %s squad is that side's NPCs" % faction)
		t.check(
			squad.leader() == members[0],
			"the %s squad is led by %s by the rank rule (led by %s)"
				% [faction, members[0].name, squad.leader().name if squad.leader() else "nobody"],
		)


## Every combatant of `handle`'s controller (in `brains`, read before their first tick) has the
## house's rooms and openings and its side's squad, an invader the `front` entrance as its
## `entry_point`.
func _check_bound(t: TestContext, handle: Dictionary, brains: Dictionary, front: Vector2) -> void:
	var combatants: Array = handle.get("combatants", [])
	var openings: Array = t.world.get("openings")
	var squads: Dictionary = handle.get("squads", {})
	for c in combatants:
		var brain: Node = brains[c]
		if not t.check(brain != null, "%s has a controller" % c.name):
			continue
		t.check(brain.rooms == t.rooms, "%s's controller has the house's rooms" % c.name)
		t.check(brain.openings == openings, "%s's controller has the house's openings" % c.name)
		t.check(
			brain.squad == squads.get(c.get("faction")),
			"%s's controller has its side's squad" % c.name,
		)
	for c in _side(combatants, MatchBuilder.INVADER_FACTION):
		t.check(
			brains[c] != null and brains[c].entry_point == front,
			"invader %s heads for the front entrance %s (entry_point %s)"
				% [c.name, str(front), str(brains[c].entry_point if brains[c] else null)],
		)
