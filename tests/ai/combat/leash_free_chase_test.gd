extends GameTest
## LD23's contrast: what the leash holds back. The world of `leash_no_chase` (the open hall, the
## puppet standing where that test's leader stands, the invader NPC beside it, the household target
## in plain sight of both) with no squad built or bound: the NPC follows nobody and has no leash
## (LD19). It fights the target; the target flees, walking straight away far down the hall, and the
## NPC goes after it, past the leash and a body's give from where the puppet stands. So in
## `leash_no_chase`, the same world with the squad bound, a follower that stays within the leash is
## held there by the leash, not by a target never worth chasing.
##
## Real Von, the whole pipeline; no switch (`Follow.chase_hall`). Premises: the target and the
## puppet are never killed (`max_health`), and the target, a puppet, never shoots.

const Follow := preload("res://tests/_ai/follow_probe.gd")
## How long (s) the chase is watched (as `leash_no_chase` watches it).
const WATCH_S := 15.0


func describe() -> Dictionary:
	return {
		"name": "An NPC with no squad chases a fleeing target past the leash",
		"description": "The world of leash_no_chase with no squad bound: the invader fights its "
			+ "target and goes after it as it flees, farther than the leash from the puppet.",
		"tags": ["ai", "combat", "squad", "leash", "leadership", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Follow.chase_hall(s)


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	if not t.require(
			await t.until(func(): return Follow.act(m).begins_with("combat"), 10.0),
			"the NPC fights the target in sight (act %s)" % Follow.act(m),
	):
		return
	t.puppet(&"target").walk_to(Follow.CHASE_FLEE_TO)
	var farthest := [0.0, ""]  # the farthest the NPC stood from the puppet, and its act then
	var each := func(_rec: Dictionary) -> void:
		var d: float = m.global_position.distance_to(me.global_position)
		t.trace("from puppet", d)
		if d > float(farthest[0]):
			farthest[0] = d
			farthest[1] = Follow.act(m)
	var w: Dictionary = await Follow.watch(t, [me, m], null, WATCH_S, Callable(), each)

	if not t.require(
			t.actor(&"target").global_position.distance_to(me.global_position) > Follow.LEASH * 2.0,
			"premise: the target fled far past the leash (%.0f px from the puppet)"
				% t.actor(&"target").global_position.distance_to(me.global_position),
	):
		return
	t.check(
		float(farthest[0]) > Follow.LEASH + Follow.CHASE_GIVE,
		"the NPC went after the target past the leash: farthest %.0f px from the puppet (leash "
			% farthest[0] + "%.0f + %.0f) act then %s; acts %s"
			% [Follow.LEASH, Follow.CHASE_GIVE, farthest[1], Follow.acts_of(w, m)],
	)
