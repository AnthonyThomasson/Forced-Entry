class_name StillMerge
extends Node
## Art domain, the still world drawn in merged chunks (interface 27, `domain-art/still-merge.md`):
## the carrier offers each still mesh it carries; `build_all`, as the view is built, copies those
## that may join into the chunk of their square of ground (`MergeChunk`) and leaves their own
## instances undrawn (only in the rendering server: the node, its `visible`, its layers and its
## parameters are as they were, so everything that reads or writes them goes on). No chunk is built
## after that, so none in a played frame: what was not taken then, or comes later, draws itself.
## The moment a held mesh's look or place differs from what was copied (the wall fade, a dent, a
## shove, a swing, hidden, freed) its vertices leave the chunk and it draws itself again, in the
## same frame, before the picture is drawn; when the look is the copied one again (a wall whole
## again) it returns; one that moved is let go for good. A change costs the one mesh's vertices.
## What tells of a change: a `Watch` child (moves, shown or hidden, in or out of the tree) and
## `MeshNodes.changed` (every write of a mesh's look).

## It judges after every script that writes a mesh has run.
const LAST := 1000

## Whether meshes are taken and built into chunks (off: those already merged stay until `release`).
var enabled := MirrorMergeConfig.enabled
## The meshes offered for the build and those a chunk holds, by node instance id.
var _offered: Dictionary = {}
var _held: Dictionary = {}
var _chunks: Array[MergeChunk] = []
## The held meshes to judge before the next picture.
var _dirty: Dictionary = {}
## Whether `build_all` has built: no mesh is taken from then until `release`.
var _built := false


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
	judge()


## Offer the meshes of `root` (a carried still mesh: it and every mesh under it) to the build.
## Nothing while merging is off or once built: a mesh made in play costs no look here.
func offer(root: Node) -> void:
	if not enabled or _built:
		return
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node: MeshInstance3D in meshes:
		_offered[node.get_instance_id()] = node


## The one build, made as a match's view is: every offered mesh that may join now goes into a
## chunk; the rest (a piece still settling, too few for a chunk) draw themselves. Nothing while
## merging is off.
func build_all() -> void:
	if not enabled:
		return
	judge()
	_built = true
	var groups: Dictionary = {}  # chunk key -> [members, vertex count]
	for node: Variant in _offered.values():
		if is_instance_valid(node) and MergeMember.suits(node) and MergeMember.joins(node):
			_gather(groups, node)
	for key: Array in groups:
		_build(key, groups[key][0])
	_offered.clear()
	# a new watch is told of its mesh's place at the next flush: told and judged here, so that look
	# at every member is the build's cost, not the first frame's
	for member: MergeMember in _held.values():
		(member.watch as Node3D).force_update_transform()
	judge()


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


## Every mesh draws itself again and every chunk goes; meshes may be offered and built anew.
func release() -> void:
	for member: MergeMember in _held.values():
		_let_go(member)
	for chunk in _chunks:
		chunk.free_instance()
	_chunks.clear()
	_held.clear()
	_offered.clear()
	_dirty.clear()
	_built = false


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


## `member` left its place for good (moved, other layers, or out of the tree): its chunk forgets it
## and it draws itself from now on.
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


## Put `node` in the group of `groups` it shares a chunk with, building a group that is full.
func _gather(groups: Dictionary, node: MeshInstance3D) -> void:
	var member := MergeMember.new()
	member.node = node
	member.key = node.get_instance_id()
	var key := _group_of(node)
	if not groups.has(key):
		var none: Array[MergeMember] = []
		groups[key] = [none, 0]
	var group: Array = groups[key]
	group[0].append(member)
	group[1] += MergeSource.of(node.mesh).vertices.size()
	if (
		group[1] >= MirrorMergeConfig.chunk_vertices
		and group[0].size() >= MirrorMergeConfig.chunk_members
	):
		_build(key, group[0])
		groups.erase(key)


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


## Build the chunk of `members`, which share `group` (`_group_of`), unless they are too few.
func _build(group: Array, members: Array[MergeMember]) -> void:
	if members.size() < MirrorMergeConfig.chunk_members:
		return
	for member in members:
		member.kind = MergeMember.kind_of(member.node)
		member.at = member.node.global_transform
		member.layers = member.node.layers
		member.look = MergeMember.look_of(member.node)
		member.art = MeshNodes.shown_texture(member.node)
	var chunk := MergeChunk.make(members, group[0], group[2], group[3])
	_chunks.append(chunk)
	for member in members:
		member.chunk = chunk
		member.in_chunk = true
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
