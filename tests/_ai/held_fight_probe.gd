extends RefCounted
## Shared helpers for the held-stack fight tests (not a test itself):
## `const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")`. A stack held at the bare
## Terrace house's back door for its leader's go (`docs/leadership.md` LD13, D31) is shot at by a
## defender in the kitchen it is held to enter: `defender` declares it out of sight of the garden,
## `fight` walks it into view of the stack's north slots through the doorway, has it fire at the
## stack, then walks it back out of sight (a hostile lost in the room the stack is held to enter),
## while it watches the members, and `check_stack_side` asserts they fought from the stack's side
## of the doorway only: none stood in the room, nor walked for it.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
## Where the defender waits, in the kitchen's north-west, out of sight of the back garden.
const HIDDEN := Vector2(560, 90)
## Where it fights from: in the kitchen's south-east, in view through the back door of the stack's
## north slots (and they of it).
const IN_VIEW := Vector2(790, 335)
## How often (s) the defender fires while in view.
const FIRE_EVERY := 0.6


## Declare the defender `id`: a household puppet at `HIDDEN`, never killed (the premise: the stack
## must hold through a fight it cannot win).
static func defender(s: TestSetup, id: StringName) -> void:
	Entry.target(s, id, HIDDEN, Vector2(840, 190))


## Arm the defender `id` with a pistol, as a match arms a defender.
static func arm(t: TestContext, id: StringName) -> void:
	Grenades.arm(t.actor(id), 0, 0, &"pistol")


## Walk the defender `id` into view and have it fire at `members[0]` every `FIRE_EVERY` s for
## `secs` s, then walk it back out of sight to `HIDDEN` and watch `after` s more, sampling the
## `members` (characters) every frame. Returns `{ in_room: { node: first time }, heading: { node:
## [time, act, target] }, fired: { node: shots from outside }, acts: { node: [[time, act]] } }`:
## when each first stood in the kitchen, when its walk first headed into it (and on which act, to
## where), how many rounds each fired from the stack's side of the doorway, and each act it took on
## the way.
static func fight(
		t: TestContext,
		id: StringName,
		members: Array,
		secs: float,
		after: float,
) -> Dictionary:
	var puppet := t.puppet(id)
	puppet.walk_to(IN_VIEW)
	var out := { "in_room": {}, "heading": {}, "fired": {}, "acts": {} }
	var clock := { "next": 0.0 }
	var firing := func() -> bool:
		_sample(t, members, out)
		if puppet.has_arrived() and t.time >= clock["next"]:
			clock["next"] = t.time + FIRE_EVERY
			puppet.aim_at(members[0])
			puppet.shoot()
		return false
	await t.until(firing, secs)
	puppet.walk_to(HIDDEN)
	await t.until(func() -> bool: _sample(t, members, out); return false, after)
	for m: Node in members:
		out["fired"][m] = t.events.filter(func(e): return (
			e["topic"] == &"shot"
				and e["data"].get("attacker") == m
				and Entry.outward(Entry.BACK, e["data"]["position"]) > 0.0
		)).size()
	return out


## The members held through the fight `seen` (`fight`) fought from the stack's side of the doorway:
## at least one fired from there, none stood in the kitchen nor walked for it, none radioed going in
## (`opening`).
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


## Note in `out` the first time each of `members` stood in the kitchen, the first time its walk
## headed into it, and each new act it took.
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
