extends RefCounted
## Shared helpers for the grenade tests (not a test itself): `const Probe :=
## preload("res://tests/_ai/grenade_probe.gd")`. The behaviour they assert is `docs/grenades.md` (G1
## to G19). This one arms and reads a character, throws, and reads the bus; what a blast or a stun
## does at a distance is `grenade_spec_probe.gd` (`GrenadeSpec`), and the AI's reads and a scene
## round a grenade are `grenade_ai_probe.gd` (`GrenadeAi`).
##
## Every grenade API is reached duck-typed (`has_method`, `call`, groups, EventBus topics), so a
## test loads and runs before the feature exists and goes red on an assertion that names what is
## missing, never on a parse error. What they read: `Character.inventory.item_count(slot)`, the
## `live_grenades` group, and the EventBus topics `throw`, `grenade`, `explosion`, `stun` and `hit`
## (outcome `blast`).

const STUN := 7
const FRAG := 8
const PISTOL := 3
## The throw range cap (G2, `max_range`), the blast radius (G7) and the stun's flash / bang radii
## (G11, G12).
const MAX_RANGE := 550.0
const BLAST_RADIUS := 250.0
const KILL_RADIUS := 120.0
const BLAST_DAMAGE := 60.0
const FLASH_RADIUS := 400.0
const FLASH_FULL := 100.0
const MAX_BLIND := 5.0
const BANG_RADIUS := 350.0
const MAX_DEAF := 6.0
const WALL_FACTOR := 0.4
## G16: how far past the blast radius a frag's danger zone reaches (`evade_margin`) and how far off
## a landing is heard (`hear_grenade`).
const EVADE_MARGIN := 120.0
const FRAG_ZONE := BLAST_RADIUS + EVADE_MARGIN
const HEAR_GRENADE := 300.0
const FUSE_FRAG := 3.0
const FUSE_STUN := 1.5
const WINDUP := 0.3


# --- Arming and reading a character ---------------------------------------------------------------


## Arm `c` the way a match does (`LoadoutConfig.apply`): the gun `weapon`, `stuns` stun grenades
## (slot 7) and `frags` frag grenades (slot 8). Call it at the start of `run`: tests keep the
## default inventory (no grenades) until they arm.
static func arm(c: Node, stun_count := 0, frag_count := 0, weapon := &"pistol") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	LoadoutConfig.apply(c, { "weapon": weapon, "stuns": stun_count, "frags": frag_count }, rng)


## How many grenades `c` carries in `slot`; -1 when the Character has no `inventory` yet.
static func count(c: Node, slot: int) -> int:
	return c.inventory.item_count(slot) if "inventory" in c else -1


## `c.stun.is_blind()` / `is_deaf()` / `level()`; false / 0.0 while the Character lacks a stun.
static func blind(c: Node) -> bool:
	return bool(c.stun.is_blind()) if "stun" in c else false


static func deaf(c: Node) -> bool:
	return bool(c.stun.is_deaf()) if "stun" in c else false


static func level(c: Node) -> float:
	return float(c.stun.level()) if "stun" in c else 0.0


## `c.stun.view()` (seconds left blind / deaf, the burst's blind time, the level 0..1); {} while it
## does not exist.
static func view(c: Node) -> Dictionary:
	return c.stun.view() if "stun" in c else {}


## Stun `c` as a grenade's burst would (`Character.take_stun(blind, deaf)`); false while it does not
## exist.
static func stun(c: Node, blind_s: float, deaf_s: float) -> bool:
	if not c.has_method("take_stun"):
		return false
	c.call("take_stun", blind_s, deaf_s)
	return true


# --- Throwing -----------------------------------------------------------------------------------


## Select `slot` on puppet `who`, face `point` and give the facing time to settle. Does not throw.
static func ready(t: TestContext, who: StringName, slot: int, point: Vector2) -> void:
	var p := t.puppet(who)
	p.select_slot(slot)
	p.aim_at(point)
	await t.seconds(0.4)


## `ready` and then one click of the trigger: the throw starts (the grenade leaves 0.3 s later).
## Returns the sim time of the click.
static func throw_at(t: TestContext, who: StringName, slot: int, point: Vector2) -> float:
	await ready(t, who, slot, point)
	var at := t.time
	t.puppet(who).shoot()
	return at


## The nodes in the `live_grenades` group (each has `kind`, `fuse_left()`, `throw_stats()`,
## `thrower`).
static func live(t: TestContext) -> Array:
	return t.world.get_tree().get_nodes_in_group("live_grenades")


## The raw bus events (`{ topic, data, time }`, `time` in sim seconds) of `topic` passing `filter`
## on their data, oldest first. (`TestContext.events_of` gives the data dicts alone, without the
## time.)
static func raw(t: TestContext, topic: StringName, filter := Callable()) -> Array:
	var out: Array = []
	for e: Dictionary in t.events:
		if e["topic"] == topic and (not filter.is_valid() or filter.call(e["data"])):
			out.append(e)
	return out


## The `explosion` events (of `kind` when given), oldest first, as raw events: `data` is
## `{ position, kind, attacker, radius }`.
static func booms(t: TestContext, kind: StringName = &"") -> Array:
	return raw(
		t,
		&"explosion",
		func(d: Dictionary) -> bool: return kind == &"" or d.get("kind") == kind,
	)


## Wait until `n` explosions (of `kind`) have happened; true on success. `timeout` is sim seconds.
static func wait_boom(t: TestContext, kind: StringName, timeout: float, n := 1) -> bool:
	return await t.until(func() -> bool: return booms(t, kind).size() >= n, timeout)


## Wait until the first grenade has come to rest (`grenade` event, stage `rest`); true on success.
static func wait_rest(t: TestContext, timeout: float) -> bool:
	return await t.until(
		func() -> bool: return t.happened(
			&"grenade",
			func(d: Dictionary) -> bool: return d.get("stage") == &"rest",
		),
		timeout,
	)


## Where the first grenade came to rest.
static func rest_point(t: TestContext) -> Vector2:
	var rests := raw(t, &"grenade", func(d: Dictionary) -> bool: return d.get("stage") == &"rest")
	return rests[0]["data"]["position"] if not rests.is_empty() else Vector2.ZERO


## The `hit` events with outcome `blast` that struck `victim` (G7).
static func blast_hits(t: TestContext, victim: Node) -> Array:
	return raw(
		t,
		&"hit",
		func(d: Dictionary) -> bool: return (
			d.get("victim") == victim and d.get("outcome") == &"blast"
		),
	)


## The `stun` events for `c`: `{ character, position, blind, deaf }`.
static func stuns(t: TestContext, c: Node) -> Array:
	return raw(t, &"stun", func(d: Dictionary) -> bool: return d.get("character") == c)
