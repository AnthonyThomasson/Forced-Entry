extends RefCounted
## AI PERCEPTION sub-domain — the avoid maps `AgentEntry.slot_reach` carves bodies out of. A map
## is made for a set of bodies (a hole at each) and kept with the planning region while it lives; an
## ask for a set whose every body stands within `TOLERANCE` px of a body of a kept one (and has as
## many) is answered by that map, so bodies swaying a pixel or two, or another NPC asking about the
## same stack, never bake a map of their own: the bake is district-sized, ~100 ms of worker thread
## and an engine landing, and a hold asks every frame (`EntryApproach.tick_approach`).
## Static: it holds nothing itself, the kept sets are meta of the planning region.

## The planning region's meta holding the kept sets, newest last: `{ key, points }`.
const META := &"ai_body_maps"
## How far (px) a body may stand off the one a kept map carved and still be that body: the grid
## the sets were keyed on (`AgentEntry.SLOT_STEP`).
const TOLERANCE := 4.0
## The most sets kept per planning region: an older one is let go (its avoid map is freed once
## nobody asks for it, `NavBuilder.avoid_idle_frames`).
const KEPT := 24
## Sides of the polygon a body is carved as, and its radius with the margin (px).
const SEGMENTS := 10


## The avoid map of planning region `region` with a body carved at each of `bodies`, `radius` px
## round (`NavBuilder.avoid_map`): a kept one for the same bodies, else a new one.
static func of(region: NavigationRegion3D, asked: Array, radius: float) -> RID:
	var bodies: Array = []
	for b: Vector2 in asked:
		if not bodies.any(func(c: Vector2) -> bool: return c.distance_to(b) <= TOLERANCE):
			bodies.append(b)
	var kept: Array = region.get_meta(META, [])
	region.set_meta(META, kept)
	var made := _kept_for(kept, bodies)
	if made.is_empty():
		made = { "key": "bodies:%d" % _serial(kept), "points": bodies.duplicate() }
		kept.append(made)
		if kept.size() > KEPT:
			kept.pop_front()
	var holes: Array = []
	for b: Vector2 in made["points"]:
		var hole := PackedVector2Array()
		for i in SEGMENTS:
			hole.append(b + Vector2.from_angle(TAU * i / SEGMENTS) * radius)
		holes.append(hole)
	return NavBuilder.avoid_map(region, made["key"], holes)


## The kept set each of `bodies` stands within `TOLERANCE` of one of (one body each), or {}.
static func _kept_for(kept: Array, bodies: Array) -> Dictionary:
	for i in range(kept.size() - 1, -1, -1):
		var points: Array = kept[i]["points"]
		if points.size() == bodies.size() and _matches(points, bodies):
			return kept[i]
	return {}


## Whether every body of `bodies` is within `TOLERANCE` of a distinct one of `points`.
static func _matches(points: Array, bodies: Array) -> bool:
	var free: Array = points.duplicate()
	for b: Vector2 in bodies:
		var at := -1
		var best := TOLERANCE
		for j in free.size():
			var d := b.distance_to(free[j])
			if d <= best:
				best = d
				at = j
		if at < 0:
			return false
		free.remove_at(at)
	return true


## A number no kept set's key carries yet.
static func _serial(kept: Array) -> int:
	return 1 if kept.is_empty() else int(str(kept[-1]["key"]).get_slice(":", 1)) + 1
