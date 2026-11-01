extends GameTest
## The ring of shells round a district (#182): each is a roofless closed building: a solid outer
## wall with no doorway all the way round, a concrete floor and a few partition walls whose doorways
## all lie inside. A shell draws a style by the seed (bare; under construction with rebar, rubble,
## scaffold and cement bags; derelict with trash, puddles, cardboard and wall stains), the
## same style for the same seed and all three across seeds. Shells are no rooms for the AI: no room
## of `WorldGen.district_rooms` lies in one, and nothing they hold gives light. Read through
## `DistrictReads.get_shells`: `{ rect, node, holder, style, partitions, decor }`.

const SEEDS := [1, 2, 3, 4, 5, 6]
const ENTRANCE := Vector2(6000, 6000)
const STYLES := ["bare", "site", "derelict"]
## What each style may hold (catalogue keys).
const DECOR := {
	"bare": [],
	"site": ["rebar", "rubble", "scaffold", "cement_bags"],
	"derelict": ["trash", "puddle", "cardboard", "wall_stain"],
}
## A decorated shell holds at least this many pieces, a shell at least this many partitions.
const DECOR_MIN := 4
const PARTITIONS_MIN := 2
const SLACK := 1.0


func describe() -> Dictionary:
	return {
		"name": "A district's shells are closed, roofless, styled by the seed and no rooms",
		"description": "Every shell has an unbroken outer wall, a floor and partitions whose "
			+ "doorways are all inside; its decor follows its style; no room or light is in one.",
		"tags": ["worldgen", "district", "shell"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## The length of wall the outer wall `node` leaves standing, over its outline's length.
func _standing(node: Node) -> float:
	var total := 0.0
	for seg: PackedVector2Array in node.wall_segments():
		total += seg[0].distance_to(seg[1])
	return total


func _check_closed(t: TestContext, label: String, shell: Dictionary) -> void:
	var rect: Rect2 = shell["rect"]
	var outline := 2.0 * (rect.size.x + rect.size.y)
	t.check((shell["node"].openings as Array).is_empty(), "%s: a doorway in the outer wall" % label)
	t.check(absf(_standing(shell["node"]) - outline) <= SLACK, "%s: outer wall has a gap" % label)
	var at: Vector2 = shell["node"].global_position
	t.check(at.is_equal_approx(rect.position), "%s: the wall is off its rect" % label)
	t.check(shell["holder"].find_child("Floor", true, false) != null, "%s: no floor" % label)


## Whether `point` lies on the outline of `rect`.
func _on_outline(rect: Rect2, point: Vector2) -> bool:
	var inside := rect.grow(SLACK).has_point(point) and not rect.grow(-SLACK).has_point(point)
	return inside


func _check_partitions(t: TestContext, label: String, shell: Dictionary) -> void:
	var parts: Array = shell["partitions"]
	t.check(parts.size() >= PARTITIONS_MIN, "%s: %d partitions" % [label, parts.size()])
	var rect: Rect2 = shell["rect"]
	for wall: Node2D in parts:
		var area := Rect2(wall.global_position, wall.get("size"))
		t.check(rect.grow(SLACK).encloses(area), "%s: a partition leaves the shell" % label)
		for opening: Dictionary in wall.get("openings"):
			var centre := _opening_point(wall, opening)
			t.check(not _on_outline(rect, centre), "%s: a doorway in the outline" % label)


## The world point at the middle of `opening` (a Wall.Side format dict) on `wall`.
func _opening_point(wall: Node2D, opening: Dictionary) -> Vector2:
	var size: Vector2 = wall.get("size")
	var offset: float = opening["offset"]
	var local := Vector2.ZERO
	match int(opening["side"]):
		WallFactory.WallScript.Side.TOP:
			local = Vector2(offset, 0.0)
		WallFactory.WallScript.Side.BOTTOM:
			local = Vector2(offset, size.y)
		WallFactory.WallScript.Side.LEFT:
			local = Vector2(0.0, offset)
		_:
			local = Vector2(size.x, offset)
	return wall.global_position + local


func _check_decor(t: TestContext, label: String, shell: Dictionary) -> void:
	var style: String = shell["style"]
	var decor: Array = shell["decor"]
	t.check(style in STYLES, "%s: style %s" % [label, style])
	if style == "bare":
		t.check(decor.is_empty(), "%s: a bare shell holds decor" % label)
		return
	t.check(decor.size() >= DECOR_MIN, "%s: %s holds %d pieces" % [label, style, decor.size()])
	for piece: Dictionary in decor:
		var node: Node2D = piece["node"]
		t.check(piece["key"] in DECOR[style], "%s: %s in a %s shell" % [label, piece["key"], style])
		t.check(not node.get("solid"), "%s: %s is solid" % [label, piece["key"]])
		var inside: bool = (shell["rect"] as Rect2).grow(SLACK).has_point(node.global_position)
		t.check(inside, "%s: %s lies outside its shell" % [label, piece["key"]])
		t.check((node.call("get_lights") as Array).is_empty(), "%s: decor gives light" % label)


## No room of the district lies in a shell, and the shells hold no room data of their own.
func _check_not_rooms(t: TestContext, label: String, district: Node2D, shells: Array) -> void:
	for room: Dictionary in WorldGen.district_rooms(district):
		for shell: Dictionary in shells:
			t.check(
				not (room["rect"] as Rect2).intersects((shell["rect"] as Rect2).grow(-SLACK)),
				"%s: room %s is in a shell" % [label, room["key"]],
			)
	for shell: Dictionary in shells:
		t.check(not shell["holder"].has_meta("rooms"), "%s: a shell carries rooms" % label)


func run(t: TestContext) -> void:
	var styles := {}
	var first: Array = []
	for district_seed in SEEDS:
		var district := WorldGen.generate_district(district_seed, "", ENTRANCE, t.world)
		var shells := DistrictReads.get_shells(district)
		var label := "seed %d" % district_seed
		t.check(shells.size() == 16, "%s: %d shells" % [label, shells.size()])
		_check_not_rooms(t, label, district, shells)
		for i in shells.size():
			var name := "%s shell %d" % [label, i]
			_check_closed(t, name, shells[i])
			_check_partitions(t, name, shells[i])
			_check_decor(t, name, shells[i])
			styles[shells[i]["style"]] = true
		var mine := shells.map(func(s: Dictionary) -> String: return s["style"])
		if district_seed == SEEDS[0]:
			first = mine
		district.queue_free()
		await t.frames(2)
	for style: String in STYLES:
		t.check(styles.has(style), "no %s shell across the seeds" % style)
	var again := WorldGen.generate_district(SEEDS[0], "", ENTRANCE, t.world)
	var repeat := DistrictReads.get_shells(again).map(
		func(s: Dictionary) -> String: return s["style"],
	)
	t.check(repeat == first, "the same seed gives the same styles")
