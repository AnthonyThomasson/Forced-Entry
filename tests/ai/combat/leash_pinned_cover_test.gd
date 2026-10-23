extends GameTest
## LD23's spots: a pinned follower finds cover within the leash, or follows. A puppet stands in for
## the human leader of a squad of one invader NPC (bound as Main binds it), in an open hall, a sofa
## beside it. A household gunman down the hall opens fire on the NPC with an SMG. Under fire, the
## NPC's COMBAT options beyond the leash of its leader's live position are not offered (the far
## retreats, the advances and flanks toward the gunman): it fights from cover within the leash (the
## sofa) or follows, and never stands farther than the leash (and a body's give) from its leader.
##
## Real Von, the whole pipeline; no switch. Premises: nobody is killed (`max_health`), the gunman (a
## puppet) keeps firing at the NPC, and every round flies at a pinned height (`projectile.flyover`
## off: a shot that arrives lands, as in `posture_pinned_crouch`).

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const HALL := Rect2(0, 0, 1700, 900)
const LEAD_AT := Vector2(900, 450)
const NPC_AT := Vector2(960, 470)
const SOFA_AT := Vector2(850, 560)
const GUNMAN_AT := Vector2(1450, 450)
## How long (s) the NPC is watched under fire.
const WATCH_S := 15.0
## A body's give past the leash (px).
const GIVE := 40.0


func describe() -> Dictionary:
	return {
		"name": "A pinned member takes cover within the leash",
		"description": "An invader under fire beside its human leader fights from cover within "
			+ "the leash or follows: it never goes farther than the leash from the leader.",
		"tags": ["ai", "combat", "squad", "leash", "cover", "leadership", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(HALL)
	s.switch(&"projectile.flyover", false)
	s.object(&"sofa", "sofa", SOFA_AT)
	Stack.human(s, &"me", LEAD_AT, { "aim_point": GUNMAN_AT })
	s.actor(&"m", &"invader", NPC_AT, { "max_health": 1_000_000.0 })
	s.actor(
		&"gunman",
		&"puppet",
		GUNMAN_AT,
		{ "faction": &"household", "max_health": 1_000_000.0, "start_slot": 5 },
	)
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	var gunman := t.puppet(&"gunman")
	var gun := t.actor(&"gunman")
	gunman.aim_at(m)
	await t.seconds(0.5)
	gunman.hold_fire(true)
	var farthest := [0.0, ""]  # the farthest the NPC stood from its leader, and its act then
	var each := func(_rec: Dictionary) -> void:
		if gun.ammo() == 0 and not gun.is_reloading():
			gunman.reload()
		var d: float = m.global_position.distance_to(me.global_position)
		t.trace("from leader", d)
		if d > float(farthest[0]):
			farthest[0] = d
			farthest[1] = Follow.act(m)
	var w: Dictionary = await Follow.watch(t, [me, m], squad, WATCH_S, Callable(), each)
	gunman.hold_fire(false)

	if not t.require(
			t.happened(&"hit", func(d): return d.get("attacker") == gun),
			"premise: the gunman's rounds landed (the NPC was under fire)",
	):
		return
	if not t.require(
			Follow.took(w, m, "combat"),
			"the NPC fought under fire (acts %s)" % Follow.acts_of(w, m),
	):
		return
	if not t.require(
			is_equal_approx(squad.leash, Follow.LEASH),
			"premise: the squad's leash is %.0f px (Squad.leash: %.0f)" % [
				Follow.LEASH,
				squad.leash,
			],
	):
		return
	t.check(
		float(farthest[0]) <= Follow.LEASH + GIVE,
		"pinned, the NPC kept to the leash: farthest %.0f px from the leader (leash %.0f + %.0f)"
			% [farthest[0], Follow.LEASH, GIVE] + " act then %s; acts %s"
			% [farthest[1], Follow.acts_of(w, m)],
	)
	t.check(
		m.global_position.distance_to(me.global_position) <= Follow.LEASH,
		"and ends within it, in cover or following (%.0f px from its leader; act %s)"
			% [m.global_position.distance_to(me.global_position), Follow.act(m)],
	)
