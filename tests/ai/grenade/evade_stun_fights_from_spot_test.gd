extends GameTest
## G16, fighting through a stun (issue #158): an NPC evading a stun still fights the hostiles in its
## sight while it holds its spot for the bang, or stands with no spot it can reach in time, and
## faces them even though its back to the stun would blind it less. A defender in an open arena has
## a stun thrown 250 px from it, inside the flash radius (400 px); a second invader stands west of
## it, in view of where it holds. Before the bang it shoots at that invader.
##
## Scripted Von (one mechanism: the evade reflex, outside Von, and the watch stage). Premises: both
## invaders are puppets that cannot be killed; the defender is armed with a pistol, as the match
## builder arms a spawn.

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
		"name": "An NPC evading a stun fights from its spot",
		"description": "A defender evades a stun with an invader in view of where it holds: "
			+ "before the bang it turns on the invader and shoots.",
		"tags": ["ai", "grenade", "evade", "stun", "scripted"],
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
	await EvadeFight.check(t, Probe.STUN, AIM, AT_SPOT)
