extends GameTest
## V9 (`docs/player-vision.md`): the viewer's death lifts the view, and everything is drawn again
## at once, live, for the rest of the match. In a world with the view on the human and in a world
## with the view on an NPC (the test builds the second beside the session's), the viewer is killed:
## within a frame the view's node, its composite and its viewports (capture, memory, mask) are
## gone, nothing the view drew is left in the world, and none comes back while the match goes on.
##
## The same holds where the viewer goes without dying (freed, or taken out of the tree: the view of
## a character that is not there cannot be kept, frozen over the world), and a character already
## dead has no view built at all (there is no view of the dead).
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` of the world (`viewer()`,
## `composite()`, `capture()`, `memory()`, `mask()`) and the nodes the world holds of the view's.

const Probe := preload("res://tests/_vision/vision_probe.gd")
## Frames the match goes on after the lift, to see that no view comes back.
const AFTERWARDS := 60


func describe() -> Dictionary:
	return {
		"name": "The viewer's death lifts the view",
		"description": "The human killed, and a viewed NPC killed: within a frame the view, its "
			+ "composite and its viewports are gone and nothing is left over the world, for good.",
		"tags": ["vision", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.actor(&"you", &"player", Vector2(150, 350))


func run(t: TestContext) -> void:
	await _lift(t, t.world, t.actor(&"you"), "the human")
	var world: Node2D = await Probe.build_world(t, _npc_view_setup())
	await _lift(t, world, world.actors[&"npc"], "the NPC")
	await _watch_the_dead(t, world, world.actors[&"npc"])
	await Probe.drop_world(t, world)
	for how in ["freed", "removed"]:
		world = await Probe.build_world(t, _npc_view_setup())
		await _leave(t, world, world.actors[&"npc"], how)
		await Probe.drop_world(t, world)


## The setup of a world, beside the session's, viewing an NPC.
func _npc_view_setup() -> TestSetup:
	var s := TestSetup.new()
	# Out of the way of the session's arena (the worlds share a navigation map).
	s.arena(Rect2(3000, 0, 1400, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.actor(&"npc", &"defender", Vector2(3150, 350))
	s.von_script([{ "pick": "investigate" }])
	s.view(&"npc")
	return s


## Take `viewer` out of `world` without killing it (`how`: "freed" or "removed"): the view of it is
## gone within a frame, with its composite and viewports, and none comes back.
func _leave(t: TestContext, world: Node, viewer: Node2D, how: String) -> void:
	var who := "the NPC %s" % how
	await t.frames(5)
	var views := Probe.views_under(world)
	if not t.require(views.size() == 1, "%s: premise: one view (%d)" % [who, views.size()]):
		return
	t.check(_left(world) >= 4, "%s: premise: the view's nodes are there (%d)" % [who, _left(world)])
	t.check(not viewer.is_dead, "%s: premise: the viewer is alive" % who)
	if how == "freed":
		viewer.queue_free()
	else:
		viewer.get_parent().remove_child(viewer)
	await t.frames(1)
	t.check(
		_left(world) == 0,
		"%s: the view's nodes are gone within a frame (%d left)" % [who, _left(world)],
	)
	await t.frames(AFTERWARDS)
	t.check(_left(world) == 0, "%s: no view comes back (%d left)" % [who, _left(world)])
	if is_instance_valid(viewer) and not viewer.is_inside_tree():
		viewer.free()


## `watch` of a character already dead builds no view and returns null.
func _watch_the_dead(t: TestContext, world: Node, dead: Node2D) -> void:
	t.check(dead.is_dead, "the dead: premise: the character is dead")
	t.check(Probe.views_under(world).is_empty(), "the dead: premise: no view is left")
	var view := PlayerView.watch(world, dead)
	t.check(view == null, "the dead: watch returns null")
	await t.frames(2)
	t.check(Probe.views_under(world).is_empty(), "the dead: no view is built")
	t.check(_left(world) == 0, "the dead: nothing of a view is in the world (%d)" % _left(world))


## Kill `viewer` in `world`, whose view is of it, and read what is left of the view.
func _lift(t: TestContext, world: Node, viewer: Node2D, who: String) -> void:
	await t.frames(5)
	var views := Probe.views_under(world)
	if not t.require(views.size() == 1, "%s: premise: one view (%d)" % [who, views.size()]):
		return
	t.check(views[0].viewer() == viewer, "%s: premise: the view is of the viewer" % who)
	t.check(_left(world) >= 4, "%s: premise: the view's nodes are there (%d)" % [who, _left(world)])
	viewer.take_damage(1000.0)
	await t.frames(1)
	t.check(viewer.is_dead, "%s: premise: the viewer is dead" % who)
	t.check(
		_left(world) == 0,
		"%s: the view's nodes are gone within a frame (%d left)" % [who, _left(world)],
	)
	t.check(Probe.views_under(world).is_empty(), "%s: no view is left in the world" % who)
	await t.frames(AFTERWARDS)
	t.check(_left(world) == 0, "%s: no view comes back (%d left)" % [who, _left(world)])


## How many nodes of the view the world holds: the view, its composite and its viewports.
func _left(world: Node) -> int:
	var count := world.find_children("*", "PlayerView", true, false).size()
	count += world.find_children("Composite", "", true, false).size()
	count += world.find_children("*", "SubViewport", true, false).size()
	return count
