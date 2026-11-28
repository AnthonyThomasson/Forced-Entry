extends RefCounted
## Fixtures for tests whose hostile "hides behind" furniture (not a test itself):
## `const Hiding := preload("res://tests/_ai/hiding_piece.gd")`. A real desk is below a ducked head
## and a standing hostile behind anything low is seen and shot over it (`docs/gaze-and-fire.md`
## W2), so the hostile the GRENADE tactic is about (`docs/grenades.md` G17: known, with no line of
## fire) is one that was seen, then ducked behind cover that hides a ducked body: known and
## remembered, neither seen nor shootable.

## How tall (px) the cover is: over a ducked head (35.9), under a standing muzzle (65.5).
const COVER_HEIGHT := 44.0


## A catalogue piece `key` with the same footprint and weight but a real top of `height`
## (`COVER_HEIGHT`), drawn as a solid block (a table's top stands on legs a ducked body shows
## under): cover a ducked body hides behind, where a desk is not.
static func low_cover(key: String, height := COVER_HEIGHT) -> Dictionary:
	var def: Dictionary = WorldGen.object_definition(key).duplicate(true)
	def["art"] = "cabinet"
	def["art_opts"] = { "height": height }
	return def


## Von is out from the first frame (every ask fails and the NPCs hold), until `duck_after_seen` has
## the hostile hidden: no decision is made, or in flight, on a hostile standing in view.
static func von_out(s: TestSetup) -> void:
	s.set_static(DecisionStub, &"fail", true)


## Wait until `watcher` (an NPC's actor id, or an array of them) all see a hostile, then have
## `hostile` (an actor id, or an array of them) duck and settle in its crouch: each watcher keeps
## the hostiles as last-seen contacts behind their cover. The watchers stand still meanwhile, and
## Von (out since `von_out`) comes back once the hostiles are hidden. True once they ducked, false
## (the test fails) if a watcher never saw one.
static func duck_after_seen(t: TestContext, hostile: Variant, watcher: Variant) -> bool:
	var ids: Array = hostile if hostile is Array else [hostile]
	var who: Array = watcher if watcher is Array else [watcher]
	var speeds := {}
	for id: StringName in who:
		speeds[id] = t.actor(id).movement.speed
		t.actor(id).movement.speed = 0.0
	var in_view := func(id: StringName) -> bool:
		return (t.controller(id, &"debug_state").debug_state().get("contacts", []) as Array).any(
			func(c): return c.get("hostile", false) and c.get("visible", false)
		)
	var found: bool = await t.until(
		func() -> bool: return who.all(func(id): return in_view.call(id)), 5.0
	)
	if t.require(found, "set-up: %s see the hostile %s before it ducks" % [who, ids]):
		for id: StringName in ids:
			var movement = t.actor(id).movement
			await t.until(
				func() -> bool:
					return movement.set_posture(&"crouch") or movement.posture() == &"crouch",
				3.0,
			)
		var hidden := func() -> bool:
			return who.all(func(w): return (
				not in_view.call(w)
				and ids.all(
					func(id): return SightRay.visible_parts(t.actor(w), t.actor(id)).is_empty()
				)
			))
		await t.until(hidden, 3.0)
		await t.seconds(1.0)
	DecisionStub.fail = false
	DecisionStub.requests.clear()
	for id: StringName in who:
		t.actor(id).movement.speed = speeds[id]
	return found
