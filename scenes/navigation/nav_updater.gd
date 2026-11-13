extends Node
## Navigation domain: keeps the baked navigation map in step with furniture that has been shoved
## around. The holes `NavBuilder.build` carves are a snapshot of where the furniture stood at bake
## time; as pieces are bulldozed off their spots those holes go stale and paths route around empty
## floor. This node re-bakes the map on an interval (`NavRebake.planning`) so the holes follow
## the furniture's CURRENT positions and paths route around scattered objects. The living characters
## are holes in the STEERING region (`NavRebake.steering`), so it follows them as they
## walk, appear and die. It only re-bakes when a piece or a character has actually moved past
## `move_threshold`, so an at-rest scene costs a cheap per-tick compare and no bake. The planning
## region only re-bakes for furniture. Bulldozing is still the behaviour BETWEEN re-bakes (and
## for non-solid decor, which is never carved). A script-only node the match builder builds once
## after the initial bake; imports nothing from other domains — it is handed plain Nodes.

## Whether the periodic re-bake runs at all. Off = the map stays the static bake-time snapshot.
@export var enabled: bool = true
## Seconds between move checks. Each check is cheap (furniture transforms only); a re-bake runs only
## on a check that finds movement, so this caps how often the (heavier) re-bake can happen.
@export var interval: float = 0.75
## How far (px) any furniture footprint point must shift since the last bake before the map is
## re-baked, so micro-jitter from settling physics bodies doesn't trigger constant re-bakes.
@export var move_threshold: float = 4.0

## The baked region to re-bake in place, the house whose furniture is tracked, and the rooms +
## agent radius the bake needs — all handed in by `setup`.
var _region: NavigationRegion2D
var _house: Node2D
var _rooms: Array = []
var _agent_radius: float = NavBuilder.AGENT_RADIUS
## Optional furniture-hole debug overlay (nav_debug.gd), re-snapshotted after each re-bake so it
## keeps matching the live navmesh. Null when no overlay is wired.
var _nav_debug: Node = null
## The furniture footprints (NavBuilder.furniture_holes) and the character footprints
## (NavBuilder.character_holes) as of the last bake of each, compared each tick to detect movement.
var _baseline: Array = []
var _character_baseline: Array = []
## Whether the planning region's re-bake is under way, gathering a step a frame (`_gather`) or
## baking on a worker thread (`NavBake`); a furniture move meanwhile waits for the first tick after
## the bake lands (the baseline is set from what that bake
## carved, so it is caught then).
var _baking := false
## A district's planning gather in progress, a step a physics frame (`_physics_process`). Null
## between gathers.
var _gather: NavGather = null
## A district's steering tiles of this tick, baked one a physics frame (`_physics_process`) and
## landed together (`NavTileBurst`).
var _burst := NavTileBurst.new()


## A script-only node: the gather's steps run in `_physics_process`, only while there is one (the
## engine switches it on at ready, for any node that has the method).
func _ready() -> void:
	set_physics_process(false)


## One physics frame of the updater's work: the next due steering tile is baked (never a second on
## a frame the tick already baked one on), and one step of the district's planning gather runs; the
## finished gather is swapped in, whole, and baked. A match torn down meanwhile leaves the tiles and
## the gather unfinished and nothing started.
func _physics_process(_delta: float) -> void:
	if not _alive():
		_burst.clear()
		_gather = null
		_baking = false
	elif _burst.pending():
		_burst.step(_region, NavBuilder.site_of(_region, _house, _rooms, _agent_radius))
	if _gather != null and _gather.step():
		var gathered := _gather
		_gather = null
		NavRebake.swap(
			_region, gathered.site, gathered.job, gathered.ring,
			_on_landed.bind(gathered.furniture),
		)
	if _gather == null and not _burst.pending():
		set_physics_process(false)


## The steering tiles of a district still to bake or landing with this tick's burst, for tests.
func tiles_in_play() -> Array[NavigationRegion2D]:
	return _burst.tiles_in_play()


## Wire the updater to the baked map and start the interval. `region` is NavBuilder.build's result,
## `house`/`rooms`/`agent_radius` are what a re-bake needs, `nav_debug` is the optional overlay to
## refresh. Captures the current furniture layout as the baseline and starts a repeating Timer.
func setup(
	region: NavigationRegion2D,
	house: Node2D,
	rooms: Array,
	nav_debug: Node = null,
	agent_radius: float = NavBuilder.AGENT_RADIUS,
) -> void:
	_region = region
	_house = house
	_rooms = rooms
	_agent_radius = agent_radius
	_nav_debug = nav_debug
	_baseline = NavBuilder.furniture_holes(house)
	_character_baseline = NavBuilder.character_holes(house.get_parent())
	var timer := Timer.new()
	timer.name = "RebakeTimer"
	timer.wait_time = max(interval, 0.05)
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)


## One interval tick: if furniture has moved since the last bake, re-carve the planning region's
## holes at the live positions, baked on a worker thread (`NavRebake.planning`; a
## furniture move while one is in flight waits for the next tick) and the steering region's in
## place; if only a character has, re-carve the steering region. Refreshes the overlay after either.
## Nothing moved, nothing baked. A lone house's steering region lands in the tick's own frame; a
## district's due tiles are baked one a physics frame, the walker's own first, and land together
## with the last (`NavTileBurst`: one steering-map sync a tick, as a bake of them all at once
## had), so a walker looking for a way round a body at rest sees it up to the burst's frames later
## (`navigation/steering_rebake_lands_in_its_tick`, `navigation/tile_rebake_one_a_frame`). A lone
## house's planning gather goes with it; a district's is a job of a few physics frames (`NavGather`,
## `_physics_process`), swapped in whole and baked on the worker thread, and a move meanwhile waits
## for the next tick after it.
func _on_tick() -> void:
	if not enabled or _region == null or not is_instance_valid(_house):
		return
	var furniture := NavBuilder.furniture_holes(_house)
	var characters := NavBuilder.character_holes(_house.get_parent())
	var furniture_moved := _moved(_baseline, furniture)
	if not furniture_moved and not _moved(_character_baseline, characters):
		return
	# Both bakes carve the footprints just measured; a house's walls are parsed once for both. A
	# district's tiles parse the towers they reach, and its planning gather the rest.
	var site := NavBuilder.site_of(_region, _house, _rooms, _agent_radius)
	var planning := furniture_moved and not _baking
	var staged := site.bounds.has_area()
	var walls := {}
	if planning and not staged:
		walls = _rebake_planning(site, furniture)
	if staged:
		_burst.land()  # a burst still open: what it holds is on its tiles before they are read
		_burst.begin(NavTiles.due_tiles(
			_region,
			site,
			furniture,
			characters,
			NavTiles.walking_at(_house.get_parent()),
		))
		_burst.step(_region, site)
	else:
		NavRebake.steering(_region, site, furniture, characters, walls)
	_character_baseline = characters
	_refresh_overlay()
	if planning and staged:
		_baking = true
		_gather = NavGather.new(_region, site, _baseline, furniture)
	set_physics_process(_gather != null or _burst.pending())


## What a planning bake's landing does: the baseline is what it carved (`furniture`), the next move
## may start a bake, the overlay follows. Handed over as a bound method, not a lambda: a world torn
## down while its bake is in flight frees the updater, a method callable of a freed object is not
## `is_valid` (the landing skips it), and a lambda that held the updater was still called, an
## engine error ("Bad address index") logged into whatever ran next.
func _on_landed(furniture: Array) -> void:
	_baking = false
	_baseline = furniture
	_refresh_overlay()


## Gather the planning bake of `site` from the furniture footprints `furniture` and start it on a
## worker thread; the baseline is set from what it carved when it lands. Returns the walls
## it parsed, for a house's steering bake to share.
func _rebake_planning(site: NavSite, furniture: Array) -> Dictionary:
	var walls := NavTiles.walls_after(_region, site, _baseline, furniture)
	_baking = true
	NavRebake.planning(_region, site, furniture, _on_landed.bind(furniture), walls)
	return walls


## Whether the updater's region and house are still standing after a wait (the match may have been
## torn down meanwhile).
func _alive() -> bool:
	return is_inside_tree() and is_instance_valid(_region) and is_instance_valid(_house)


## Re-snapshot the overlay so it matches the re-baked holes.
func _refresh_overlay() -> void:
	if (_nav_debug != null
			and is_instance_valid(_nav_debug)
			and _nav_debug.has_method("setup")
			and is_instance_valid(_house)):
		_nav_debug.setup(_house)


## Whether the footprints `b` differ from `a` enough to warrant a re-bake: a different piece
## count, or any footprint point shifted more than `move_threshold`. Both come from
## the same function, so points line up one-to-one when the piece count is unchanged.
func _moved(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return true
	for i in a.size():
		var pa: PackedVector2Array = a[i]
		var pb: PackedVector2Array = b[i]
		if pa.size() != pb.size():
			return true
		for j in pa.size():
			if pa[j].distance_to(pb[j]) > move_threshold:
				return true
	return false
