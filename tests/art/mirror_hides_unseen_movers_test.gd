extends GameTest
## The 3D mirror shows what the player's view has seen, and what moves only where it sees now
## (#193 vision-mask, Art's `WorldMirror`, `docs/player-vision.md` V5, V6 and V12): a character the
## cone and the bubble do not reach is hidden as the 2D view hides it, and shown when it is in the
## cone; a corpse, a dropped item or a character at rest (a thing on `ViewLayers.WORLD`) that the
## cone has never reached is hidden too, and once it has been in the cone it stays shown where it
## lies, remembered, though the cone moves on; a thing is hidden again the frames it moves out of
## the cone; a thing seen that then moves out of view (a character walking off and dying, a car
## driving off and parking) is to be seen again where it comes to rest; a piece of furniture is
## never hidden. The viewer faces east along a hall; one puppet
## stands behind it, one ahead in the cone, a corpse and a dropped rifle lie behind, a table too.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(700, 350)
const BEHIND := Vector2(250, 350)
const AHEAD := Vector2(1100, 350)
const TABLE_AT := Vector2(300, 150)
const CORPSE_AT := Vector2(250, 550)
const RIFLE_AT := Vector2(400, 200)
const CAR_SEEN_AT := Vector2(1000, 250)
const CAR_PARKED_AT := Vector2(300, 500)

var _mirror: WorldMirror


func describe() -> Dictionary:
	return {
		"name": "The 3D mirror hides what the view has not seen and what moves out of it",
		"description": "A puppet, a corpse and a dropped rifle behind the viewer are hidden "
			+ "though at rest, a puppet in the cone is shown; once the cone has reached them they "
			+ "stay shown after it moves on (the puppet hidden again while it moves); a table "
			+ "behind is never hidden.",
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
	s.actor(&"corpse", &"puppet", CORPSE_AT)
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
	CharacterMeshes.register(_mirror.builders)
	ItemMeshes.register(_mirror)
	var corpse := t.actor(&"corpse")
	corpse.take_damage(1000.0)
	var rifle := DroppedItem.spawn(ItemRegistry.create(6), 0.0, Vector2.ZERO)
	rifle.place(t.world, RIFLE_AT, RIFLE_AT)
	_mirror.mirror(t.world)
	await t.frames(4)
	var behind := _shown_of(t.actor(&"behind"))
	var ahead := _shown_of(t.actor(&"ahead"))
	var dead := _shown_of(corpse)
	var lying := _shown_of(rifle)
	if not t.require(
		behind != null and ahead != null and dead != null and lying != null,
		"premise: all four are mirrored",
	):
		return
	t.check(not Probe.reached_by(BEHIND)[0], "premise: the cone and bubble do not reach behind")
	t.check(Probe.reached_by(AHEAD)[0], "premise: the cone reaches ahead")
	t.check(ahead.visible, "a mover in the cone is shown")
	t.check(not behind.visible, "a mover the view does not reach is hidden")
	_table_is_never_hidden(t)
	await t.until(
		func() -> bool: return (corpse.visibility_layer & ViewLayers.MOVING) == 0, 12.0
	)
	await t.until(func() -> bool: return not rifle.is_physics_processing(), 10.0)
	t.check(
		(corpse.visibility_layer & ViewLayers.MOVING) == 0 and corpse.is_dead,
		"premise: the corpse lies at rest (on WORLD)",
	)
	await _at_rest_unseen(t, behind, dead, lying)
	await _walks_in(t, behind)
	var car := await _car_seen_then_parked_out_of_view(t)
	await _leaves_and_dies(t, behind)
	await _looks_back(t, dead, lying, behind, car)
	await _remembered(t, dead, lying)


## The table behind the viewer: furniture is remembered, never hidden.
func _table_is_never_hidden(t: TestContext) -> void:
	var table := _shown_of(t.object(&"table"))
	if t.require(table != null, "premise: the table is mirrored"):
		t.check(table.visible, "a piece of furniture behind the viewer is shown")


## At rest (WORLD) and never in the cone, they are still hidden.
func _at_rest_unseen(t: TestContext, behind: Node3D, dead: Node3D, lying: Node3D) -> void:
	ViewLayers.set_moving(t.actor(&"behind") as CanvasItem, false)
	await t.frames(2)
	t.check(not behind.visible, "a character at rest the cone never reached is hidden")
	t.check(not dead.visible, "a corpse the cone never reached is hidden")
	t.check(not lying.visible, "a dropped rifle the cone never reached is hidden")
	ViewLayers.set_moving(t.actor(&"behind") as CanvasItem, true)


## It walks into the cone: shown.
func _walks_in(t: TestContext, behind: Node3D) -> void:
	t.actor(&"behind").global_position = AHEAD + Vector2(0, 40)
	await t.frames(3)
	t.check(behind.visible, "a mover that comes into the cone is shown")


## A car in the cone is seen; it drives out of view and parks there (it is on `WORLD` again):
## hidden, it must be reached again.
func _car_seen_then_parked_out_of_view(t: TestContext) -> Node3D:
	var car := AnimatableBody2D.new()
	car.add_to_group(&"vehicles")
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(60, 30)
	shape.shape = box
	car.add_child(shape)
	car.position = CAR_SEEN_AT
	t.world.add_child(car)
	ViewLayers.set_moving(car, true)
	await t.frames(3)
	var mesh := _shown_of(car)
	if not t.require(mesh != null, "premise: the car is mirrored"):
		return null
	t.check(mesh.visible, "a car in the cone is shown")
	car.global_position = CAR_PARKED_AT
	await t.frames(2)
	t.check(not mesh.visible, "driving out of view it is hidden")
	ViewLayers.set_moving(car, false)
	await t.frames(2)
	t.check(not mesh.visible, "parked out of view it stays hidden: it must be reached again")
	return mesh


## `behind`, seen in the cone, walks out of view and dies there: its corpse is hidden too.
func _leaves_and_dies(t: TestContext, behind: Node3D) -> void:
	var body := t.actor(&"behind")
	body.global_position = BEHIND
	await t.frames(3)
	t.check(not behind.visible, "a seen character who walks out of view is hidden")
	ViewLayers.set_moving(body as CanvasItem, false)
	await t.frames(2)
	t.check(not behind.visible, "at rest out of view it stays hidden")
	body.take_damage(1000.0)
	await t.frames(30)
	t.check(
		not behind.visible,
		"killed out of view, its corpse is hidden until the cone reaches it",
	)


## The viewer turns west: the cone reaches the corpse, the rifle, the car and the character that
## died.
func _looks_back(
	t: TestContext, dead: Node3D, lying: Node3D, died: Node3D, car: Node3D
) -> void:
	var eye := t.actor(&"eye")
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.LEFT), "premise: the viewer faces west")
	await t.frames(3)
	t.check(dead.visible, "the cone reaches the corpse: shown")
	t.check(lying.visible, "the cone reaches the rifle: shown")
	if car != null:
		t.check(car.visible, "the cone reaches the parked car: shown")
	t.check(died.visible, "and the character that died out of view")


## The viewer turns back east: what it has seen stays where it lies.
func _remembered(t: TestContext, dead: Node3D, lying: Node3D) -> void:
	var eye := t.actor(&"eye")
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "premise: the viewer faces east")
	await t.frames(3)
	t.check(not Probe.reached_by(CORPSE_AT)[0], "premise: the corpse is out of the cone again")
	t.check(dead.visible, "the corpse stays shown where it lies (remembered)")
	t.check(lying.visible, "and the rifle")


## The one mesh `body` is shown by (null: the test ends).
func _shown_of(body: Node) -> Node3D:
	var found := _mirror.proxies_of(body)
	return null if found.is_empty() else found[0]
