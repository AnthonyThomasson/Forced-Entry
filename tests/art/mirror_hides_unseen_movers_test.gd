extends GameTest
## The 3D mirror shows what moves only where the player's view sees (#193 vision-mask, Art's
## `WorldMirror`, `docs/player-vision.md` V5, V6 and V12): a character the cone and the bubble do
## not reach is hidden as the 2D view hides it, and shown when it is in the cone; what is at rest
## (a thing on `ViewLayers.WORLD`: a corpse once its ragdoll sleeps, a parked car) is not hidden,
## it is remembered, and a piece of furniture is never hidden; a thing is hidden for the frames it
## moves again. With a view on, the mesh of a moving thing is marked for the shaders to cut it at
## the cone's edge (`MeshNodes.moving`). The viewer faces east along a hall; one puppet stands
## behind it, one ahead in the cone, a table lies behind.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(700, 350)
const BEHIND := Vector2(250, 350)
const AHEAD := Vector2(1100, 350)
const TABLE_AT := Vector2(300, 150)

var _mirror: WorldMirror


func describe() -> Dictionary:
	return {
		"name": "The 3D mirror hides a mover the view does not see, not what is at rest",
		"description": "A puppet behind the viewer is hidden, one in the cone shown; the one "
			+ "behind shows once it is at rest (WORLD) and is hidden again moving, and shows in "
			+ "the cone; a table behind is never hidden.",
		"tags": ["mirror", "3d", "render", "vision"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	s.set_static(GroundLayer, &"enabled", true)
	s.switch(&"vision.enabled", true)
	s.switch(&"nav.rebake", false)
	s.actor(&"eye", &"puppet", EYE_AT)
	s.actor(&"behind", &"puppet", BEHIND)
	s.actor(&"ahead", &"puppet", AHEAD)
	s.object(&"table", "coffee_table", TABLE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	if not t.require(
		await Probe.place(t, eye, EYE_AT, Vector2.RIGHT),
		"premise: the viewer faces east",
	):
		return
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_mirror = WorldMirror.new()
	view.add_child(_mirror)
	_mirror.mirror(t.world)
	await t.frames(4)
	var behind := _shown_of(t.actor(&"behind"))
	var ahead := _shown_of(t.actor(&"ahead"))
	if not t.require(behind != null and ahead != null, "premise: both are mirrored"):
		return
	t.check(not Probe.reached_by(BEHIND)[0], "premise: the cone and bubble do not reach behind")
	t.check(Probe.reached_by(AHEAD)[0], "premise: the cone reaches ahead")
	t.check(ahead.visible, "a mover in the cone is shown")
	t.check(not behind.visible, "a mover the view does not reach is hidden")
	_table_is_never_hidden(t)
	await _rest_and_move(t, behind)
	await _walks_in(t, behind)


## The table behind the viewer: furniture is remembered, never hidden.
func _table_is_never_hidden(t: TestContext) -> void:
	var table := _shown_of(t.object(&"table"))
	if t.require(table != null, "premise: the table is mirrored"):
		t.check(table.visible, "a piece of furniture behind the viewer is shown")


## At rest (WORLD) the thing behind is shown; moving again it is hidden again.
func _rest_and_move(t: TestContext, behind: Node3D) -> void:
	var body := t.actor(&"behind") as CanvasItem
	ViewLayers.set_moving(body, false)
	await t.frames(2)
	t.check(behind.visible, "a thing at rest is remembered, not hidden")
	ViewLayers.set_moving(body, true)
	await t.frames(2)
	t.check(not behind.visible, "and hidden again the frames it moves")


## It walks into the cone: shown.
func _walks_in(t: TestContext, behind: Node3D) -> void:
	t.actor(&"behind").global_position = AHEAD + Vector2(0, 40)
	await t.frames(3)
	t.check(behind.visible, "a mover that comes into the cone is shown")


## The one mesh `body` is shown by (null: the test ends).
func _shown_of(body: Node) -> Node3D:
	var found := _mirror.proxies_of(body)
	return null if found.is_empty() else found[0]
