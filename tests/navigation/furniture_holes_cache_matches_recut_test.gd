extends GameTest
## The furniture holes are cut again only for the pieces moved, dented, destroyed or added since
## the last tick (#192, rule 27): a tick where nothing changed walks no tree and cuts no hull, a
## moved or dented piece costs one cut and a destroyed or added one a re-listing of the pieces, and
## after each of those the holes are exactly what a full re-cut of every piece gives
## (`NavHoles.plain`, the reference). `NavHoles.walks` counts the tree walks that find the pieces
## and `NavHoles.cuts` the hulls cut from a body's shapes.

const SEED := 7
const PLAN := "garage_home"


func describe() -> Dictionary:
	return {
		"name": "Furniture holes cache matches a re-cut",
		"description": "furniture_holes cuts only the pieces that moved, were dented, destroyed or "
			+ "added since the last call, and equals a full re-cut after each.",
		"tags": ["bake", "furniture", "holes", "perf"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var house: Node2D = t.world.get("house")
	await t.frames(2)
	var pieces: Array = house.find_children("*", "RigidBody2D", true, false)
	if not t.require(pieces.size() >= 20, "the house is furnished (%d pieces)" % pieces.size()):
		return
	var first := NavBuilder.furniture_holes(house)
	t.check(first == NavHoles.plain(house), "the first tick equals a re-cut (%d)" % first.size())

	# A tick where nothing changed: the same holes for no walk and no cut.
	_reset_counts()
	var quiet := NavBuilder.furniture_holes(house)
	t.check(quiet == first, "a quiet tick returns the same holes")
	t.check(
		NavHoles.walks == 0 and NavHoles.cuts == 0,
		"and walks no tree and cuts no hull (%d walks, %d cuts)" % [NavHoles.walks, NavHoles.cuts],
	)

	var moved: RigidBody2D = null
	for piece: RigidBody2D in pieces:
		if not piece.freeze:
			moved = piece
			break
	if not t.require(moved != null, "a piece that can be moved"):
		return
	moved.freeze = true  # a free body is put back by the next physics step
	await t.frames(1)
	NavBuilder.furniture_holes(house)
	await _check_moved(t, house, moved, first)
	await _check_dented(t, house, moved)
	await _check_added(t, house)
	await _check_destroyed(t, house, pieces)


## A piece moved and turned costs one cut, and its hole moved with it.
func _check_moved(
	t: TestContext,
	house: Node2D,
	moved: RigidBody2D,
	before: Array,
) -> void:
	moved.global_position += Vector2(23.0, -11.0)
	moved.rotation += 0.4
	await t.frames(1)
	_reset_counts()
	var after := NavBuilder.furniture_holes(house)
	t.check(NavHoles.cuts == 1, "a moved piece is cut once (%d cuts)" % NavHoles.cuts)
	t.check(NavHoles.walks == 0, "and moving it walks no tree (%d walks)" % NavHoles.walks)
	t.check(after == NavHoles.plain(house), "after a piece is moved the holes equal a full re-cut")
	t.check(after != before, "and the moved piece's hole moved with it")


## A piece shot up has its collider rebuilt in convex pieces a frame later: one cut, still equal.
func _check_dented(t: TestContext, house: Node2D, piece: RigidBody2D) -> void:
	var hit := HitInfo.new()
	hit.normal = Vector2.RIGHT
	hit.direction = Vector2.LEFT
	hit.damage = 60.0
	hit.speed_factor = 1.0
	for k in 4:
		hit.position = piece.global_position + Vector2.from_angle(k * 1.3) * 12.0
		piece.take_hit(hit)
	await t.frames(3)  # the collider is rebuilt from the dents a frame later
	_reset_counts()
	var dented := NavBuilder.furniture_holes(house)
	t.check(NavHoles.cuts == 1, "a dented piece is cut once (%d cuts)" % NavHoles.cuts)
	t.check(NavHoles.walks == 0, "and dinting it walks no tree (%d walks)" % NavHoles.walks)
	t.check(dented == NavHoles.plain(house), "after a piece is dented the holes equal a re-cut")


## A piece added is found, cut once, and the holes equal a full re-cut.
func _check_added(t: TestContext, house: Node2D) -> void:
	var before := NavBuilder.furniture_holes(house)
	var added := RigidBody2D.new()
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30.0, 20.0)
	col.shape = rect
	added.add_child(col)
	added.freeze = true  # an added piece that shoves nothing, and is shoved by nothing
	house.add_child(added)
	added.global_position = house.global_position + Vector2(-400.0, -400.0)
	await t.frames(1)
	_reset_counts()
	var after := NavBuilder.furniture_holes(house)
	t.check(NavHoles.cuts == 1, "an added piece is cut once (%d cuts)" % NavHoles.cuts)
	t.check(after.size() == before.size() + 1, "its hole is in the holes")
	t.check(after == NavHoles.plain(house), "after a piece is added the holes equal a full re-cut")
	_reset_counts()
	NavBuilder.furniture_holes(house)
	t.check(
		NavHoles.walks == 0 and NavHoles.cuts == 0,
		"the tick after that is quiet again (%d walks, %d cuts)" % [NavHoles.walks, NavHoles.cuts],
	)


## A piece destroyed leaves no hole, and no other piece is cut again.
func _check_destroyed(t: TestContext, house: Node2D, pieces: Array) -> void:
	var before := NavBuilder.furniture_holes(house)
	var gone: RigidBody2D = null
	for piece: RigidBody2D in pieces:
		if not piece.freeze and piece.find_children("*", "CollisionShape2D", false, false):
			gone = piece
	if not t.require(gone != null, "a solid piece to destroy"):
		return
	gone.queue_free()
	await t.frames(2)
	_reset_counts()
	var after := NavBuilder.furniture_holes(house)
	t.check(NavHoles.cuts == 0, "no piece is cut again for a destroyed one (%d)" % NavHoles.cuts)
	t.check(after.size() == before.size() - 1, "the destroyed piece's hole is gone")
	t.check(after == NavHoles.plain(house), "after a piece is destroyed the holes equal a re-cut")


func _reset_counts() -> void:
	NavHoles.walks = 0
	NavHoles.cuts = 0
