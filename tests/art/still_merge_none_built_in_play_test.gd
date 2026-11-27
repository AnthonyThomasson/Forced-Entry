extends GameTest
## In a real match (Main run whole, `tests/_main/main_probe.gd`: the setup window's Start of a
## watched district match) every chunk of the still world is built with the view. Hundreds of
## meshes sit on bodies still settling then (the items set down on pieces' tops fall and rest only
## later): they draw themselves for the whole match, and not one chunk is built after the view's
## (`domain-art/still-merge.md`). Scripted Von.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_still_merge_test.json"
const CONFIG := {
	"mode": "watch",
	"seed": 23,
	"defenders": { "count": 2 },
	"invaders": { "count": 2 },
}
## How long the match is watched after the view's build, past when the items have come to rest.
const WATCHED_S := 12.0
## The least meshes that were still settling at the build and rest by the end (587 here).
const SETTLED_LATE := 200


func describe() -> Dictionary:
	return {
		"name": "A match builds every merged chunk with its view, none in play",
		"description": "Main's watched district match: the chunks there are when the view is built "
			+ "are all there ever are, though hundreds of meshes only come to rest later.",
		"tags": ["mirror", "3d", "render", "match"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", Settings.debug)
	s.von_script([])


func run(t: TestContext) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var menu := MainProbe.setup_menu(main)
	if not t.require(menu != null, "premise: Main opened the setup window"):
		await MainProbe.close(t, viewport)
		return
	menu.start_requested.emit(CONFIG.duplicate(true))
	var lit := func() -> bool:
		var view := main.get_node_or_null("View3D") as CanvasLayer
		return view != null and view.lighting != null
	if t.require(await t.until(lit, 60.0), "the match is built and its view lit"):
		await _watch(t, main)
	await MainProbe.close(t, viewport)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## Watch the match on: the chunks stay those of the build.
func _watch(t: TestContext, main: Node) -> void:
	var view := main.get_node("View3D") as CanvasLayer
	var merge: StillMerge = view.carrier.merge
	var built := merge.chunks().duplicate()
	var held := merge.held()
	if not t.require(not built.is_empty(), "premise: the view built chunks"):
		return
	var settling := _settling(view, main)
	var added := [0]
	var count := func() -> bool:
		var new := merge.chunks().filter(func(c: MergeChunk) -> bool: return c not in built)
		added[0] = maxi(added[0], new.size())
		return false
	await t.until(count, WATCHED_S)
	var rested := settling.filter(
		func(pair: Array) -> bool:
			return is_instance_valid(pair[0]) and (pair[0] as RigidBody3D).sleeping
	)
	t.require(
		rested.size() >= SETTLED_LATE,
		"premise: meshes settling at the build rest now (%d of %d)" % [
			rested.size(),
			settling.size(),
		],
	)
	t.expect_eq(added[0], 0, "chunks built after the view's %d" % built.size())
	t.check(merge.held() <= held, "no mesh is taken after the build (%d)" % merge.held())


## `[twin, mesh]` of each carried mesh no chunk shows, on a rigid body that is awake.
func _settling(view: CanvasLayer, main: Node) -> Array:
	var out: Array = []
	var world := main.get_node("World") as Node2D
	for body: Node2D in TwinSpace.of_world(world).bodies():
		var twin := TwinSpace.twin_for(body) as RigidBody3D
		var carried: Node3D = view.carrier.mesh_of(body)
		if twin == null or twin.sleeping or carried == null:
			continue
		for mesh: Node in carried.find_children("*", "MeshInstance3D", true, false):
			if not view.carrier.merge.shows(mesh):
				out.append([twin, mesh])
	return out
