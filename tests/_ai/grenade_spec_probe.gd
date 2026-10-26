extends RefCounted
## Shared helpers for the grenade tests (not a test itself):
## `const GrenadeSpec := preload("res://tests/_ai/grenade_spec_probe.gd")`. The numbers of the spec
## (`docs/grenades.md` G7, G11, G12), so a test checks the doc and not the code: what a blast or a
## stun does at a distance, and the `sound` categories the grenades add. The spec's constants are
## `grenade_probe.gd`'s, read there.

const Probe := preload("res://tests/_ai/grenade_probe.gd")


## G7: blast damage at distance `d` from the blast point: full to `KILL_RADIUS`, linear to 0 at
## `BLAST_RADIUS`.
static func blast_damage(d: float) -> float:
	return Probe.BLAST_DAMAGE * clampf(
		(Probe.BLAST_RADIUS - d) / (Probe.BLAST_RADIUS - Probe.KILL_RADIUS),
		0.0,
		1.0,
	)


## G11: the flash's reach at distance `d` (1 inside `FLASH_FULL`, linear to 0 at `FLASH_RADIUS`).
static func flash_scale(d: float) -> float:
	return clampf((Probe.FLASH_RADIUS - d) / (Probe.FLASH_RADIUS - Probe.FLASH_FULL), 0.0, 1.0)


## G11: the facing factor from the dot of the victim's facing with the direction to the burst: 1
## facing it, 0.6 side-on, 0.25 back to it, linear between those anchors.
static func _facing_factor(dot: float) -> float:
	return lerpf(0.6, 1.0, dot) if dot >= 0.0 else lerpf(0.6, 0.25, -dot)


## G11: the blind time of a victim at `at` facing `facing`, in line of sight of a burst at `burst`.
static func expected_blind(at: Vector2, facing: Vector2, burst: Vector2) -> float:
	var to_burst := burst - at
	var dot := facing.normalized().dot(to_burst.normalized()) if to_burst.length() > 0.5 else 1.0
	return Probe.MAX_BLIND * flash_scale(to_burst.length()) * _facing_factor(dot)


## G12: the deaf time of a victim `d` from the burst (linear from `MAX_DEAF` at 0 to nothing at
## `BANG_RADIUS`), times `factor` (`WALL_FACTOR` through a wall).
static func expected_deaf(d: float, factor := 1.0) -> float:
	return Probe.MAX_DEAF * clampf(1.0 - d / Probe.BANG_RADIUS, 0.0, 1.0) * factor


## The `sound` categories the grenades add, merged into the audio tests' "nothing is out of earshot"
## range table.
static func everywhere(base: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for kind in [&"throw", &"grenade", &"explosion", &"tinnitus"]:
		out[kind] = 1.0e9
	return out
