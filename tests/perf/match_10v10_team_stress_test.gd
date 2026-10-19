extends GameTest
## Performance guard for the largest match with its teams coordinated (`docs/leadership.md` LD19
## to LD23): the 10v10 of `perf/match_10v10_stress` (the same house, plan, seed, placement,
## loadouts, switches and scripted Von) with one squad per side built and bound the way Main builds
## it (`Squad.setup` over the side's combatants in spawn order with the spawner's openings, the
## house's rooms and the claim ttl `MatchSpawner.callout_ttl_of`, each NPC handed it by
## `MatchSpawner.bind_squad`), the invaders ranked as Main ranks its police unit (the first the
## lead, rank 2, the second the sergeant, 1, the rest 0). So the members follow their leaders: what
## a squad costs (the leader's trail, the follow spots, the follow primitive, the leash) is in the
## frame, where the squad-less guards cannot see it. The sides are in contact before the window
## opens: the warm-up runs on until a shot has been fired (at most `CONTACT_WITHIN` s more), so the
## frames measured cost the teams' fight (the leash filter, combat within the leash, the leash
## break) and not only a walking crowd. Measured to the same standard: the average frame fits in
## one 60 fps frame, no spike over two. The follow cost is the frame stats this guard logs (`PERF
## 10v10 team match` avg / p95 / max, `Perf.within_frames`), read against those of
## `perf/match_10v10_stress` on the same house and seed, which builds no squad; it also logs how
## many members were following at the end. Headless measures CPU only.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Perf := preload("res://tests/_perf/perf_probe.gd")
const MatchSpawner := preload("res://scenes/match_spawner.gd")
const SEED := 7
## The largest plan by floor area, pinned as `perf/match_10v10_stress` pins it.
const PLAN := "garage_home"
const PER_SIDE := 10
const WARMUP_S := 6.0
## The most (s) the warm-up runs on past `WARMUP_S` for the sides to make contact (a shot fired).
const CONTACT_WITHIN := 20.0
const MEASURE_FRAMES := 300
const NODE_GROWTH := 5000


func describe() -> Dictionary:
	return {
		"name": "A 10v10 match of two coordinated teams runs without frame loss",
		"description": "Ten defenders and ten invaders, each side a squad bound as Main binds it "
			+ "(members following their leader), fight in a generated house; the average frame "
			+ "stays under 16.7 ms and no frame takes over two.",
		"tags": ["match", "ai", "scripted", "crowd", "squad", "follow"],
		"timeout": 60.0,
		# As in perf/match_10v10_stress: the re-bake of overlapping footprints is now and then
		# rejected by the engine; the bake's cost is part of what is measured.
		"allowed_logs": [
			"Navigation map synchronization error",
			"NavigationPolygon polygon convex partition failed",
		],
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.vision", true)
	s.switch(&"ai.pursuit", true)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters := _spawn_match(t)
	if not t.require(
			characters.size() == PER_SIDE * 2,
			"twenty combatants spawned (%d)" % characters.size(),
	):
		return
	var squads := _build_squads(t, characters)
	if not t.require(squads.size() == 2, "one squad per side is built (Squad.setup)"):
		return
	for faction: StringName in squads:
		var squad: Node = squads[faction]
		var side: Array = characters.filter(func(c): return c.get("faction") == faction)
		t.require(
			side.all(func(c): return Follow.brain_of(c).get("squad") == squad),
			"every %s NPC's controller has its side's squad (bind_squad)" % faction,
		)
		var lead: Node = side.reduce(func(a, c): return c if int(c.rank) > int(a.rank) else a)
		t.require(
			squad.leader() == lead,
			"the %s leader is the rank rule's (%s, rank %d; got %s)"
				% [faction, lead.name, int(lead.rank), Follow.name_of(squad.leader())],
		)
		if not t.require(
				side.all(func(c): return c == lead or squad.follows(c)),
				"premise: every %s member but the leader follows it (Squad.follows)" % faction,
		):
			return
	await t.seconds(WARMUP_S)
	var shot := func() -> bool: return t.happened(&"shot")
	if not t.require(
			await t.until(shot, CONTACT_WITHIN),
			"premise: the sides are in contact, a shot fired, within %.0f s of the warm-up (%.1f s)"
				% [CONTACT_WITHIN, t.time],
	):
		return
	GameLog.say("PERF 10v10 team match contact at %.1f s" % t.time)
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	var following := characters.filter(func(c): return Follow.following(c)).size()
	Perf.within_frames(
		t,
		"10v10 team match",
		stats,
		Perf.SMOOTH_AVG_MS,
		Perf.SMOOTH_P95_MS,
		Perf.SMOOTH_MAX_MS,
	)
	t.check(
		not t.von_requests().is_empty(),
		"the NPCs asked for decisions (%d asks)" % t.von_requests().size(),
	)
	var grown := Perf.nodes() - nodes_before
	GameLog.say(
		"PERF 10v10 team match node growth %d, %d decisions asked, %d following at the end"
			% [grown, t.von_requests().size(), following],
	)
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])


## Place the match as `perf/match_10v10_stress` places it (the defenders as Main places them, the
## invaders spread round the house by `spawn_invader`, so the two guards' frames compare), and rank
## the invaders as Main ranks its police unit.
func _spawn_match(t: TestContext) -> Array:
	var spawner = MatchSpawner.new()
	spawner.world = t.world
	spawner.openings = t.world.openings
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var entrance := Perf.front_entrance(t)
	for i in PER_SIDE:
		spawner.spawn_defender(t.rooms, rng, i)
	for i in PER_SIDE:
		spawner.spawn_invader(t.rooms, rng, i, PER_SIDE, entrance)
	var loadout_rng := RandomNumberGenerator.new()
	loadout_rng.seed = SEED
	var rank := 2
	for c in spawner.combatants:
		LoadoutConfig.apply(c, {}, loadout_rng)
		Perf.overlays_off(c)
		if c.get("faction") == &"invader":
			c.rank = rank
			rank = maxi(rank - 1, 0)
	return spawner.combatants


## One squad per side over its combatants in spawn order, bound to each NPC, as Main's
## `_build_squads` does: faction -> squad ({} when the squad script is missing).
func _build_squads(t: TestContext, characters: Array) -> Dictionary:
	var out := {}
	for faction: StringName in [&"household", &"invader"]:
		var side: Array = characters.filter(func(c): return c.get("faction") == faction)
		var squad := Follow.team_of(t, side)
		if squad != null:
			out[faction] = squad
	return out
