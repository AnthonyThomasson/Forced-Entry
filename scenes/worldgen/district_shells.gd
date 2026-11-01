class_name DistrictShells
## World Generation domain: the ring of shells round a district: roofless, closed buildings past the
## outer street. Each is a solid outer wall in the house wall style with no doorway, so it cannot be
## entered, a concrete floor and a few partition walls whose doorways all lie inside. A shell draws
## a style by the seed: bare; under construction (rebar, rubble, scaffold, cement bags) or derelict
## (trash, puddles, cardboard and damp stains down its walls). They are not rooms for the AI
## and carry no room fixtures; they stand outside the area the nav map covers.

const STYLES := ["bare", "site", "derelict"]
## What each style strews,
## `[catalogue key, how many in a shell of `WorldGenShellConfig.shell_area`]`.
const SITE := [["rebar", 3], ["rubble", 3], ["scaffold", 2], ["cement_bags", 3]]
const LITTER := [["trash", 7], ["puddle", 4], ["cardboard", 4]]
## The damp stains on a derelict shell's long walls: how many on the north wall and on the south.
const STAINS := [["north", 4], ["south", 2]]
const FACINGS := [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]


## Build a shell on each rect of `rects` (layout frame) shifted by `delta`, under `root`:
## `[{ rect, node, holder, style, partitions, decor }]`, `rect` in world space, `node` the outer
## wall, `holder` the node holding all of it, `style` one of `STYLES`, `partitions` the partition
## walls and `decor` `[{ key, node }]`. Each shell draws from an RNG of its own, `hash([seed,
## "shell", index])`.
static func build(rects: Array, delta: Vector2, root: Node2D, district_seed: int) -> Array:
	var out: Array = []
	for i in rects.size():
		var rect := Rect2((rects[i] as Rect2).position + delta, (rects[i] as Rect2).size)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([district_seed, "shell", i])
		var shell := Node2D.new()
		shell.name = "Shell %d" % i
		root.add_child(shell)
		var style: String = STYLES[rng.randi() % STYLES.size()]
		var node := _walls(rect, [], "Walls", shell)
		FloorFactory.spawn(rect, GeneralCatalog.FLOORS["concrete"], "Floor", shell)
		out.append({
			"rect": rect,
			"node": node,
			"holder": shell,
			"style": style,
			"partitions": _partitions(rect, rng, shell),
			"decor": _decorate(style, rect, rng, shell),
		})
	return out


## A wall round `rect` in the house wall style with the doorways `openings` cut in, under `holder`.
static func _walls(rect: Rect2, openings: Array, wall_name: String, holder: Node2D) -> Node:
	var walls := RoomWalls.new()
	walls.thickness = WorldGenDistrictConfig.shell_wall
	walls.openings = openings
	walls.style = GeneralCatalog.WALL
	return WallFactory.spawn(rect, walls, wall_name, holder)


## The partition walls of the shell on `rect`: a west room the full height and an east room across
## the top of the rest, split where `rng` says. Their other sides lie on the shell's outline, so
## they have no doorway there; the doorways are all on the lines between them: two from the west
## room (one to the east room, one to the open part below it) and one from the east room down.
static func _partitions(rect: Rect2, rng: RandomNumberGenerator, holder: Node2D) -> Array:
	var split := lerpf(
		WorldGenShellConfig.shell_split_min,
		WorldGenShellConfig.shell_split_max,
		rng.randf(),
	)
	var across := rect.position.x + rect.size.x * split
	var down := rect.position.y + rect.size.y * lerpf(
		WorldGenShellConfig.shell_split_min,
		WorldGenShellConfig.shell_split_max,
		rng.randf(),
	)
	var west := Rect2(rect.position, Vector2(across - rect.position.x, rect.size.y))
	var east := Rect2(
		Vector2(across, rect.position.y),
		Vector2(rect.end.x - across, down - rect.position.y),
	)
	var width := WorldGenShellConfig.shell_doorway
	var upper := { "pos": Vector2(across, (rect.position.y + down) * 0.5), "width": width }
	var lower := { "pos": Vector2(across, (down + rect.end.y) * 0.5), "width": width }
	var inner := { "pos": Vector2((across + rect.end.x) * 0.5, down), "width": width }
	return [
		_walls(west, WallFactory.openings_for(west, [upper, lower]), "Partition West", holder),
		_walls(east, WallFactory.openings_for(east, [upper, inner]), "Partition East", holder),
	]


## The decor of a shell in `style` on `rect`: `[{ key, node }]`, none for a bare one.
static func _decorate(
	style: String,
	rect: Rect2,
	rng: RandomNumberGenerator,
	holder: Node2D,
) -> Array:
	var decor: Array = []
	var inset := WorldGenDistrictConfig.shell_wall * 0.5 + WorldGenShellConfig.shell_edge
	var field := rect.grow(-inset)
	var scale := rect.get_area() / WorldGenShellConfig.shell_area
	if style == "site":
		for row: Array in SITE:
			decor.append_array(_scatter(holder, rng, field, row[0], _count(row[1], scale)))
	elif style == "derelict":
		for row: Array in LITTER:
			decor.append_array(_scatter(holder, rng, field, row[0], _count(row[1], scale)))
		decor.append_array(_stains(rect, rng, holder, scale))
	return decor


## `base` pieces for a shell of `scale` times the reference area, at least one.
static func _count(base: int, scale: float) -> int:
	return maxi(1, roundi(base * scale))


## `count` pieces of catalogue `key` strewn over `field` under `holder`, each turned a way `rng`
## picks and kept inside it: `[{ key, node }]`.
static func _scatter(
	holder: Node2D,
	rng: RandomNumberGenerator,
	field: Rect2,
	key: String,
	count: int,
) -> Array:
	var definition := ObjectDefinitions.get_definition(key)
	var out: Array = []
	for _i in count:
		var turned := { "rotated": rng.randf() < 0.5, "facing": FACINGS[rng.randi() % 4] }
		var size: Vector2 = definition["size"]
		if turned["rotated"]:
			size = Vector2(size.y, size.x)
		var lo := field.position + size * 0.5
		var hi := (field.end - size * 0.5).max(lo)
		var at := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		out.append({ "key": key, "node": ObjectFactory.spawn(definition, at, holder, turned) })
	return out


## The damp stains down the north and south walls of `rect`, each starting on the wall it runs from
## (a piece facing away from it) and running out over the floor.
static func _stains(rect: Rect2, rng: RandomNumberGenerator, holder: Node2D, scale: float) -> Array:
	var definition := ObjectDefinitions.get_definition("wall_stain")
	var size: Vector2 = definition["size"]
	var half := WorldGenDistrictConfig.shell_wall * 0.5
	var out: Array = []
	for row: Array in STAINS:
		var north: bool = row[0] == "north"
		var y := (
			rect.position.y + half + size.y * 0.5 if north
			else rect.end.y - half - size.y * 0.5
		)
		var lo := rect.position.x + WorldGenShellConfig.shell_edge + size.x * 0.5
		var hi := rect.end.x - WorldGenShellConfig.shell_edge - size.x * 0.5
		for _i in _count(row[1], scale):
			var at := Vector2(rng.randf_range(lo, maxf(lo, hi)), y)
			var facing := Vector2.DOWN if north else Vector2.UP
			out.append({
				"key": "wall_stain",
				"node": ObjectFactory.spawn(definition, at, holder, { "facing": facing }),
			})
	return out
