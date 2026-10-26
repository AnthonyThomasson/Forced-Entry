extends GameTest
## P1 (`docs/grenades.md`, Performance): grenades going off in a running match keep it smooth. The
## 5v5 match of `perf/match_5v5_stress`, built as Main builds one (`Perf.configure_match`,
## `s.declared_match`: a generated house on its largest plan, the defenders in random rooms, the
## invader team beside the front door, each side with its spec loadout, so the invaders carry their
## plates and a stun and a frag each, styled and ranked, one squad per side; nav re-baker, blood,
## debris, sound and radio on, scripted Von), and once the sides are in contact (after its warm-up,
## a shot fired and some NPC knowing a hostile, `Perf.warm_until_contact`: a premise) a puppet on
## the invaders' side (the human's place) throws three frags and three stuns among the fighters over
## about 3 s, through the controller contract (select the slot, aim, click). The puppet is a test
## actor, not one of the match's: it carries the three of each P1 names (`Probe.arm`), not a side's
## one and one, and waits far off the house until its first throw, out of the warm-up and the
## placement. So the burst's whole cost is in the window: the blast and its fragments, the flash and
## bang, the FX, scorch, blood and debris, the sounds, and every NPC's grenade perception, evade
## planning and re-decision. From the puppet's first throw to 3 s after its last burst the frames
## meet the smooth standard (`Perf.SMOOTH_*`); a grenade an NPC throws meanwhile is part of the
## load. The camera frames the fighters as Main's spectator view does, on a player's screen, so
## every body a player would see is drawn. Headless measures the CPU only (the drawing calls
## included, not the GPU); `tools/run_tests.sh --windowed` measures the render too.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const PER_SIDE := 5
## Frag, stun, frag, stun, frag, stun: one throw every `THROW_EVERY` frames (0.6 s), the click
## `CLICK_AFTER` frames after the slot is picked and the aim set (the facing settles in a frame or
## two standing; the 0.3 s wind-up is over before the next pick).
const THROWS := [Probe.FRAG, Probe.STUN, Probe.FRAG, Probe.STUN, Probe.FRAG, Probe.STUN]
const THROW_EVERY := 36
const CLICK_AFTER := 15
## How far from the fighter it throws at the thrower stands: inside the throw range, outside the
## kill radius.
const THROW_DISTANCE := 200.0
## The last click is at frame 195 (3.25 s); the last frag leaves the hand at about 2.95 s and goes
## off 3 s later, so the last burst is near 6 s and the window runs to 3 s after it: 560 frames (9.3
## s), checked below against the bursts' real times.
const MEASURE_FRAMES := 560
const AFTER_LAST_S := 3.0
const NODE_GROWTH := 2500


func describe() -> Dictionary:
	return {
		"name": "Grenades in a 5v5 match keep it smooth",
		"description": "In the 5v5 match of perf/match_5v5_stress a puppet throws 3 frags and 3 "
			+ "stuns among the fighters over ~3 s; from the first throw to 3 s after the last "
			+ "burst the average frame stays under 16.7 ms, p95 under 20 and no frame over 33.4.",
		"tags": ["match", "ai", "scripted", "crowd", "grenade", "frag", "stun"],
		"timeout": 60.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)
	# a person's wheel or camera keys would change what is drawn, so what is measured
	s.lock_interaction([&"camera"])
	# Far off the house until its first throw: it plays no part in the warm-up.
	s.actor(
		&"thrower",
		&"puppet",
		Vector2(-3000, -3000),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters: Array = t.world.match_handle.get("combatants", [])
	if not _set_up(t, characters):
		return
	var thrower := t.actor(&"thrower")
	if not await Perf.warm_until_contact(t, "grenades in a 5v5 match", characters):
		return

	var nodes_before := Perf.nodes()
	var start := t.time
	var targets: Array = []
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES, _throws(t, characters, targets))
	var end := t.time

	# The puppet's own bursts: an NPC's grenade is load, not one of the six.
	var booms := Probe.booms(t).filter(
		func(b: Dictionary) -> bool: return b["data"].get("attacker") == thrower,
	)
	if not _window_holds_bursts(t, booms, start, end, targets):
		return
	Perf.within_frames(t, "grenades in a 5v5 match", stats)
	_check_struck(t, booms, nodes_before)


## The premises before the warm-up: the match's ten `characters` spawned, the runner's camera
## framing them on a player's screen, the thrower armed with three frags and three stuns. False
## when one failed (the test ended).
func _set_up(t: TestContext, characters: Array) -> bool:
	if not t.require(
			characters.size() == PER_SIDE * 2,
			"ten combatants spawned (%d)" % characters.size(),
	):
		return false
	Perf.player_screen(t)
	var camera := t.world.get_viewport().get_camera_2d()
	if not t.require(
			camera != null and camera.has_method("frame"),
			"the runner's camera can frame the fight",
	):
		return false
	camera.frame(characters)
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 3, 3)
	return t.require(
			Probe.count(thrower, Probe.FRAG) == 3 and Probe.count(thrower, Probe.STUN) == 3,
			"the thrower carries 3 frags and 3 stuns",
	)


## The per-frame script of the window: each `THROW_EVERY` frames the puppet picks the next of
## `THROWS` (where it throws appended to `targets`) and clicks `CLICK_AFTER` frames later.
func _throws(t: TestContext, characters: Array, targets: Array) -> Callable:
	return func(i: int) -> void:
		var k := int(i / float(THROW_EVERY))
		if k >= THROWS.size():
			return
		var step := i % THROW_EVERY
		if step == 0:
			targets.append(_throw_from(t, characters))
			t.puppet(&"thrower").select_slot(THROWS[k])
		elif step == CLICK_AFTER:
			t.puppet(&"thrower").shoot()


## The premises on the window from `start` to `end` (s): all six of the puppet's `booms` inside it
## (`targets` where it threw), and it running `AFTER_LAST_S` past the last.
func _window_holds_bursts(
	t: TestContext,
	booms: Array,
	start: float,
	end: float,
	targets: Array,
) -> bool:
	var last := -INF
	for b: Dictionary in booms:
		last = maxf(last, float(b["time"]))
	if not t.require(
			booms.size() == THROWS.size(),
			"all six grenades went off inside the window (%d bursts; thrown at %s)"
				% [booms.size(), str(targets)],
	):
		return false
	return t.require(
			end - last >= AFTER_LAST_S - 0.05,
			"the window runs %.1f s past the last burst (%.2f s after the first throw)"
				% [end - last, last - start],
	)


## The puppet's own grenades (`booms`) went off among the fighters: its frags' blast hits and the
## stuns of the frames its stuns went off in (a `stun` event names no thrower); and the node growth
## since `nodes_before` is within budget.
func _check_struck(t: TestContext, booms: Array, nodes_before: int) -> void:
	var thrower := t.actor(&"thrower")
	var hits := Probe.raw(
		t,
		&"hit",
		func(d: Dictionary) -> bool:
			return d.get("outcome") == &"blast" and d.get("attacker") == thrower,
	).size()
	var stun_times: Array = booms.filter(
		func(b: Dictionary) -> bool: return b["data"].get("kind") == &"stun",
	).map(func(b: Dictionary) -> float: return float(b["time"]))
	var stunned := Probe.raw(t, &"stun").filter(
		func(e: Dictionary) -> bool: return stun_times.has(float(e["time"])),
	).size()
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF grenades in a 5v5 match: %d blast hits, %d stuns, node growth %d"
			% [hits, stunned, grown])
	t.check(
		hits + stunned > 0,
		"the puppet's grenades went off among the fighters (%d blast hits, %d stuns)" % [
			hits,
			stunned,
		],
	)
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])


## Stand the thrower `THROW_DISTANCE` from the fighter in the thick of the fight (the living one
## with the most others near it), on the navmesh with a clear line to it, and aim at it. Returns the
## fighter's position.
func _throw_from(t: TestContext, characters: Array) -> Vector2:
	var target: Node2D = null
	var crowd := -1
	for c: Node2D in characters:
		if c.is_dead:
			continue
		var near := 0
		for o: Node2D in characters:
			if (o != c
					and not o.is_dead
					and o.global_position.distance_to(c.global_position) < 300.0):
				near += 1
		if near > crowd:
			crowd = near
			target = c
	if target == null:
		return Vector2.ZERO
	var map := t.world.get_world_2d().navigation_map
	var spot := target.global_position + Vector2.RIGHT * THROW_DISTANCE
	for a in 16:
		var want := target.global_position + Vector2.from_angle(TAU * a / 16.0) * THROW_DISTANCE
		var on := NavBuilder.snap(map, want)
		if on.distance_to(want) < 30.0 and GrenadeAi.line_clear(t, on, target.global_position):
			spot = on
			break
	var thrower := t.actor(&"thrower")
	thrower.global_position = spot
	thrower.velocity = Vector2.ZERO
	t.puppet(&"thrower").aim_at(target.global_position)
	return target.global_position.round()
