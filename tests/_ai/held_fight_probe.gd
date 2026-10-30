extends RefCounted
## Shared helpers for the held-stack fight tests (not a test itself):
## `const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")`. A stack held at the bare
## Terrace house's back door for its leader's go (`docs/leadership.md` LD13, D31) is shot at by a
## defender in the kitchen it is held to enter: `defender` declares it out of sight of the garden,
## `fight` walks it into view of the stack through the doorway (`IN_VIEW` by default: the stack's
## north slots), has it fire at the stack, then walks it back out of sight (a hostile lost in the
## room the stack is held to enter), while it watches the members, and `check_stack_side` asserts
## they fought from the stack's side of the doorway only: none stood in the room, nor walked for
## it, and once the fight lapsed each was back in its slot.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
## Where the defender waits, in the kitchen's north-west, out of sight of the back garden.
const HIDDEN := Vector2(560, 90)
## Where it fights from by default: in the kitchen's south-east, in view through the back door of
## the stack's north slots (and they of it).
const IN_VIEW := Vector2(790, 335)
## How often (s) the defender fires while in view.
const FIRE_EVERY := 0.6
## How long (s) the defender fires at the held stack.
const FIGHT := 10.0
## How long (s) the stack is watched once the defender is out of sight again.
const AFTER := 15.0
## How long (s) past `AFTER` the watch goes on while a member is not back in its slot yet: one the
## fight took far off (a retreat through the house) walks back once its order resumes.
const BACK_WITHIN := 20.0
## Within this (px) of its slot's point a member stands in its slot (an NPC's 6 px slot reach,
## `docs/tactical-entry.md` E2, and a few px).
const SLOT_NEAR := 10.0


## Declare the defender `id`: a household puppet at `HIDDEN`, never killed (the premise: the stack
## must hold through a fight it cannot win).
static func defender(s: TestSetup, id: StringName) -> void:
	Entry.target(s, id, HIDDEN, Vector2(840, 190))


## Arm the defender `id` with a pistol, as a match arms a defender.
static func arm(t: TestContext, id: StringName) -> void:
	Grenades.arm(t.actor(id), 0, 0, &"pistol")


## Walk the defender `id` to `spot`, in view of the stack, and have it fire at `members[0]` every
## `FIRE_EVERY` s for `FIGHT` s, then walk it back out of sight to `HIDDEN` and watch `AFTER` s
## more (until every member is back in its slot, at most `BACK_WITHIN` s past that), sampling the
## `members` (characters) every frame. Returns `{ in_room: { node: first time }, heading: { node:
## [time, act, target] }, fired: { node: shots from outside }, acts: { node: [[time, act]] },
## back: { node: time }, lapsing: true }`: when each first stood in the kitchen, when its walk
## first headed into it (and on which act, to where), how many rounds each fired from the stack's
## side of the doorway, each act it took on the way, and when, once the defender was out of sight,
## each first stood in its slot again, back on its stack order (`lapsing`: that watch has begun).
static func fight(
		t: TestContext,
		id: StringName,
		members: Array,
		spot: Vector2 = IN_VIEW,
) -> Dictionary:
	var puppet := t.puppet(id)
	puppet.walk_to(spot)
	var out := { "in_room": {}, "heading": {}, "fired": {}, "acts": {}, "back": {} }
	var clock := { "next": 0.0 }
	var firing := func() -> bool:
		_sample(t, members, out)
		if puppet.has_arrived() and t.time >= clock["next"]:
			clock["next"] = t.time + FIRE_EVERY
			puppet.aim_at(members[0])
			puppet.shoot()
		return false
	await t.until(firing, FIGHT)
	puppet.walk_to(HIDDEN)
	out["lapsing"] = true
	var lapsed_at := t.time
	var watched := func() -> bool:
		_sample(t, members, out)
		return (t.time - lapsed_at >= AFTER
				and members.all(func(m): return out["back"].has(m)))
	await t.until(watched, AFTER + BACK_WITHIN)
	for m: Node in members:
		out["fired"][m] = t.events.filter(func(e): return (
			e["topic"] == &"shot"
				and e["data"].get("attacker") == m
				and Entry.outward(Entry.BACK, e["data"]["position"]) > 0.0
		)).size()
	return out


## The members held through the fight `seen` (`fight`) fought from the stack's side of the doorway:
## at least one fired from there, none stood in the kitchen nor walked for it, none radioed going in
## (`opening`); and once the fight lapsed (the defender out of sight), each was back in its slot.
static func check_stack_side(t: TestContext, members: Array, seen: Dictionary) -> void:
	var opening := String(Entry.BACK["id"])
	t.check(
		members.any(func(m): return int(seen["fired"].get(m, 0)) > 0),
		"a held member fired at the defender from the stack's side of the doorway (rounds %s; "
			% str(members.map(func(m): return [m.name, seen["fired"].get(m, 0)]))
			+ "acts %s)" % str(members.map(func(m): return [m.name, seen["acts"].get(m, [])])),
	)
	for m: Node in members:
		t.check(
			not seen["in_room"].has(m),
			"%s never stood in the kitchen while held (first at %s s; acts %s)"
				% [m.name, str(seen["in_room"].get(m, "-")), str(seen["acts"].get(m, []))],
		)
		t.check(
			not seen["heading"].has(m),
			"%s's walks kept out of the kitchen while held (first headed in: %s)"
				% [m.name, str(seen["heading"].get(m, "-"))],
		)
		t.check(
			Entry.calls(t, "going_in").filter(func(d): return (
				d.get("speaker") == m and String(d.get("opening", "")) == opening
			)).is_empty(),
			"%s never radioed going in by the back door while held" % m.name,
		)
		t.check(
			seen["back"].has(m),
			"%s was back in its slot once the fight lapsed (at %s s; acts %s)"
				% [m.name, str(seen["back"].get(m, "-")), str(seen["acts"].get(m, []))],
		)


## Note in `out` the first time each of `members` stood in the kitchen, the first time its walk
## headed into it, each new act it took and, once the fight lapses (`lapsing`), the first time it
## stood in its slot again on its stack order's entry (its act the order's stack, within `SLOT_NEAR`
## of its slot's point).
static func _sample(t: TestContext, members: Array, out: Dictionary) -> void:
	for m: Node in members:
		if not out["in_room"].has(m) and Entry.in_room(Entry.BACK, m.global_position):
			out["in_room"][m] = t.time
		var to := Follow.walk_target(m)
		if not out["heading"].has(m) and to != Vector2.INF and Entry.in_room(Entry.BACK, to):
			out["heading"][m] = [snappedf(t.time, 0.1), Follow.act(m), to.round()]
		var acts: Array = out["acts"].get_or_add(m, [])
		var act := Follow.act(m)
		if act != "" and (acts.is_empty() or acts.back()[1] != act):
			acts.append([snappedf(t.time, 0.1), act])
		if out.get("lapsing", false) and not out["back"].has(m):
			var e := Entry.entry(Follow.brain_of(m))
			var slot: Vector2 = e.get("stack_point", Vector2.INF)
			if (act.begins_with("order/stack")
					and String(e.get("opening", "")) == String(Entry.BACK["id"])
					and slot != Vector2.INF and m.global_position.distance_to(slot) <= SLOT_NEAR):
				out["back"][m] = snappedf(t.time, 0.1)
