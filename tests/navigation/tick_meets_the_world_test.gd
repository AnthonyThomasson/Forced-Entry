extends GameTest
## A district's tick (`NavTick`) is made over physics frames while the world goes on, and what it
## meets meanwhile must not change what it finds (#194, `tick.md`):
## - another caller's `furniture_holes` between its steps leaves its cursor alone: its footprints
##   are
##   the whole read, an open door's leaf hole in them once;
## - a piece moved, freed or added between two of its steps is caught by the next tick, which
##   converges on the whole read;
## - a planning bake that lands during the tick carved the holes the tick then finds, so the tick
##   starts no gather of them again; the control, without a landing, starts one;
## - the timer firing while it runs is skipped, and the updater disabled during it starts no burst
##   and no gather.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const SEED := 7
const MOVE_BY := 40.0
## Frames the tick may take to end (nine steady; the first steps of a moved world a few more).
const MOST_FRAMES := 40
const WAIT := 12.0

var _region: NavigationRegion3D
var _district: Node2D
var _timer: Timer
var _updater: Node
var _site: NavSite


func describe() -> Dictionary:
	return {
		"name": "A district's tick meets the world it is made in",
		"description": "Another reader between its steps, a piece moved, freed or added, a bake "
			+ "landing, the timer firing again and the updater disabled leave the tick right.",
		"tags": ["navigation", "district", "rebake", "perf"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", true)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	_region = t.world.find_children("NavRegion", "NavigationRegion3D", true, false)[0]
	_district = t.world.district
	_timer = t.world.get_node("NavUpdater/RebakeTimer") as Timer
	_updater = _timer.get_parent()
	for body in PlanProbe.pieces_under(_district):
		var lead := TwinSpace.leader_of(body)
		if lead != null:  # nothing but the moves below moves
			lead.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			lead.freeze = true
	var pieces := _free_pieces()
	if not t.require(pieces.size() >= 4, "premise: the district has free pieces"):
		return
	_timer.stop()  # the ticks are driven here
	await t.until(func() -> bool: return not _updater.busy(), 8.0)
	await t.seconds(1.0)  # whatever the first ticks started lands
	_site = NavBuilder.site_of(_region, _district, WorldGen.district_rooms(_district))
	await _check_cursor(t)
	await _check_world_moves_on(t, pieces)
	await _check_landing(t, pieces[2])
	await _check_skipped_and_disabled(t, pieces[3])


## `NavBuilder.furniture_holes` between two steps: the tick's footprints are the whole read, the
## leaf of an open door in them once.
func _check_cursor(t: TestContext) -> void:
	var door := await _open_leaf(t)
	if not t.require(door != null, "premise: a door stands open with its leaf carved"):
		return
	var whole := NavBuilder.furniture_holes(_district)
	var tick := _tick_of(whole)
	t.check(not tick.step(), "premise: the first step leaves pieces to read")
	NavBuilder.furniture_holes(_district)
	var steps := 0
	while not tick.step() and steps < MOST_FRAMES:
		steps += 1
	t.expect_eq(tick.furniture, whole, "the tick's footprints are the whole read")
	t.expect_eq(
		tick.furniture.count(NavLeaves.hole(door)), 1, "the open leaf's hole is in them once")
	door.call("turn_by", -360.0, null)  # shut again: the bakes below carve no leaf
	await t.seconds(2.0)


## A piece moved, one freed and one added after the tick read them: the next tick converges.
func _check_world_moves_on(t: TestContext, pieces: Array[Node2D]) -> void:
	var tick := _tick_of(NavBuilder.furniture_holes(_district))
	tick.step()
	_shove(pieces[0], Vector2(MOVE_BY, 0.0))
	var freed := pieces[1]
	freed.queue_free()
	var added := Node2D.new()
	added.add_to_group(TwinSpace.PIECES)
	_district.add_child(added)
	await t.frames(TwinSpace.PARK_SPREAD + 2)
	var steps := 0
	while not tick.step() and steps < MOST_FRAMES:
		steps += 1
	t.check(steps < MOST_FRAMES, "the tick ended (%d steps more)" % steps)
	var next := _tick_of(tick.furniture)
	steps = 0
	while not next.step() and steps < MOST_FRAMES * 2:
		steps += 1
	t.check(next.furniture_moved, "the next tick finds what moved since")
	t.expect_eq(next.furniture, NavBuilder.furniture_holes(_district), "and the whole read")
	added.queue_free()


## A bake that lands during the tick: no gather of the holes it carved. Without one, a gather.
func _check_landing(t: TestContext, piece: Node2D) -> void:
	_shove(piece, Vector2(0.0, MOVE_BY))
	await t.frames(TwinSpace.PARK_SPREAD + 2)
	_timer.timeout.emit()
	await t.frames(1)
	t.check(_updater.ticking(), "premise: the tick is under way")
	_updater._on_landed(NavBuilder.furniture_holes(_district))  # a planning bake landed
	await _until_made(t)
	t.check(not _updater.busy(), "a bake landed during the tick: no gather is started")
	await t.seconds(1.0)
	_shove(piece, Vector2(0.0, -MOVE_BY))
	await t.frames(TwinSpace.PARK_SPREAD + 2)
	_timer.timeout.emit()
	await _until_made(t)
	t.check(_updater.busy(), "control: with no landing the tick starts a gather")
	await t.until(func() -> bool: return not _updater.busy(), WAIT)


## The timer firing again during a tick leaves it be; the updater disabled during one starts
## nothing.
func _check_skipped_and_disabled(t: TestContext, piece: Node2D) -> void:
	await t.seconds(1.0)
	_shove(piece, Vector2(MOVE_BY, 0.0))
	await t.frames(TwinSpace.PARK_SPREAD + 2)
	_timer.timeout.emit()
	await t.frames(1)
	var running: Variant = _updater._tick
	_timer.timeout.emit()
	t.check(
		running != null and _updater._tick == running,
		"the timer firing during the tick leaves it running, not made again",
	)
	_updater.enabled = false
	await _until_made(t)
	t.check(not _updater.busy(), "disabled during the tick: no gather is started")
	t.check(_updater.tiles_in_play().is_empty(), "and no burst")
	_updater.enabled = true


## A tick of the district against the footprints `furniture` and the characters now.
func _tick_of(furniture: Array) -> NavTick:
	return NavTick.new(
		_region, _district, _site,
		[furniture, NavBuilder.character_holes(_district.get_parent())], 4.0)


## Frames until the updater's tick is made (its end is a frame's, the apply with it).
func _until_made(t: TestContext) -> void:
	for _i in MOST_FRAMES:
		if not _updater.ticking():
			return
		await t.frames(1)
	await t.frames(1)


## A door opened to its stop whose leaf is carved, or null; no other door stays open.
func _open_leaf(t: TestContext) -> Node2D:
	for door in NavLeaves.doors_of(_district):
		door.call("open_fully", null)
	await t.seconds(2.0)
	var found: Node2D = null
	for door in NavLeaves.doors_of(_district):
		if found == null and not NavLeaves.hole(door).is_empty():
			found = door
		else:
			door.call("turn_by", -360.0, null)
	await t.seconds(2.0)
	return found


func _shove(piece: Node2D, by: Vector2) -> void:
	TwinSpace.leader_of(piece).global_position += PlanSpace.lift(by)
	piece.global_position += by


## The district's free pieces: a rigid body led by a 3D body of the twin space.
func _free_pieces() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for body in PlanProbe.pieces_under(_district):
		if TwinSpace.leader_of(body) != null:
			out.append(body)
		if out.size() == 4:
			break
	return out
