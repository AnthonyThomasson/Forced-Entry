extends GameTest
## A piece settles by a hair after the district is built (its twin comes to rest, a footprint that
## was 4 vertices is outlined with 6) and that is not a change: the steering tiles it reaches are
## not due (#194 nav3d-a). Compared exactly, the first re-bake after a build re-baked 40 of a seed's
## 49 tiles for nothing, and the game's burst did the same once a match started. A tile's holes are
## unchanged when every hole outline matches within `NavSettle.TOLERANCE` (0.1 px), compared as
## shapes: a re-outline of the same footprint is the same hole. A piece moved half a pixel and a
## piece tipped over (D14) are changes.

const SEED := 7
## A piece's outline moved by this far (px) is settling; 0.5 px is a real move.
const SETTLE := 0.05
const MOVED := 0.5

var _district: Node2D
var _region: NavigationRegion2D
var _rooms: Array
var _site: NavSite


func describe() -> Dictionary:
	return {
		"name": "A piece settling by a hair does not make a steering tile due",
		"description": "In a district, once the steering tiles are baked, a piece settled by "
			+ "0.05 px or outlined with more vertices leaves every tile un-due; a piece moved "
			+ "0.5 px, or tipped over, makes the tiles it reaches due.",
		"tags": ["navigation", "district", "steering", "furniture"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	_district = t.world.get("district") as Node2D
	_region = t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	_rooms = WorldGen.district_rooms(_district)
	_site = NavBuilder.site_of(_region, _district, _rooms)
	NavBuilder.rebake_steering(_region, _district, _rooms)
	var furniture := NavBuilder.furniture_holes(_district)
	var characters := NavBuilder.character_holes(_district.get_parent())
	if not t.require(furniture.size() > 10, "premise: the district has furniture holes"):
		return
	t.expect_eq(_due(furniture, characters), 0, "premise: nothing is due after a re-bake")

	var piece := _index_of_a_square(furniture)
	if not t.require(piece >= 0, "premise: a hole with four corners"):
		return
	var outline: PackedVector2Array = furniture[piece]
	t.expect_eq(
		_due(_with(furniture, piece, _shifted(outline, Vector2(SETTLE, -SETTLE))), characters),
		0,
		"a piece settled by %s px leaves every tile un-due" % SETTLE,
	)
	t.expect_eq(
		_due(_with(furniture, piece, _more_vertices(outline)), characters),
		0,
		"the same footprint outlined with more vertices is no change",
	)
	var moved := _due(_with(furniture, piece, _shifted(outline, Vector2(MOVED, 0))), characters)
	t.check(
		moved >= 1 and moved <= 4,
		"a piece moved %s px makes %d tiles due (1 to 4)" % [MOVED, moved],
	)
	t.check(
		_due(_with(furniture, piece, _tipped(outline)), characters) >= 1,
		"a piece tipped over, its footprint now a long strip, makes its tiles due",
	)
	_leaning(t)
	var shrunk := furniture.duplicate()
	shrunk.remove_at(piece)
	t.check(_due(shrunk, characters) >= 1, "a piece gone makes its tiles due")


## A box that settled a hair off true is still the rectangle it stood as; a tipped one is not
## upright.
func _leaning(t: TestContext) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(40, 40, 40)
	var leaning := Transform3D(Basis(Vector3.RIGHT, 0.003), Vector3(100, 20, 100))
	t.expect_eq(
		NavTwins.footprint(box, leaning).size(),
		4,
		"a box leaning 0.003 rad (a resting piece's settle) is still the rectangle it stood as",
	)
	var tipped := Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(100, 20, 100))
	t.check(
		not NavTwins.upright(tipped) and NavTwins.upright(leaning),
		"a box tipped 0.3 rad is no longer upright",
	)


## How many tiles `furniture` and `characters` leave due.
func _due(furniture: Array, characters: Array) -> int:
	return NavTiles.due_tiles(_region, _site, furniture, characters).size()


## `holes` with the outline at `index` replaced by `outline`.
func _with(holes: Array, index: int, outline: PackedVector2Array) -> Array:
	var out := holes.duplicate()
	out[index] = outline
	return out


## The index of a hole of exactly four corners, 0 or more; -1 when none.
func _index_of_a_square(holes: Array) -> int:
	for i in holes.size():
		if (holes[i] as PackedVector2Array).size() == 4:
			return i
	return -1


func _shifted(outline: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in outline:
		out.append(point + by)
	return out


## `outline` with the midpoint of every second edge added: the same shape, more vertices.
func _more_vertices(outline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in outline.size():
		out.append(outline[i])
		if i % 2 == 0:
			out.append(outline[i].lerp(outline[(i + 1) % outline.size()], 0.5))
	return out


## A strip 4 px thick running 80 px out from the outline's first corner: a piece lying down.
func _tipped(outline: PackedVector2Array) -> PackedVector2Array:
	var at := outline[0]
	return PackedVector2Array([
		at, at + Vector2(80, 0), at + Vector2(80, 4), at + Vector2(0, 4),
	])
