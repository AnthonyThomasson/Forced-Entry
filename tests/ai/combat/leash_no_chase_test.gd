extends GameTest
## LD23 (`docs/leadership.md`): fighting stays with the leader. A puppet stands in for the human
## leader of a squad of one invader NPC (bound as Main binds it), standing in an open hall. A
## household target is in plain sight of both; the NPC fights it. Then the target flees, walking
## straight away far past the leash (`LEASH` 320 px of the leader's live position). The NPC does
## not chase it out of the leash: its COMBAT options beyond the leash are not offered and its
## combat spots stay within it, so it never stands more than the leash (and a body's give) from its
## leader. The contrast, the same world with no squad bound, is `leash_free_chase`: there the NPC
## goes after the target past the leash, so the leash is what holds this one back.
##
## Real Von, the whole pipeline; no switch (`Follow.chase_hall`). Premises: the leash is LD23's, the
## target and the leader are never killed (`max_health`) and the target, a puppet, never shoots.

const Follow := preload("res://tests/_ai/follow_probe.gd")
## How long (s) the chase is watched.
const WATCH_S := 15.0


func describe() -> Dictionary:
	return {
		"name": "A member does not chase a fleeing target out of the leash",
		"description": "An invader fighting beside its human leader sees its target flee far down "
			+ "the hall: it never goes farther than the leash from the leader.",
		"tags": ["ai", "combat", "squad", "leash", "leadership", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Follow.chase_hall(s)
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	if not t.require(
			is_equal_approx(squad.leash, Follow.LEASH),
			"premise: the squad's leash is %.0f px (Squad.leash: %.0f)" % [
				Follow.LEASH,
				squad.leash,
			],
	):
		return
	if not t.require(
			await t.until(func(): return Follow.act(m).begins_with("combat"), 10.0),
			"the NPC fights the target in sight (act %s)" % Follow.act(m),
	):
		return
	t.puppet(&"target").walk_to(Follow.CHASE_FLEE_TO)
	var farthest := [0.0, ""]  # the farthest the NPC stood from its leader, and its act then
	var each := func(_rec: Dictionary) -> void:
		var d: float = m.global_position.distance_to(me.global_position)
		t.trace("from leader", d)
		if d > float(farthest[0]):
			farthest[0] = d
			farthest[1] = Follow.act(m)
	var w: Dictionary = await Follow.watch(t, [me, m], squad, WATCH_S, Callable(), each)

	if not t.require(
			t.actor(&"target").global_position.distance_to(me.global_position) > Follow.LEASH * 2.0,
			"premise: the target fled far past the leash (%.0f px from the leader)"
				% t.actor(&"target").global_position.distance_to(me.global_position),
	):
		return
	t.check(
		float(farthest[0]) <= Follow.LEASH + Follow.CHASE_GIVE,
		"the NPC never chased past the leash: farthest %.0f px from the leader (leash %.0f + %.0f)"
			% [farthest[0], Follow.LEASH, Follow.CHASE_GIVE] + " act then %s; acts %s"
			% [farthest[1], Follow.acts_of(w, m)],
	)
