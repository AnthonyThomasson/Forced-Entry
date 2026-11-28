extends GameTest
## The follower hides what the player's view does not show, as the mirror did (#194,
## `MirrorSight`, `docs/player-vision.md` V5, V6 and V12), on a `MeshFollower` with a view on: a
## rifle lying where the cone and the bubble do not reach is hidden, one in the cone is shown; one
## seen stays shown where it lies once the cone moves on, one behind is shown when the viewer turns
## to it; a thing that moves is marked for the shaders (`MeshNodes.moving`), shown in the cone and
## hidden out of it. The viewer faces east along a hall.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(700, 350)
const BEHIND := Vector2(250, 350)
const AHEAD := Vector2(1100, 350)
const MOVER := &"follow_sight_mover"

var _follower: MeshFollower


func describe() -> Dictionary:
	return {
		"name": "The mesh follower hides what the view does not show",
		"description": "With a view on, a lying rifle behind the viewer is hidden and one ahead "
			+ "is shown; the one seen stays shown when the viewer turns away, the one behind is "
			+ "shown when it turns to it; a mover is marked moving, shown in the cone and "
			+ "hidden out of it.",
		"tags": ["mirror", "3d", "render", "vision", "follower"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	s.switch(&"vision.enabled", true)
	s.switch(&"nav.rebake", false)
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	if not t.require(
		await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "premise: the viewer faces east"
	):
		return
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_follower = MeshFollower.new()
	view.add_child(_follower)
	ItemMeshes.register(_follower)
	_follower.track_group(MOVER, func(_n: Node2D) -> Node3D: return Node3D.new())
	_follower.follow(t.world)
	var behind := _rifle(t, BEHIND)
	var ahead := _rifle(t, AHEAD)
	var mover := Node2D.new()
	mover.add_to_group(MOVER)
	t.world.add_child(mover)
	mover.global_position = AHEAD
	ViewLayers.set_moving(mover, true)
	if not ToonMask.mask_active():
		_mask_on()
	await t.until(func() -> bool: return _landed([behind, ahead]), 10.0)
	await t.frames(4)
	t.check(not Probe.reached_by(BEHIND), "premise: the cone and bubble do not reach behind")
	t.check(Probe.reached_by(AHEAD), "premise: the cone reaches ahead")
	if not t.require(
		_follower.mesh_of(behind) != null and _follower.mesh_of(ahead) != null,
		"premise: both rifles are shown by the follower",
	):
		return
	t.check(not _follower.mesh_of(behind).visible, "a rifle the view does not reach is hidden")
	t.check(_follower.mesh_of(ahead).visible, "a rifle in the cone is shown")
	await _check_mover(t, mover)
	await _check_remembered(t, behind, ahead)
	ToonMask.clear()


## A rifle lying at `at` (it is shown by the follower from the next frame).
func _rifle(t: TestContext, at: Vector2) -> Node2D:
	var rifle := DroppedItem.spawn(ItemRegistry.create(6), 0.0, Vector2.ZERO)
	rifle.place(t.world, at, at)
	return rifle


## Whether every rifle of `rifles` has landed (one in the air is a mover).
func _landed(rifles: Array) -> bool:
	return rifles.all(func(rifle: Node2D) -> bool: return not rifle.is_physics_processing())


func _mask_on() -> void:
	var white := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	ToonMask.set_mask(ImageTexture.create_from_image(white), Rect2(0, 0, 1400, 700), 0.0)


## A mover is marked moving for the shaders, shown in the cone and hidden when it is out of it.
func _check_mover(t: TestContext, mover: Node2D) -> void:
	var mesh := _follower.mesh_of(mover)
	if not t.require(mesh != null, "premise: the mover is shown by the follower"):
		return
	t.check(mesh.get_meta(&"moving", false), "a mover's mesh is marked moving")
	t.check(mesh.visible, "a mover in the cone is shown")
	mover.global_position = BEHIND
	await t.frames(2)
	t.check(not mesh.visible, "a mover out of the cone is hidden")
	ViewLayers.set_moving(mover, false)
	await t.frames(2)
	t.check(not mesh.get_meta(&"moving", false), "at rest it is not marked moving")


## The viewer turns west: the rifle behind is reached and shown; turned east again, both stay shown
## where they lie (remembered).
func _check_remembered(t: TestContext, behind: Node2D, ahead: Node2D) -> void:
	var eye := t.actor(&"eye")
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.LEFT), "premise: the viewer faces west")
	await t.frames(3)
	t.check(_follower.mesh_of(behind).visible, "the cone reaches the rifle behind: shown")
	t.check(_follower.mesh_of(ahead).visible, "the one seen before stays shown")
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "premise: the viewer faces east")
	await t.frames(3)
	t.check(not Probe.reached_by(BEHIND), "premise: behind is out of the cone again")
	t.check(_follower.mesh_of(behind).visible, "the rifle seen stays shown where it lies")
