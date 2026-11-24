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
var _region: NavigationRegion3D
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
## A district's steering tiles of this tick, started baking a physics frame each
## (`_physics_process`) and landed together `NavBakeConfig.tile_frames` after the last
## (`NavTileBurst`).
var _burst := NavTileBurst.new()
## A district's tick in progress, a step a physics frame (`NavTick`). Null between ticks.
var _tick: NavTick = null


## A script-only node: the gather's steps run in `_physics_process`, only while there is one (the
## engine switches it on at ready, for any node that has the method).
func _ready() -> void:
	set_physics_process(false)


## A world torn down with a burst or a gather under way: its threads are waited for, none is left
## running.
func _exit_tree() -> void:
	_burst.clear()
	if _gather != null:
		_gather.abandon()
		_gather = null


## One physics frame of the updater's work: the next due steering tile is started baking on a
## worker thread (never a second on a frame the tick already started one on), and one step of the
## district's planning gather runs; the finished gather is swapped in, whole, and baked. A match
## torn down meanwhile leaves the tiles and the gather unfinished and nothing started.
func _physics_process(_delta: float) -> void:
	if not _alive():
		_burst.clear()
		if _gather != null:
			_gather.abandon()
		_gather = null
		_tick = null
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
	if _tick != null and _tick.step():
		var made := _tick
		_tick = null
		_apply(made)
	if _gather == null and _tick == null and not _burst.pending():
		set_physics_process(false)


## Whether a district's tick is under way (`NavTick`), for tests.
func ticking() -> bool:
	return _tick != null


## Whether a tick, a planning gather or a planning bake is under way, for tests.
func busy() -> bool:
	return _tick != null or _gather != null or _baking


## The steering tiles of a district still to bake or landing with this tick's burst, for tests.
func tiles_in_play() -> Array[NavigationRegion3D]:
	return _burst.tiles_in_play()


## Wire the updater to the baked map and start the interval. `region` is NavBuilder.build's result,
## `house`/`rooms`/`agent_radius` are what a re-bake needs, `nav_debug` is the optional overlay to
## refresh. Captures the current furniture layout as the baseline and adds a repeating Timer,
## stopped until `start()`.
func setup(
	region: NavigationRegion3D,
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
	# Counted in the physics pass, like the sim it re-bakes for, and started by `start`.
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	timer.autostart = false
	timer.timeout.connect(_on_tick)
	add_child(timer)


## Start the interval. A timer counts from the step it is added in or the next, by whether it was
## added before that step's pass reached it or after, so one started in `setup` ticked a frame
## earlier or later against the fight by the point of the frame the world was built from (a live Von
## test builds it from the launcher's `_process`, a replay from a physics step's signal, a second
## run of a test from where gdUnit resumed it), and the re-bake that landed a frame apart gave the
## same fight a different navmesh. The caller starts it on the frame the world's bodies are placed
## on, a continuation of a physics step's signal whatever the build began in: `MatchBuilder.stage`
## with `wait_nav` (a stage without it returns in the phase it began in, and so does the timer).
func start() -> void:
	var timer := get_node_or_null("RebakeTimer") as Timer
	if timer != null and timer.is_stopped():
		timer.start()


## One interval tick: if furniture has moved since the last bake, re-carve the planning region's
## holes at the live positions, baked on a worker thread (`NavRebake.planning`; a furniture move
## while one is in flight waits for the next tick) and the steering region's in place; if only a
## character has, re-carve the steering region. Refreshes the overlay after either. Nothing moved,
## nothing baked. A lone house's tick is made here, at once, its steering region landing in the
## tick's own frame. A district's tick is a job of a few physics frames (`NavTick`: the footprints
## read a slice a frame, the due tiles found a slice a frame, `_physics_process` steps it), and
## then `_apply` starts what it found: the due tiles are started baking a frame each, the walker's
## own first, and land together `NavBakeConfig.tile_frames` after the last (`NavTileBurst`: one
## steering-map sync a tick), so a walker looking for a way round a body at rest sees it up to the
## burst's frames later (`navigation/tile_rebake_one_a_frame`), and the planning gather
## (`NavGather`) is a job of a few physics frames too, swapped in whole and baked on the worker
## thread. A tick still running when the timer fires, and a furniture move while the gather runs,
## wait for the
## next tick.
func _on_tick() -> void:
	if not enabled or _region == null or not is_instance_valid(_house):
		return
	var site := NavBuilder.site_of(_region, _house, _rooms, _agent_radius)
	if site.bounds.has_area() and _house.is_inside_tree():
		if _tick == null:
			_burst.land()  # a burst still open: what it holds is on its tiles before they are read
			_tick = NavTick.new(
				_region, _house, site, [_baseline, _character_baseline], move_threshold)
			set_physics_process(true)
		return
	var furniture := NavBuilder.furniture_holes(_house)
	var characters := NavBuilder.character_holes(_house.get_parent())
	var furniture_moved := NavTick.moves(_baseline, furniture, move_threshold)
	if not furniture_moved and not NavTick.moves(_character_baseline, characters, move_threshold):
		return
	# Both bakes carve the footprints just measured; a house's walls are parsed once for both.
	var walls := {}
	if furniture_moved and not _baking:
		walls = _rebake_planning(site, furniture)
	NavRebake.steering(_region, site, furniture, characters, walls)
	_character_baseline = characters
	_refresh_overlay()


## A district's finished tick (`NavTick`, the frames after the timer): when something moved, the due
## tiles start their burst (the first tile is started by the next physics frame) and a furniture
## move starts the planning gather, from the baseline as it stands.
func _apply(made: NavTick) -> void:
	if not made.moved or not is_instance_valid(_house):
		return
	var site := NavBuilder.site_of(_region, _house, _rooms, _agent_radius)
	_burst.begin(made.due)
	_character_baseline = made.characters
	_refresh_overlay()
	if made.furniture_moved and not _baking:
		_baking = true
		_gather = NavGather.new(_region, site, _baseline, made.furniture)


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
