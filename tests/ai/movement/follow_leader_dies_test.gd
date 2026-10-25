extends GameTest
## LD4 and LD19: the leader dies. Three invaders, ranked as Main ranks a unit (lead, sergeant,
## trooper), are a squad bound as Main binds it, in the furnished warehouse (one big room, no
## doorway, so nobody is on a stack order). Gunfire is heard down the hall: the lead investigates it
## through Von and walks off, and the sergeant and the trooper follow it. Then the lead is killed
## (`take_damage`). The sergeant leads within the frame (LD4) and stops following: it gets its own
## modes back (it decides again, on its own cadence, and what it decides is not FOLLOW); the trooper
## re-centres on it (its follow spot and its place come round the sergeant).
##
## Real Von, the whole pipeline; no switch. The premise is the gunfire (a `hit` event nobody known
## fired, as `tests/_ai/investigate_probe.gd` posts it): the open hall, seen whole at once, leaves
## an invader nothing else to go to.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## Where the gunfire is heard: the hall's far north-east, well out of the team's awareness radius.
const GUNFIRE := Vector2(900, 330)
## How long (s) the team is watched following the lead before it dies.
const BEFORE_S := 10.0
## How long (s) the sergeant and the trooper have to take up their new parts after it.
const AFTER_S := 12.0


func describe() -> Dictionary:
	return {
		"name": "When the leader dies the followers re-centre on the next",
		"description": "Three invaders follow their lead in the warehouse; the lead is killed: the "
			+ "sergeant leads, decides on its own again, and the trooper follows the sergeant.",
		"tags": ["ai", "movement", "squad", "follow", "leadership", "von"],
		"requires_von": true,
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	s.actor(&"lead", &"invader", Vector2(330, 400))
	s.set_props(&"lead", "Wardrobe", { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(280, 440))
	s.set_props(&"sergeant", "Wardrobe", { "rank": 1 })
	s.actor(&"trooper", &"invader", Vector2(260, 380))
	s.set_props(&"trooper", "Wardrobe", { "rank": 0 })
	s.squads()


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var lead := t.actor(&"lead")
	var sergeant := t.actor(&"sergeant")
	var trooper := t.actor(&"trooper")
	var nodes: Array = [lead, sergeant, trooper]
	await t.seconds(1.0)
	Investigate.gunfire(GUNFIRE)
	var before: Dictionary = await Follow.watch(t, nodes, squad, BEFORE_S)
	if not _followed(t, squad, before, nodes):
		return

	var decided_before := await _lead_dies(t, squad, lead, sergeant)
	if decided_before < 0:
		return
	var died_at := await _settle(t, squad, sergeant, trooper, decided_before)

	if not _check_settled(t, squad, sergeant, trooper, decided_before):
		return
	t.trace("since death", t.time - died_at)


## Before the death: the lead investigates and the other two follow it; false when a premise fails.
func _followed(t: TestContext, squad: Node, before: Dictionary, nodes: Array) -> bool:
	var lead: Node = nodes[0]
	var sergeant: Node = nodes[1]
	var trooper: Node = nodes[2]
	if not t.require(
			Follow.took(before, lead, "investigate"),
			"the lead investigates the gunfire (acts %s)" % Follow.acts_of(before, lead),
	):
		return false
	if not t.require(
			squad.follows(sergeant) and squad.follows(trooper),
			"premise: the sergeant and the trooper follow the lead (Squad.follows)",
	):
		return false
	t.check(
		Follow.took(before, sergeant, "follow") and Follow.took(before, trooper, "follow"),
		"the sergeant and the trooper follow the lead before it dies (FOLLOW; acts %s / %s)" % [
					Follow.acts_of(before, sergeant),
					Follow.acts_of(before, trooper),
				],
	)
	return true


## The lead dies and the sergeant leads within the frame; the sergeant's decisions before it, or -1
## when the lead is not dead.
func _lead_dies(t: TestContext, squad: Node, lead: Node, sergeant: Node) -> int:
	lead.take_damage(1.0e9)
	if not t.require(lead.is_dead, "the lead is dead"):
		return -1
	var decided_before := _decisions(sergeant)
	await t.frames(1)
	t.check(
		squad.leader() == sergeant,
		"the sergeant leads within the frame (leader %s)" % Follow.name_of(squad.leader()),
	)
	return decided_before


## Waits (at most `AFTER_S`) for the sergeant to decide on its own and the trooper to come round it;
## when the wait began.
func _settle(
		t: TestContext,
		squad: Node,
		sergeant: Node,
		trooper: Node,
		decided_before: int,
) -> float:
	var w := Follow.new_watch()
	var died_at := t.time
	# The trooper is the sergeant's only follower now: the first in its file (`band_p50(0)`).
	var settled := func() -> bool:
		Follow.tick(w, t, [sergeant, trooper], squad)
		var at: Vector2 = squad.follow_spot(trooper)
		return (
			not Follow.following(sergeant)
				and _decisions(sergeant) > decided_before
				and at != Vector2.INF
				and at.distance_to(sergeant.global_position) <= Follow.BAND_P90
				and trooper.global_position.distance_to(sergeant.global_position)
					<= Follow.band_p50(0)
		)
	await t.until(settled, AFTER_S)
	return died_at


## After the death the sergeant decides on its own and the trooper follows round it; false when the
## premise fails.
func _check_settled(
		t: TestContext,
		squad: Node,
		sergeant: Node,
		trooper: Node,
		decided_before: int,
) -> bool:
	if not t.require(
			not squad.follows(sergeant),
			"premise: the new leader no longer follows (Squad.follows(sergeant) false)",
	):
		return false
	t.check(
		not Follow.following(sergeant) and _decisions(sergeant) > decided_before,
		"the sergeant decides on its own again (%d decisions since; act %s)"
			% [_decisions(sergeant) - decided_before, Follow.act(sergeant)],
	)
	var spot: Vector2 = squad.follow_spot(trooper)
	t.check(
		spot != Vector2.INF and spot.distance_to(sergeant.global_position) <= Follow.BAND_P90,
		"the trooper's follow spot is round the sergeant now (%s, %.0f px from it)"
			% [str(spot), spot.distance_to(sergeant.global_position)],
	)
	t.check(
		Follow.following(trooper)
			and trooper.global_position.distance_to(sergeant.global_position) <= Follow.band_p50(0),
		"the trooper re-centres on the sergeant within %.0f s (%.0f px from it; act %s)"
			% [
				AFTER_S,
				trooper.global_position.distance_to(sergeant.global_position),
				Follow.act(trooper),
			],
	)
	return true


## How many decision walks character `c`'s controller has started (`debug_state()["decisions"]`).
func _decisions(c: Node) -> int:
	var b := Follow.brain_of(c)
	return int(b.debug_state().get("decisions", 0)) if b != null else 0
