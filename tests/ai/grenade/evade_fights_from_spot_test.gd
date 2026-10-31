extends GameTest
## G16, fighting from the spot (issue #158): an NPC that has got clear of a live grenade still
## fights the hostiles in its sight while it holds its spot for the burst. A defender in an open
## arena has a frag thrown 250 px from it, inside the danger zone (370 px); it runs west out of the
## zone. A second invader stands west of it, in view of the way it runs and of the spot it holds:
## once the defender is holding its spot, and before the burst, it shoots at that invader.
##
## Scripted Von (one mechanism: the evade reflex, outside Von, and the watch stage). Premises: both
## invaders are puppets that cannot be killed; the defender is armed with a pistol, as the match
## builder arms a spawn, and cannot be killed (the burst is not what is tested).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const EvadeFight := preload("res://tests/_ai/evade_fight_probe.gd")
const NPC_AT := Vector2(600, 250)
const THROWER_AT := Vector2(1000, 250)
const AIM := Vector2(850, 250)
const TARGET_AT := Vector2(180, 170)
## How close (px) the defender stands to its planned spot to count as holding it: the evade walks
## all the way in (G16), with a few px for the body's last stride.
const AT_SPOT := 10.0


func describe() -> Dictionary:
	return {
		"name": "An NPC clear of a frag fights from its spot",
		"description": "A defender runs clear of a frag with an invader in view of its spot: "
			+ "holding the spot, before the burst, it shoots at the invader.",
		"tags": ["ai", "grenade", "evade", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 500))
	s.switch(&"projectile.flyover", false)
	s.von_script([{ "pick": "hold" }])
	s.actor(&"d", &"defender", NPC_AT, { "facing": Vector2.RIGHT, "max_health": 1_000_000.0 })
	s.actor(
		&"thrower",
		&"puppet",
		THROWER_AT,
		{ "faction": &"invader", "max_health": 1_000_000.0, "movement:aim_point": AIM },
	)
	s.actor(
		&"target",
		&"puppet",
		TARGET_AT,
		{ "faction": &"invader", "max_health": 1_000_000.0, "movement:aim_point": NPC_AT },
	)


func run(t: TestContext) -> void:
	await EvadeFight.check(t, Probe.FRAG, AIM, AT_SPOT)
