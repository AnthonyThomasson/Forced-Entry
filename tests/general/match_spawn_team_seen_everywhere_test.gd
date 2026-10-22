extends GameTest
## LD27 (`docs/leadership.md`), ticket #95: when no point round the house is out of the views of its
## exterior doorways, the invader team still starts packed in one group round the point drawn for
## it, as any team does, each member on a spot of its own. A one-room house with an exterior doorway
## in each wall: every point of the ring the team's point is drawn on lies within 200 px of one.

## The room, 100 px square, and its four doorways, one mid-wall each (a doorway on one room's wall
## is an exterior one).
const ROOM := Rect2(0, 0, 100, 100)
const DOORS := [
	{ "pos": Vector2(50, 0), "width": 40.0 },
	{ "pos": Vector2(100, 50), "width": 40.0 },
	{ "pos": Vector2(50, 100), "width": 40.0 },
	{ "pos": Vector2(0, 50), "width": 40.0 },
]
const INVADERS := 4
## Twice the match's `spawn_clearance` (20 px): how far apart two members of a group start.
const APART := 40.0
## The most (px) a member may stand from the group's centre: four bodies packed at the clearance.
const GROUP_RADIUS := 110.0


func describe() -> Dictionary:
	return {
		"name": "A team seen from every side still starts packed",
		"description": "In a house whose every surrounding point is within an exterior doorway's "
			+ "reach, the invader team starts in one group, its members apart.",
		"tags": ["setup", "match", "spawn", "squad"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "room", "type": "living_room", "rect": ROOM }], DOORS)
	s.von_down()
	s.match({ "seed": 3, "defenders": { "count": 0 }, "invaders": { "count": INVADERS } })


func run(t: TestContext) -> void:
	var team: Array = t.match().get("combatants", [])
	if not t.require(team.size() == INVADERS, "premise: four invaders placed (%d)" % team.size()):
		return
	var points: Array = team.map(func(c): return (c as Node2D).global_position)
	var centre := Vector2.ZERO
	for p: Vector2 in points:
		centre += p
	centre /= points.size()
	for i in points.size():
		t.check(
			(points[i] as Vector2).distance_to(centre) <= GROUP_RADIUS,
			"%s stands within %.0f px of the group's centre (%.0f px; at %s)"
				% [team[i].name, GROUP_RADIUS, (points[i] as Vector2).distance_to(centre), points],
		)
		for j in range(i + 1, points.size()):
			t.check(
				(points[i] as Vector2).distance_to(points[j]) >= APART - 0.01,
				"%s and %s start %.0f px apart or more (%.0f px)"
					% [
						team[i].name,
						team[j].name,
						APART,
						(points[i] as Vector2).distance_to(points[j]),
					],
			)
