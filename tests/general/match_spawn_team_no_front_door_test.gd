extends GameTest
## LD27 (`docs/leadership.md`), ticket #95: in a house with no front door the invader team starts
## packed in one group round a point of the ring round the house (`invader_margin`, 80 px, out of
## the rooms' bounds), as any team does, each member on a spot of its own and outside the house. A
## one-room layout with no doorway at all.

## The room, 200 px square, with no doorway.
const ROOM := Rect2(0, 0, 200, 200)
const INVADERS := 4
## The match's `invader_margin`: how far (px) out of the rooms' bounds the ring lies.
const MARGIN := 80.0
## Twice the match's `spawn_clearance` (20 px): how far apart two members of a group start, and
## how far apart the rings a group packs in lie; the group's centre stands within one of them of
## the ring round the house.
const APART := 40.0
## The most (px) a member may stand from the group's centre: four bodies packed at the clearance.
const GROUP_RADIUS := 110.0


func describe() -> Dictionary:
	return {
		"name": "A team in a house with no front door starts on the ring round it",
		"description": "In a house with no front door, the invader team starts in one group round "
			+ "a point of the ring round the house, its members apart and outside the house.",
		"tags": ["setup", "match", "spawn", "squad"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "room", "type": "living_room", "rect": ROOM }], [])
	s.von_down()
	s.declared_match({ "seed": 3, "defenders": { "count": 0 }, "invaders": { "count": INVADERS } })


func run(t: TestContext) -> void:
	var team: Array = t.world.match_handle.get("combatants", [])
	if not t.require(team.size() == INVADERS, "premise: four invaders placed (%d)" % team.size()):
		return
	if not t.require(
			not (t.world.match_handle["openings"] as Array).any(
				func(o): return o.get("front", false),
			),
			"premise: the house has no front door",
	):
		return
	var points: Array = team.map(func(c): return (c as Node2D).global_position)
	var centre := Vector2.ZERO
	for p: Vector2 in points:
		centre += p
	centre /= points.size()
	var ring := ROOM.grow(MARGIN)
	var off_ring := _off_ring(ring, centre)
	t.check(
		off_ring <= APART,
		"the group's centre %s stands within %.0f px of the ring %s round the house (%.0f px)"
			% [str(centre.round()), APART, str(ring), off_ring],
	)
	for i in points.size():
		var p: Vector2 = points[i]
		t.check(
			not ROOM.has_point(p),
			"%s starts outside the house (%s)" % [team[i].name, str(p.round())],
		)
		t.check(
			p.distance_to(centre) <= GROUP_RADIUS,
			"%s stands within %.0f px of the group's centre (%.0f px; at %s)"
				% [team[i].name, GROUP_RADIUS, p.distance_to(centre), points],
		)
		for j in range(i + 1, points.size()):
			t.check(
				p.distance_to(points[j]) >= APART - 0.01,
				"%s and %s start %.0f px apart or more (%.0f px)"
					% [team[i].name, team[j].name, APART, p.distance_to(points[j])],
			)


## How far `p` lies from the outline of `rect`.
func _off_ring(rect: Rect2, p: Vector2) -> float:
	if not rect.has_point(p):
		return p.distance_to(p.clamp(rect.position, rect.end))
	return minf(
		minf(p.x - rect.position.x, rect.end.x - p.x),
		minf(p.y - rect.position.y, rect.end.y - p.y),
	)
