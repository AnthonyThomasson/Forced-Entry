class_name StillMerge
extends Node
## Art domain, the still world drawn in merged chunks (interface 27, `domain-art/still-merge.md`):
## the carrier offers each still mesh it carries; once it has settled it is copied into the chunk
## of its square of ground (`MergeChunk`), and its own instance is left undrawn (only in the
## rendering server: the node, its `visible`, its layers and its parameters are as they were, so
## everything that reads or writes them goes on). The moment its look or place differs from what
## was copied (the wall fade, a dent, a shove, a swing, hidden, freed) its vertices leave the chunk
## and it draws itself again, in the same frame, before the picture is drawn; when the look is the
## copied one again (a wall whole again) it returns. A chunk is never built again, so a change in a
## match costs the one mesh's vertices. Building is spread: each frame looks at a few waiting
## meshes and builds at most one chunk. What tells of a change: a `Watch` child (moves, shown or
## hidden, in or out of the tree) and `MeshNodes.changed` (every write of a mesh's look).

## It judges after every script that writes a mesh has run.
const LAST := 1000
## The age every waiting mesh is taken as when all are merged at once (`merge_now`).
const ANY_AGE := 0x7fffffff

## Whether meshes are gathered into chunks (off: those already merged stay until `release`).
var enabled := MirrorMergeConfig.enabled
## Meshes waiting to join, and those a chunk holds, by node instance id.
var _waiting: Dictionary = {}
var _held: Dictionary = {}
var _chunks: Array[MergeChunk] = []
## The held meshes to judge before the next picture.
var _dirty: Dictionary = {}
## The round over the waiting meshes: the ids still to look at, the meshes gathered by chunk key,
## the groups to build, and the frame the next round may start.
var _round: Array = []
var _groups: Dictionary = {}
var _to_build: Array = []
var _next_round := 0
var _frame := 0


func _init() -> void:
	name = "StillMerge"
	process_priority = LAST
	# the camera turns and the walls fade while the tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _enter_tree() -> void:
	RenderingServer.frame_pre_draw.connect(judge)


func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(judge)
	release()
	MergeSource.clear()


func _process(_delta: float) -> void:
	_frame += 1
	judge()
	if not enabled:
		return
	if not _to_build.is_empty():
		_build(_to_build.pop_back())
	else:
		_look(MirrorMergeConfig.looked_per_frame, _frame)


## Offer the meshes of `root` (a carried still mesh: it and every mesh under it).
func offer(root: Node) -> void:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node: MeshInstance3D in meshes:
		if MergeMember.suits(node):
			_wait(node, _frame + MirrorMergeConfig.settle_frames)


## A match's build: every chunk the still world calls for is built now, so none of them is built in
## a played frame. Nothing while merging is off.
func build_all() -> void:
	if not enabled:
		return
	merge_now()
	# a new watch is told of its mesh's place at the next flush: told and judged here, so that look
	# at every member is the build's cost, not the first frame's
	for member: MergeMember in _held.values():
		(member.watch as Node3D).force_update_transform()
	judge()


## Merge every waiting mesh that may join now, whatever its age (`build_all`, a test, a measure).
func merge_now() -> void:
	judge()
	_round.clear()
	_groups.clear()
	_next_round = 0
	_look(_waiting.size(), ANY_AGE)
	_look(0, ANY_AGE)
	while not _to_build.is_empty():
		_build(_to_build.pop_back())


## Whether a chunk draws `node` now (else it draws itself, or not at all).
func shows(node: Node) -> bool:
	var member: MergeMember = _held.get(node.get_instance_id())
	return member != null and member.in_chunk


## How many meshes the chunks hold (drawn by them or not).
func held() -> int:
	return _held.size()


## The chunks there are now.
func chunks() -> Array[MergeChunk]:
	return _chunks


## Every mesh draws itself again and every chunk goes.
func release() -> void:
	for member: MergeMember in _held.values():
		_let_go(member)
	for chunk in _chunks:
		chunk.free_instance()
	_chunks.clear()
	_held.clear()
	_waiting.clear()
	_dirty.clear()
	_round.clear()
	_groups.clear()
	_to_build.clear()


## Judge every held mesh that changed since the last call: out of its chunk, back into it, or gone.
func judge() -> void:
	if _dirty.is_empty():
		return
	var recast: Dictionary = {}
	var gone: Array[MergeMember] = []
	for key: int in _dirty:
		var member: MergeMember = _held.get(key)
		if member == null:
			continue
		if not member.in_place():
			gone.append(member)
		else:
			_swap(member, recast)
	_dirty.clear()
	for member in gone:
		_retire(member, recast)
	for chunk: MergeChunk in recast:
		chunk.recast()


## Show `member` (still where it was merged) by its chunk or by itself, as its look says.
func _swap(member: MergeMember, recast: Dictionary) -> void:
	var same := MergeMember.look_of(member.node) == member.look
	if same != member.in_chunk:
		member.in_chunk = same
		member.chunk.show_member(member, same)
	if not member.casts_as_merged():
		if not member.strayed:
			recast[member.chunk] = true
		member.strayed = true
	elif same and member.strayed:
		member.strayed = false
		recast[member.chunk] = true
	# the engine shows an instance again by itself whenever its node's visibility is set
	RenderingServer.instance_set_visible(
		member.node.get_instance(), not same and member.node.is_visible_in_tree()
	)


## `member` left its place for good (moved, or out of the tree): its chunk forgets it and, while it
## is still carried, it waits to join another once it rests.
func _retire(member: MergeMember, recast: Dictionary) -> void:
	var chunk := member.chunk
	if member.in_chunk:
		chunk.show_member(member, false)
	recast[chunk] = true
	_let_go(member)
	_held.erase(member.key)
	chunk.members.erase(member)
	if chunk.members.is_empty():
		chunk.free_instance()
		_chunks.erase(chunk)
		recast.erase(chunk)
	if is_instance_valid(member.node) and member.node.is_inside_tree():
		_wait(member.node, _frame + MirrorMergeConfig.settle_frames)


## `member`'s node is its own again: no watch, no hook, drawn as its visibility says.
func _let_go(member: MergeMember) -> void:
	if is_instance_valid(member.watch):
		member.watch.told = Callable()
		member.watch.queue_free()
	if not is_instance_valid(member.node):
		return
	member.node.remove_meta(MeshNodes.WATCHED)
	RenderingServer.instance_set_visible(
		member.node.get_instance(), member.node.is_visible_in_tree()
	)


## `node` waits to join a chunk from the frame `since`; one a chunk holds is left there.
func _wait(node: MeshInstance3D, since: int) -> void:
	if _held.has(node.get_instance_id()):
		return
	var member := MergeMember.new()
	member.node = node
	member.key = node.get_instance_id()
	member.since = since
	_waiting[member.key] = member


## Look at up to `most` of the waiting meshes of this round, `now` the frame they are as old as;
## a round that has looked at all of them hands its groups over to be built.
func _look(most: int, now: int) -> void:
	if _round.is_empty():
		if not _groups.is_empty():
			for key: Array in _groups:
				if _groups[key][0].size() >= MirrorMergeConfig.chunk_members:
					_to_build.append([key, _groups[key][0]])
			_groups = {}
			return
		if now < _next_round or _waiting.is_empty():
			return
		_round = _waiting.keys()
		_next_round = _frame + MirrorMergeConfig.round_frames
	for i in mini(most, _round.size()):
		_gather(_round.pop_back(), now)


## Put the waiting mesh `key` in the group of the chunk it would join, if it may join now.
func _gather(key: int, now: int) -> void:
	var member: MergeMember = _waiting.get(key)
	if member == null:
		return
	if not is_instance_valid(member.node):
		_waiting.erase(key)
		return
	if now < member.since:
		return
	if not MergeMember.joins(member.node):
		member.asked += 1
		if member.asked > MirrorMergeConfig.rounds:
			_waiting.erase(key)
		return
	var group := _group_of(member.node)
	if not _groups.has(group):
		_groups[group] = [[], 0]  # the members and their vertices
	var gathered: Array = _groups[group]
	gathered[0].append(member)
	gathered[1] += MergeSource.of(member.node.mesh).vertices.size()
	var most := (
		MirrorMergeConfig.chunk_vertices if now == ANY_AGE else MirrorMergeConfig.play_vertices
	)
	if gathered[1] >= most and gathered[0].size() >= MirrorMergeConfig.chunk_members:
		_to_build.append([group, gathered[0]])
		_groups.erase(group)


## What meshes of one chunk share: the world, the square of ground, the shadows they cast and the
## render layers they are on.
func _group_of(node: MeshInstance3D) -> Array:
	var middle := node.global_transform * node.get_aabb().get_center()
	var side := MirrorMergeConfig.cell * RenderConfig.unit
	return [
		node.get_world_3d().scenario,
		Vector2i(floori(middle.x / side), floori(middle.z / side)),
		node.cast_shadow,
		node.layers,
	]


## Build the chunk of `entry` (`[group, members]`) from those that still may join it.
func _build(entry: Array) -> void:
	var group: Array = entry[0]
	var joining: Array[MergeMember] = []
	for member: MergeMember in entry[1]:
		if (
			_waiting.get(member.key) == member and is_instance_valid(member.node)
			and MergeMember.suits(member.node) and MergeMember.joins(member.node)
			and _group_of(member.node) == group
		):
			joining.append(member)
	if joining.size() < MirrorMergeConfig.chunk_members:
		return
	for member in joining:
		member.kind = MergeMember.kind_of(member.node)
		member.at = member.node.global_transform
		member.layers = member.node.layers
		member.look = MergeMember.look_of(member.node)
		member.art = MeshNodes.shown_texture(member.node)
	var chunk := MergeChunk.make(joining, group[0], group[2], group[3])
	_chunks.append(chunk)
	for member in joining:
		member.chunk = chunk
		member.in_chunk = true
		member.strayed = false
		_waiting.erase(member.key)
		_held[member.key] = member
		_watch(member)
		RenderingServer.instance_set_visible(member.node.get_instance(), false)


## Hear of every change of `member`'s node.
func _watch(member: MergeMember) -> void:
	var told := _changed.bind(member.key)
	member.node.set_meta(MeshNodes.WATCHED, told)
	var watch := Watch.new()
	member.watch = watch
	member.node.add_child(watch, false, Node.INTERNAL_MODE_BACK)
	watch.told = told


## The held mesh `key` may differ from what its chunk copied.
func _changed(key: int) -> void:
	_dirty[key] = true


## A child of a held mesh: it says when the mesh moved, was shown or hidden, or left or entered
## the tree.
class Watch:
	extends Node3D

	var told := Callable()

	func _init() -> void:
		set_notify_transform(true)

	func _notification(what: int) -> void:
		if (
			what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED
			or what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_EXIT_TREE
		):
			if told.is_valid():
				told.call()
