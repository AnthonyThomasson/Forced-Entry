extends GameTest
## `BodyHeights`, the one holder of a body's real proportions (#194,
## `docs/research/3d-cover-heights.md`): 1 3D unit = 1 px and a 1.75 m person = 74 px, so a metre is
## about 42.3 px; the eye, the muzzle (bore) line and the head top of each posture (stand, duck,
## fire-over), and the hit zones' bands (feet, legs, torso, head) from the floor. The expected
## numbers are worked by hand from the research note's metres (stand eye 1.64, bore 1.55, crouch
## head 0.85), not read back.

const PX_PER_M := 74.0 / 1.75
## A low piece of cover, 0.9 m: a sofa back, a counter, a low wall.
const LOW_COVER_M := 0.9
## The head from the neck base to the crown (1.52 to 1.75 m: the research note, section 1).
const HEAD_M := 0.23


func describe() -> Dictionary:
	return {
		"name": "Body heights: px per metre, posture eye / muzzle / head, hit-zone bands",
		"description": "BodyHeights scales metres to px (a 1.75 m person is 74 px) and gives each "
			+ "posture (stand, duck, fire-over) its eye, muzzle and head-top height and its zone "
			+ "bands; a duck hides behind 0.9 m cover and a fire-over muzzle clears it.",
		"tags": ["heights", "posture", "3d", "cover"],
		"timeout": 4.0,
	}


func run(t: TestContext) -> void:
	_scale(t)
	_ordering(t)
	_zones(t)
	_stand_matches_the_mirror_body(t)
	_rise_to_fire(t)


## 1.75 m is 74 px: the one scale, and px and metres convert back and forth.
func _scale(t: TestContext) -> void:
	t.expect_near(BodyHeights.px_per_metre(), PX_PER_M, 0.001, "a metre is 42.3 px")
	t.expect_near(BodyHeights.px(1.75), 74.0, 0.001, "a 1.75 m person is 74 px")
	t.expect_near(BodyHeights.metres(BodyHeights.px(0.85)), 0.85, 0.0001, "metres round-trip")
	t.expect_near(BodyHeights.head_top(BodyHeights.STAND), 74.0, 0.001, "standing head top = 74")
	t.expect_near(
		BodyHeights.eye(BodyHeights.STAND), 1.64 * PX_PER_M, 0.01, "standing eye is 1.64 m"
	)
	t.expect_near(
		BodyHeights.muzzle(BodyHeights.STAND), 1.55 * PX_PER_M, 0.01, "standing bore is 1.55 m"
	)
	t.expect_near(
		BodyHeights.head_top(BodyHeights.DUCK), 0.85 * PX_PER_M, 0.01, "a duck's head top is 0.85 m"
	)


## Each posture's own order (muzzle under eye under head) and the postures' order: a duck's head is
## under 0.9 m cover (so the cover hides it), a fire-over muzzle is over it, and a standing body
## is over both.
func _ordering(t: TestContext) -> void:
	var cover := LOW_COVER_M * PX_PER_M
	for posture: StringName in BodyHeights.postures_ids():
		t.check(
			BodyHeights.muzzle(posture) < BodyHeights.eye(posture)
			and BodyHeights.eye(posture) < BodyHeights.head_top(posture),
			"%s: muzzle < eye < head top" % posture,
		)
	t.check(
		BodyHeights.head_top(BodyHeights.DUCK) < cover,
		"a ducked head top is under a 0.9 m piece: %.1f < %.1f"
		% [BodyHeights.head_top(BodyHeights.DUCK), cover],
	)
	t.check(
		BodyHeights.muzzle(BodyHeights.DUCK) < cover,
		"a ducked muzzle line is blocked by 0.9 m cover",
	)
	t.check(
		BodyHeights.muzzle(BodyHeights.FIRE_OVER) > cover,
		"a risen muzzle clears 0.9 m cover",
	)
	t.check(
		BodyHeights.eye(BodyHeights.FIRE_OVER) > cover
		and BodyHeights.shoulder(BodyHeights.FIRE_OVER) > cover,
		"a risen body's eye and shoulders are over 0.9 m cover",
	)
	t.check(
		BodyHeights.head_top(BodyHeights.FIRE_OVER) - cover >= BodyHeights.px(HEAD_M),
		"a head's height of the risen body (and more) shows over 0.9 m cover",
	)
	t.check(
		BodyHeights.head_top(BodyHeights.FIRE_OVER) < BodyHeights.head_top(BodyHeights.STAND)
		and BodyHeights.head_top(BodyHeights.DUCK) < BodyHeights.head_top(BodyHeights.FIRE_OVER),
		"duck < fire-over < stand by head top",
	)
	t.check(
		BodyHeights.muzzle(BodyHeights.FIRE_OVER) < BodyHeights.muzzle(BodyHeights.STAND),
		"a risen muzzle is under a standing one",
	)


## The bands run feet, legs, torso, head from the floor to the head top without a gap, and a height
## reads the zone it falls in.
func _zones(t: TestContext) -> void:
	for posture: StringName in BodyHeights.postures_ids():
		var bands := BodyHeights.zones(posture)
		t.expect_eq(bands.size(), 4, "%s has four bands" % posture)
		var names: Array = []
		var from := 0.0
		var contiguous := true
		for band: Array in bands:
			names.append(band[0])
			contiguous = contiguous and is_equal_approx(band[1], from) and band[2] > band[1]
			from = band[2]
		t.expect_eq(names, [&"feet", &"legs", &"torso", &"head"], "%s: bands feet up" % posture)
		t.check(contiguous, "%s: the bands touch, floor to head" % posture)
		t.expect_near(
			from,
			BodyHeights.head_top(posture),
			0.001,
			"%s: the last ends at the head" % posture,
		)
	t.expect_eq(
		BodyHeights.zone_at(BodyHeights.STAND, 2.0),
		&"feet",
		"2 px up a standing body: feet",
	)
	t.expect_eq(BodyHeights.zone_at(BodyHeights.STAND, 0.5 * PX_PER_M), &"legs", "0.5 m: legs")
	t.expect_eq(BodyHeights.zone_at(BodyHeights.STAND, 1.3 * PX_PER_M), &"torso", "1.3 m: torso")
	t.expect_eq(BodyHeights.zone_at(BodyHeights.STAND, 1.65 * PX_PER_M), &"head", "1.65 m: head")
	t.expect_eq(BodyHeights.zone_at(BodyHeights.STAND, 200.0), &"head", "over the head: head")
	t.expect_eq(BodyHeights.zone_at(BodyHeights.STAND, -3.0), &"feet", "under the floor: feet")
	t.expect_eq(
		BodyHeights.zone_at(BodyHeights.DUCK, 0.8 * PX_PER_M), &"head", "0.8 m up a duck: its head"
	)
	t.expect_eq(
		BodyHeights.zone_at(BodyHeights.STAND, 0.8 * PX_PER_M), &"legs", "0.8 m up a stander: legs"
	)


## The mirror's body is as tall as a standing person (one number, not two).
func _stand_matches_the_mirror_body(t: TestContext) -> void:
	t.expect_near(
		MirrorConfig.character_height,
		BodyHeights.head_top(BodyHeights.STAND),
		0.001,
		"the 3D mirror's character is a standing person's height",
	)


## The rise to fire picks the lowest pose whose muzzle clears the cover: the duck itself for cover
## under its muzzle, fire-over up to a risen muzzle (about 1.0 m), standing up to a standing muzzle
## (about 1.55 m), and none above (fire around, not over).
func _rise_to_fire(t: TestContext) -> void:
	var none := BodyHeights.NONE
	t.expect_eq(
		BodyHeights.lowest_clearing(BodyHeights.px(0.5)),
		BodyHeights.DUCK,
		"0.5 m: a duck fires over it",
	)
	t.expect_eq(
		BodyHeights.lowest_clearing(BodyHeights.px(0.9)),
		BodyHeights.FIRE_OVER,
		"0.9 m: fire-over",
	)
	t.expect_eq(
		BodyHeights.lowest_clearing(BodyHeights.px(0.98)),
		BodyHeights.FIRE_OVER,
		"0.98 m: still fire-over",
	)
	t.expect_eq(
		BodyHeights.lowest_clearing(BodyHeights.px(1.1)),
		BodyHeights.STAND,
		"1.1 m: only a stander clears it",
	)
	t.expect_eq(
		BodyHeights.lowest_clearing(BodyHeights.px(1.5)),
		BodyHeights.STAND,
		"1.5 m: a standing muzzle",
	)
	t.expect_eq(
		BodyHeights.lowest_clearing(BodyHeights.px(1.6)),
		none,
		"1.6 m: no pose fires over it",
	)
	t.expect_eq(BodyHeights.lowest_clearing(BodyHeights.px(2.27)), none, "a wall: none")
	var edge := BodyHeights.muzzle(BodyHeights.FIRE_OVER)
	t.expect_eq(
		BodyHeights.lowest_clearing(edge),
		BodyHeights.STAND,
		"a muzzle level with the top does not clear it",
	)
	t.expect_eq(
		BodyHeights.lowest_clearing(edge - 0.01),
		BodyHeights.FIRE_OVER,
		"a hair under it does",
	)
