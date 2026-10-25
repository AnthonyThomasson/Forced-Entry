extends GameTest
## Ticket #95: a test world's `invader` is bound as a match's invader is (`MatchBuilder.bind_npc`
## with the front entrance as its `entry_point`), and a setup that declares its squads
## (`s.squads()`) gets them built and bound as a match's (`MatchBuilder.build_squads`). On the
## Terrace house (`Maps.house`, bare), an invader outside is offered "the front entrance" as where
## to search (the option `entrance`, at its entry point); with the squads declared, its partner
## follows it (`Squad.follows`) and walks after it (a FOLLOW walk, `docs/leadership.md` LD19).
##
## Premise: tactical entry is off for both (`ai.entry`). The entrance is a SEARCH option offered
## only while ENTER has no doorway to offer, and outside the house ENTER always offers its outer
## doorways while entry is on.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
## Where the two invaders start: in the garden west of the front door, out of the house.
const LEAD_AT := Vector2(-160, 415)
const PARTNER_AT := Vector2(-200, 520)
## How far (px) the partner walks after its leader, at the least: two of its steps.
const WALKED := 40.0


func describe() -> Dictionary:
	return {
		"name": "A test-world invader is bound as a match's invader",
		"description": "An invader in a test world is offered the front entrance (its entry point, "
			+ "as a match invader's), and with the squads declared its partner follows it.",
		"tags": ["setup", "match", "squad", "leadership"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.switch(&"ai.entry", false)
	s.von_script([{ "pick": "search" }, { "pick": "entrance" }])
	s.actor(&"lead", &"invader", LEAD_AT)
	s.set_props(&"lead", "Wardrobe", { "rank": 2 })
	s.actor(&"partner", &"invader", PARTNER_AT)
	s.squads()


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	if not t.require(squad != null, "premise: the invaders' squad is built"):
		return
	t.require(
		squad.leader() == t.actor(&"lead") and squad.follows(t.actor(&"partner")),
		"premise: the lead leads the squad and the partner follows it",
	)
	var partner := t.actor(&"partner")
	var followed := [false]
	var walked := [0.0]
	await t.until(
		func():
			if Follow.following(partner):
				followed[0] = true
				walked[0] = maxf(walked[0], partner.global_position.distance_to(PARTNER_AT))
			return _offered(t, "entrance") and followed[0] and walked[0] >= WALKED,
		6.0,
	)
	t.check(_offered(t, "entrance"), "the invader is offered the front entrance (entrance)")
	t.check(followed[0], "the partner follows its leader (a FOLLOW leaf)")
	t.check(
		walked[0] >= WALKED,
		"the partner walks after its leader, %.0f px or more (%.0f px)" % [WALKED, walked[0]],
	)


## Whether Von was ever offered the option `id`.
func _offered(t: TestContext, id: String) -> bool:
	return t.von_requests().any(func(r): return (r.get("options", []) as Array).has(id))
