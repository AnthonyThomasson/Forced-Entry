extends RefCounted
## The shell interiors set: one of the closed towers of the district's outer ring, drawn roofless
## like every other ground floor, as a 600 x 400 shell. Its exterior wall is the house wall style
## with no doorway, so it cannot be entered; the bare interior inside differs by variant (`a` bare
## concrete and partition walls, `b` under construction, `c` derelict). The real sidewalk and road
## run past its south wall.

const Kit := preload("res://sandboxes/showroom/downtown_district/stage_kit.gd")
const Decor := preload("res://sandboxes/showroom/downtown_district/shell_decor_painter.gd")
const SHELL := Vector2(600, 400)
const WALK := 64.0
const ROAD := 110.0
## Margin (px) from the exterior wall that loose things keep to.
const EDGE := 36.0
## A wall stain: its size (it starts on the wall and runs out over the floor).
const STAIN := Vector2(72, 46)
const SCATTER_SEED := 182
const FACINGS := [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]
## What variant `c` strews, each `[catalogue key, how many]`.
const LITTER := [["trash", 7], ["puddle", 4], ["cardboard", 4], ["cables", 2]]
## Variant `b`'s decor: `[kind, size, shell-local top-left of each]`.
const SITE := [
	["rebar", Vector2(104, 20), [Vector2(40, 330), Vector2(440, 70), Vector2(300, 220)]],
	["rubble", Vector2(70, 48), [Vector2(120, 100), Vector2(470, 300), Vector2(260, 330)]],
	["scaffold", Vector2(120, 52), [Vector2(40, 40), Vector2(430, 150)]],
	["cement", Vector2(88, 40), [Vector2(250, 40), Vector2(60, 220), Vector2(400, 330)]],
]


## Build the exhibit of set `kind` for `slot` through `kit`.
static func build(kit: Kit, _kind: StringName, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	var shell := Rect2(o, SHELL)
	kit.room(shell, "concrete", [])
	_street(kit, o, float(slot["width"]))
	match slot["variant"]:
		"a":
			_partitions(kit, shell)
		"b":
			_site(kit, o)
		"c":
			_derelict(kit, o)


## The sidewalk and road along the shell's south wall, a little wider than the shell so the three
## shells' streets meet, and a real streetlight at the curb.
static func _street(kit: Kit, o: Vector2, width: float) -> void:
	var left := o.x - 50.0
	var wide := width + 100.0
	var y := o.y + SHELL.y
	kit.street(Rect2(left, y, wide, WALK), "sidewalk", o, [Vector2.DOWN])
	kit.street(Rect2(left, y + WALK, wide, ROAD), "asphalt", o, [Vector2.UP])
	kit.piece("streetlight", Vector2(o.x + width - 40.0, y + WALK - 10.0))


## A few interior walls: one long partition with two doorways, and a short one across the east
## half with one; a doorway has no door, only an archway.
static func _partitions(kit: Kit, shell: Rect2) -> void:
	var o := shell.position
	var west := Rect2(o, Vector2(220, SHELL.y))
	kit.room(west, "", [o + Vector2(220, 110), o + Vector2(220, 300)])
	var north_east := Rect2(o + Vector2(220, 0), Vector2(SHELL.x - 220.0, 210))
	kit.room(north_east, "", [o + Vector2(220, 110), o + Vector2(420, 210)])


## Rebar bundles, rubble, scaffolds and cement bags lying about the floor.
static func _site(kit: Kit, o: Vector2) -> void:
	for group: Array in SITE:
		for at: Vector2 in group[2]:
			kit.sprite(
				Decor, group[1], o + at, { "kind": group[0] }, { "z": DrawLayers.RUG },
			)


## Litter on the floor (real catalogue decor) and damp stains running down the wall.
static func _derelict(kit: Kit, o: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED
	var field := Rect2(o, SHELL).grow(-EDGE)
	for row: Array in LITTER:
		for _i in int(row[1]):
			var at := Vector2(
				rng.randf_range(field.position.x, field.end.x),
				rng.randf_range(field.position.y, field.end.y),
			)
			var turned := { "rotated": rng.randf() < 0.5, "facing": FACINGS[rng.randi() % 4] }
			kit.piece(row[0], at, turned)
	for x in [60.0, 210.0, 330.0, 470.0]:
		kit.sprite(
			Decor, STAIN, Vector2(o.x + x, o.y - 6.0), { "kind": "stain" }, {},
		)
	for x in [120.0, 400.0]:
		kit.sprite(
			Decor, STAIN, Vector2(o.x + x, o.y + SHELL.y + 6.0 - STAIN.y),
			{ "kind": "stain" }, { "facing": Vector2.UP },
		)
