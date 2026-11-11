class_name WorldRng
extends RefCounted
## General domain: each world's own chance and order, shared infrastructure like `FillBatch`
## (interface 11). A world is the node a match or test world is built under (`MatchBuilder.stage`
## registers it with the match's `seed`); anything in it finds its world by walking up to that node.
## - `of(node)` is the world's one `RandomNumberGenerator`, seeded from the match seed: what a
##   shot's spread, a casing's side, a blast's fragments, a chip of debris, a fall's jolt, a stun's
##   sway and a dropped item's toss draw from instead of the global `randf`. The same seed plays the
##   same draws, a different seed other ones, and two worlds in one process never share a stream.
## - `enrol(node)` / `order_of(id)` is each character's spawn order: its place, from 0, among the
##   characters its world has taken in (`Character._enter_tree` enrols it, again where it is
##   reparented into another world: it takes that world's next place and drops the old). The AI keys
##   every order or timing it used to take from an instance id on it (the sight cadence, who gives
##   way, whose claim wins a tie). An instance id follows what the process allocated before; a spawn
##   order does not. An id is still the key to look a character up by.
## - `frame_of(node)` is how many physics frames its world has run since its first character took
##   its place: the frame every AI cadence and phase is counted on (`perception_sight.gd`'s sight
##   cadence, `perception_house.gd`'s look). `Engine.get_physics_frames()` counts what the whole
##   process ran before the world did, so a match's phase would follow every test that ran ahead of
##   it; this starts at 0 with each world.
## Painters, world-gen, lighting and audio keep their own randomness.

## Mixed into the match seed, so the world's stream is not the stream of another draw from that seed
## (placement, guns, styles).
const SEED_SALT := 0x57524e47
## Where `order_of` starts counting for an id no live node holds: after every live character.
const GONE := 1 << 30

## World root instance id -> `{ rng, spawned }`.
static var _worlds := {}
## Enrolled node instance id -> its spawn order.
static var _orders := {}
## Enrolled node instance id -> the instance id of the world root that gave it that order.
static var _homes := {}


## Register `root` as a world whose stream is seeded from `match_seed` (a registered root again
## keeps the order it has handed out, and restarts its stream). Roots freed since are dropped.
static func register(root: Node, match_seed: int) -> void:
	for id: int in _worlds.keys():
		if not is_instance_id_valid(id):
			_worlds.erase(id)
	for id: int in _orders.keys():
		if not is_instance_id_valid(id):
			_orders.erase(id)
			_homes.erase(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed ^ SEED_SALT
	var kept: Dictionary = _worlds.get(root.get_instance_id(), { "spawned": 0, "began": -1 })
	_worlds[root.get_instance_id()] = {
		"rng": rng, "spawned": kept["spawned"], "root": root.get_instance_id(),
		"began": kept["began"],
	}


## The stream of `node`'s world. A node under no registered root belongs to the topmost node above
## it, registered on the spot with seed 0.
static func of(node: Node) -> RandomNumberGenerator:
	return _entry_of(node)["rng"]


## `node`'s place in its world's spawn order, taking the next one when it has none yet (so a node
## enrolled twice in one world keeps its first). A node now under another world than the one that
## numbered it (the human, built in the scene and reparented into the match) drops that order and
## takes the next of the world it is in.
static func enrol(node: Node) -> int:
	var id := node.get_instance_id()
	var entry := _entry_of(node)
	if _orders.has(id) and _homes[id] == entry["root"]:
		return _orders[id]
	var order: int = entry["spawned"]
	entry["spawned"] = order + 1
	if int(entry["began"]) < 0:
		entry["began"] = Engine.get_physics_frames()
	_orders[id] = order
	_homes[id] = entry["root"]
	return order


## The physics frames `node`'s world has run since its first character took its place (0 on that
## frame, and for a world with none yet, which starts counting at this ask): the one clock a cadence
## or a phase of the AI is counted on, never `Engine.get_physics_frames()`.
static func frame_of(node: Node) -> int:
	var entry := _entry_of(node)
	var now := Engine.get_physics_frames()
	if int(entry["began"]) < 0:
		entry["began"] = now
	return now - int(entry["began"])


## The spawn order of the node with instance id `id`: its own once enrolled, enrolled now for a live
## node that never was (a stand-in), `GONE` plus the id for an id nothing holds (after every live
## one, and among themselves in the id's own order).
static func order_of(id: int) -> int:
	var known: Variant = _orders.get(id)
	if known != null:
		return known
	var node := instance_from_id(id) as Node
	return enrol(node) if node != null else GONE + id


## Whether the node with instance id `a` was spawned before the one with `b`: the order every
## "the lower instance id wins" tie-break reads, the same in whatever order the process allocated.
static func before(a: int, b: int) -> bool:
	return order_of(a) < order_of(b)


## The registry entry of `node`'s world: the nearest registered root above it, else the topmost
## node's (registered on the spot).
static func _entry_of(node: Node) -> Dictionary:
	var top := node
	var at := node
	while at != null:
		var entry: Variant = _worlds.get(at.get_instance_id())
		if entry != null:
			return entry
		top = at
		at = at.get_parent()
	register(top, 0)
	return _worlds[top.get_instance_id()]
