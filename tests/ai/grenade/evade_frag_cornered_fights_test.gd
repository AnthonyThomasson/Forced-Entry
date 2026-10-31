extends GameTest
## G16, safe first and then the fight, with no spot (issue #158): an NPC caught by a frag with no
## safe spot it can reach in time crouches where it stands, and since its facing is no help against
## the blast it fights the hostile in its sight. A defender that only walks (`run_enabled` off, 150
## px/s) and keeps a wide berth of a frag (`evade_margin` 600 px, so a danger zone of 850 px) stands
## in the middle of a large open floor, its walls (and the walkable ring past them) far out of its
## reach; an invader 350 px off lobs a frag at its feet. The zone is far wider than it can walk in
## the whole fuse (3 s), and there is nothing to hide behind: with no spot, it turns from its back
## to the frag onto the thrower and shoots before the burst.
##
## Scripted Von (one mechanism: the evade reflex, outside Von, and the watch stage). Premises: the
## thrower is a puppet that cannot be killed; the defender is armed with a pistol, as the match
## builder arms a spawn, and cannot be killed (the burst is not what is tested); it has no spot
## (`debug_grenades().escape` is `Vector2.INF` while it evades).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const EvadeFight := preload("res://tests/_ai/evade_fight_probe.gd")
const NPC_AT := Vector2(1500, 1500)
const THROWER_AT := Vector2(1150, 1500)
const AIM := Vector2(1510, 1500)


func describe() -> Dictionary:
	return {
		"name": "An NPC cornered by a frag fights where it stands",
		"description": "A frag lands at the feet of a walking defender with no way clear in "
			+ "time: it crouches where it stands and shoots at the thrower before the burst.",
		"tags": ["ai", "grenade", "evade", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3000, 3000))
	s.switch(&"projectile.flyover", false)
	s.von_script([{ "pick": "hold" }])
	s.actor(&"d", &"defender", NPC_AT, { "facing": Vector2.LEFT, "max_health": 1_000_000.0 })
	s.set_props(
		&"d",
		"GoalController",
		{ "tuning:pace:run_enabled": false, "tuning:grenades:evade_margin": 600.0 },
	)
	s.actor(
		&"thrower",
		&"puppet",
		THROWER_AT,
		{ "faction": &"invader", "max_health": 1_000_000.0, "movement:aim_point": AIM },
	)


func run(t: TestContext) -> void:
	await EvadeFight.check(t, Probe.FRAG, AIM, 0.0, true)
