extends GameTest
## LD19: an NPC with no squad (no `squad` handed to its controller) follows nobody and decides on
## its own. One invader in the back garden of the bare Terrace house, no squad built or bound: it
## decides through Von (its root level is asked, never taken as FOLLOW), knows it is no follower
## (its snapshot's `follows` fact is false), never carries out FOLLOW, and searches the house on its
## own: it claims a doorway of its own choosing and goes in.
##
## Real Von, the whole pipeline; no switch.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const WATCH_S := 40.0


func describe() -> Dictionary:
	return {
		"name": "An invader with no squad decides on its own",
		"description": "One invader with no squad bound asks Von, has the follows fact false, "
			+ "never follows, and searches the house by an entry of its own.",
		"tags": ["ai", "movement", "squad", "follow", "von"],
		"requires_von": true,
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"inv", &"invader", Vector2(960, 60))


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := Follow.brain_of(inv)
	t.check(brain.get("squad") == null, "premise: no squad was handed to its controller")
	var went_in := func(_rec: Dictionary) -> bool:
		return not Follow.calls_of(t, inv, "going_in").is_empty()
	var w: Dictionary = await Follow.watch(t, [inv], null, WATCH_S, went_in)

	if not t.require(
			Follow.asked(w, inv) > 0,
			"it decided through Von (asked %d; acts %s)" % [
				Follow.asked(w, inv),
				Follow.acts_of(w, inv),
			],
	):
		return
	var facts: Dictionary = brain.debug_state().get("facts", {})
	t.check(
		facts.has("follows") and facts["follows"] == false,
		"its snapshot has the follows fact, false (facts %s)" % str(facts.keys()),
	)
	t.check(
		not Follow.took(w, inv, "follow"),
		"it never followed (acts %s)" % Follow.acts_of(w, inv),
	)
	t.check(
		Follow.took(w, inv, "search"),
		"it searched the house on its own (acts %s)" % Follow.acts_of(w, inv),
	)
	var claims := Follow.calls_of(t, inv, "claim")
	t.check(
		not claims.is_empty() and str(claims[0]["data"].get("order_id", "")) == "",
		"it claimed a doorway by an entry of its own, under no order (%d claims)" % claims.size(),
	)
	t.check(
		not Follow.calls_of(t, inv, "going_in").is_empty(),
		"and went in (acts %s)" % Follow.acts_of(w, inv),
	)
