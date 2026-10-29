extends GameTest
## D31 rule 4: the command menu's quiet go on a held rally beats the stack's own E17 pick. A puppet
## human leader rallies its two NPC teammates at the bare Terrace house's back door and holds the
## threshold in slot 1; once both stand ready, gunfire is heard in the kitchen (which would turn a
## stack carrying a stun into a bang one, E17), and the leader gives "Go into the kitchen (quiet)".
## No grenade is thrown; both AIs go in, the human not waited for (it never steps in).
##
## Real Von, the whole pipeline; no switch. Each NPC carries one stun, as a match arms an invader:
## the premise that a bang could be thrown. The gunfire is a `hit` event nobody known fired, in the
## kitchen.

const Rally := preload("res://tests/_ai/rally_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
## How long (s) the stack is held, with the kitchen suspect, before the go.
const HELD := 3.0
## How long (s) each NPC has to hear the gunfire.
const HEAR_WITHIN := 1.0
## How near (px) a gunfire lead lies to where the shot landed for it to be that shot's.
const HEARD_NEAR := 8.0
## How long (s) the AIs have, once the go is given, to be in.
const IN_WITHIN := 25.0


func describe() -> Dictionary:
	return {
		"name": "A human leader's rally goes in quiet on the menu's quiet go",
		"description": "A puppet human leader rallies its two NPC teammates at the back door and "
			+ "holds; gunfire is heard in the kitchen, then it gives the quiet go: no grenade, "
			+ "both AIs go in without waiting for the human.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "grenade", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Rally.world(s)


func run(t: TestContext) -> void:
	if not Rally.arm(t, 1, 0):
		return
	var w := FollowWatch.new_watch()
	if not await Rally.rallied(t, w):
		return
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	var heard := func() -> bool: return Rally.members(t).all(_heard_kitchen_gunfire)
	if not t.require(
			await t.until(heard, HEAR_WITHIN),
			"premise: both NPCs heard the gunfire in the kitchen (a reason to suspect it, E17)",
	):
		return
	await t.seconds(HELD)
	if Rally.menu_go(t, "quiet").is_empty():
		return
	await Rally.both_in(t, w, IN_WITHIN)
	t.check(
		Grenades.booms(t).is_empty() and not t.happened(&"throw"),
		"no grenade was thrown (bursts %s)" % str(Grenades.booms(t).map(func(e): return e["data"])),
	)
	Rally.check_went_without_human(t)


## Whether NPC `m` holds a gunfire lead where the kitchen's gunfire landed.
func _heard_kitchen_gunfire(m: Node) -> bool:
	var b := Follow.brain_of(m)
	return b != null and (b.debug_memory().get("gunfire", []) as Array).any(
		func(g): return (g["pos"] as Vector2).distance_to(Maps.KITCHEN_CENTRE) <= HEARD_NEAR,
	)
