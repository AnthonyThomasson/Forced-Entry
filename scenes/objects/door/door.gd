class_name Door
extends AnimatableBody2D
## A hinged door standing in a doorway (Objects domain, `docs/doors.md`). A driven body, not a
## physics hinge (`docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`): the code
## turns its leaf about the hinge and the engine moves the body kinematically, so a swing is exact
## and never knocked about by what leans on it. It publishes the door contract (architecture
## interface 24) and is hit, shoved and damaged through the hittable (3) and pushable (5)
## contracts. Drawn by `door_visuals.gd`; its parts are `look`, `damage`, `swing` and `push`. Its
## tuning is `DoorConfig`, `DoorPushConfig` and `DoorMaterialConfig`. It posts a `&"door"` event on
## the EventBus at each stage of its life (interface 10), which Audio voices (`docs/doors.md` DR12).
##
## Frame: the body's origin is the middle of the leaf and its x axis runs along the leaf from the
## hinge toward the latch, so `global_position` is where the leaf is (a blast reaches it there). The
## leaf is turned about a pivot `leaf_thickness / 2` toward `swing_into` off the hinge point,
## filling `[slack / 2, width - slack / 2]` along the shut leaf and one `leaf_thickness` of the side
## the door swings away from, so the shut leaf is centred on the wall line and, swung open, clears
## the jamb it is hinged on. Angles are degrees from shut.

## The door's state changed: a swing began or ended, it was hurt, its panes shattered, it fell.
signal changed

const DoorDamage = preload("res://scenes/objects/door/door_damage.gd")
const DoorLook = preload("res://scenes/objects/door/door_look.gd")
const DoorPush = preload("res://scenes/objects/door/door_push.gd")
const DoorSwing = preload("res://scenes/objects/door/door_swing.gd")
const DoorVisuals = preload("res://scenes/objects/door/door_visuals.gd")
const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## The hinge: a world point on the jamb the leaf turns about.
var hinge := Vector2.ZERO
## Unit vector from the doorway into the room the door swings into.
var swing_into := Vector2.DOWN
## How far the door opens (degrees from shut): where its leaf lies along the room's wall.
var open_angle := DoorConfig.open_angle
## The doorway's free width (px), hinge jamb to latch jamb: twice the hinge's distance from the
## doorway's centre.
var width := 0.0
## Its display name.
var object_name := "Door"
## What it is drawn as (`door_look.gd`), its hit points and latch (`door_damage.gd`), its swing
## (`door_swing.gd`), the turn a walker gives it (`door_push.gd`) and what draws it (`texture()`);
## built with it.
var look := DoorLook.new()
var damage: DoorDamage
var swing := DoorSwing.new()
var push := DoorPush.new()
var visuals: DoorVisuals
## The material's row of `DoorMaterialConfig.materials`.
var _row: Dictionary = {}
## Whether it has been knocked down.
var _down := false
## What a swing asks the physics space about before it turns there: the leaf's shape, a pixel
## slimmer all round (`DoorConfig.probe_inset`), so a leaf lying against a jamb or a wall it clears
## by a hair is not counted as in it (`_overlapping` sizes it for each query).
var _probe: RectangleShape2D
## Unit vector along the shut leaf, hinge to latch.
var _along := Vector2.RIGHT
## The game second the door last began opening, -INF before it has or once a closing swing has begun
## since: a swing opening it within `DoorConfig.latch_gap` of that carries on one movement (a run of
## scroll notches), which has sounded its latch already.
var _opened_at := -INF


func _ready() -> void:
	collision_layer = PhysicsLayers.SOLID
	collision_mask = 0
	var size := leaf_size()
	var col := CollisionShape2D.new()
	var leaf := RectangleShape2D.new()
	leaf.size = size
	col.shape = leaf
	_probe = RectangleShape2D.new()
	add_child(col)
	_build_occluder(size * 0.5)
	visuals = DoorVisuals.new()
	visuals.name = "DoorVisuals"
	visuals.setup(self, size)
	add_child(visuals)


## Turn the leaf on a step if it is swinging, or being pushed.
func _physics_process(delta: float) -> void:
	if not swing.moving():
		if push.moving():
			_pushed(delta)
		return
	if _blocked(swing.after(delta), delta, true):
		swing.halt()
		changed.emit()
		return
	swing.advance(delta)
	global_transform = leaf_pose(swing.angle)
	if not swing.moving():
		changed.emit()
		if is_zero_approx(swing.angle):
			_post(&"shut")


## Describe the door before it joins the tree. `opening` holds `pos` (the doorway's centre), `hinge`
## (the point on the jamb the leaf turns about, where the walls' ends stand: the leaf fills the
## doorway from there to the opposite jamb), `swing_into` (the unit vector into the room it swings
## into) and `angle` (the start angle in degrees, 0 = shut); `definition` is the catalogue's `name`,
## `material`, `style` and `color`.
func setup(opening: Dictionary, definition: Dictionary) -> void:
	hinge = opening["hinge"]
	width = 2.0 * (opening["pos"] as Vector2).distance_to(hinge)
	swing_into = (opening["swing_into"] as Vector2).normalized()
	_along = ((opening["pos"] as Vector2) - hinge).normalized()
	swing.turn = 1.0 if _along.rotated(PI / 2.0).dot(swing_into) > 0.0 else -1.0
	swing.angle = clampf(float(opening.get("angle", 0.0)), 0.0, open_angle)
	swing.target = swing.angle
	look.material = String(definition["material"])
	look.style = String(definition["style"])
	look.color = definition["color"]
	object_name = String(definition.get("name", object_name))
	_row = DoorMaterialConfig.materials[look.material]
	damage = DoorDamage.new(_row)
	add_to_group(&"doors")


## Put the body where the leaf stands (at its start angle), in the frame of `parent` it will be
## added under. Done before it joins the tree: a kinematic body is moved to the physics server's
## pose only as it enters, and set after, it keeps the pose it entered with until its next motion.
func place(parent: Node) -> void:
	var pose := leaf_pose(swing.angle)
	if parent is Node2D:
		position = (parent as Node2D).to_local(pose.origin)
		rotation = pose.get_rotation() - (parent as Node2D).global_rotation
	else:
		position = pose.origin
		rotation = pose.get_rotation()


## The leaf's size (px): its length along the doorway and its thickness.
func leaf_size() -> Vector2:
	return Vector2(width - DoorConfig.leaf_slack, DoorConfig.leaf_thickness)


## Where the leaf's middle stands, in the world, with the door `angle` degrees open (a transform:
## its origin the middle and its x axis along the leaf, hinge to latch).
func leaf_pose(angle_degrees: float) -> Transform2D:
	var turned := _along.angle() + swing.turn * deg_to_rad(angle_degrees)
	var pivot := _pivot()
	var middle := Vector2(width * 0.5, -swing.turn * DoorConfig.leaf_thickness * 0.5)
	return Transform2D(turned, pivot + middle.rotated(turned))


## The door's surface for a striker (interface 3): full cover, its material's penetration, the
## surface material it sounds as (a steel door's is wood's) and, for the glass-panel door,
## `transparent`: sight passes through it.
func get_surface() -> Dictionary:
	var surface := {
		"coverage": 100.0,
		"penetration": _row["penetration"],
		"material": _row.get("broken_sound", _row["sound"]) if look.broken else _row["sound"],
		"color": ObjectArt.drawn_color(look.color),
	}
	if look.material == "glass":
		surface["transparent"] = true
	return surface


## The surface a hit's chips and sparks are styled by: the door's own, unless its material has the
## debris look of another than it sounds as (steel sounds as wood but throws metal).
func _debris_surface() -> Dictionary:
	var surface := get_surface()
	if _row.has("debris"):
		surface["material"] = _row["debris"]
	return surface


## The leaf's angle now, degrees from shut.
func angle() -> float:
	return swing.angle


## How far open the leaf is, 0 (shut) to 1 (`open_angle`); a knocked-down door counts as wide open.
func open_amount() -> float:
	return 1.0 if _down else swing.angle / open_angle


## The width a character can pass through (px): the straight way from the leaf's free end to the
## latch jamb, never more than the doorway; the whole doorway once the door is down.
func gap() -> float:
	if _down:
		return width
	return minf(2.0 * width * sin(deg_to_rad(swing.angle) * 0.5), width)


## Use the door: an open door (or one swinging open) swings shut, a shut or ajar one swings fully
## open, in `DoorConfig.swing_time`. `by` is the character using it; a knocked-down door does
## nothing.
func toggle(_by: Node) -> void:
	_turn_to(0.0 if swing.target >= open_angle - 0.01 else open_angle)


## Turn the door by `degrees` (positive opens) from where it is heading, between shut and
## `open_angle`, and leave it there; each step is a share of the swing time. A knocked-down door
## does nothing.
func turn_by(degrees: float, _by: Node) -> void:
	_turn_to(swing.target + degrees)


## Swing the door fully open.
func open_fully(_by: Node) -> void:
	_turn_to(open_angle)


## Where to stand to work the latch from the side of the doorway `from` lies on: beside the latch
## jamb, out from the wall line (`DoorConfig.latch_spot_out`) and in from the jamb
## (`DoorConfig.latch_spot_in`).
func latch_side_spot(from: Vector2) -> Vector2:
	var middle := _doorway_middle()
	var side := 1.0 if (from - middle).dot(swing_into) >= 0.0 else -1.0
	return (
		hinge
		+ _along * (width - DoorConfig.latch_spot_in)
		+ swing_into * side * DoorConfig.latch_spot_out
	)


## Whether the leaf has been knocked down (0 HP): off its hinges and lying flat, the doorway clear.
func is_down() -> bool:
	return _down


## A round or a blast struck the leaf (hittable contract, interface 3): a dent or hole shows, debris
## flies, the glass-panel door's panes shatter, and the hit takes its material's factor of its
## damage off the hit points (a blast is a hit with no speed: `speed_factor` 0 and no height).
func take_hit(hit: HitInfo) -> void:
	if _down:
		return
	var kind := &"blast" if hit.speed_factor <= 0.0 and hit.height < 0.0 else &"round"
	visuals.deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, _debris_surface())
	if look.material == "glass":
		_shatter()
	_hurt(hit.damage, kind, hit.direction)


## A strike of `kind` (`&"punch"` or `&"kick"`, the melee strike's own name for itself) dealt
## `amount` while shoving along `impulse` (the character's melee, interface 3): the hit points drop
## by the material's factor for that kind, and a kick from the push side wears the latch.
func take_blow(kind: StringName, amount: float, impulse: Vector2) -> void:
	if _down:
		return
	_hurt(amount, &"kick" if kind == &"kick" else &"melee", impulse)


## Plain damage with no kind (a test's wound, the contract's `take_damage`): counted as a punch.
func take_damage(amount: float) -> void:
	take_blow(&"punch", amount, Vector2.ZERO)


## A shove (the pushable contract, interface 5). A shut door never moves for it, nor does a leaf a
## hand or a burst is swinging; an ajar or open one is turned about its hinge by the shove's moment
## against its weight, away from the body (`door.push`, `docs/doors.md` DR5, DR10). `at` is where
## it lands, from the leaf's middle.
func apply_impulse(impulse: Vector2, at := Vector2.ZERO) -> void:
	if _down or swing.moving() or swing.angle <= 0.0:
		return
	if not push.moving():
		push.began_at = swing.angle
	push.shove(impulse, global_position + at, _pivot(), swing.turn, float(_row["weight"]))


## The leaf's mass, read by a pusher.
func get_mass() -> float:
	return float(_row["weight"])


## A hit of `kind` dealing `strike` damage pushing along `direction`: the hit points drop by the
## material's factor for that kind of it. A kick or a blast from the push side (it pushes the way
## the door swings) throws an ajar door fully open at once, whatever its material: it is not
## latched. On a shut door it wears the latch by the strike itself (a boot cannot move a steel
## door's bolt), and when the latch gives the door bursts open.
func _hurt(strike: float, kind: StringName, direction: Vector2) -> void:
	push.note_blow()
	if damage.hurt(strike * damage.factor(kind)):
		_fall(direction)
		return
	changed.emit()
	if kind != &"kick" and kind != &"blast":
		return
	if direction.dot(swing_into) <= 0.0 or swing.target >= open_angle:
		return
	if swing.angle > 0.0 or (damage.wears_latch(kind) and damage.wear(strike)):
		_burst()


## The leaf comes off its hinges at 0 HP and falls flat into the room the last blow pushed it toward
## (`direction`; the room it swings into when the blow had none): it lies on the floor beyond the
## doorway with its length along the way it fell, walk-over (no collider), casting no shadow, in the
## doorway's way no more.
func _fall(direction: Vector2) -> void:
	_down = true
	swing.angle = open_angle
	swing.halt()
	push.stop()
	var toward := swing_into if direction.dot(swing_into) >= 0.0 else -swing_into
	var doorway := _doorway_middle()
	var lies := doorway + toward * (DoorConfig.fallen_length * 0.5 + DoorConfig.leaf_thickness)
	collision_layer = 0
	for child in get_children():
		if child is LightOccluder2D:
			child.queue_free()
	z_index = DrawLayers.LYING
	global_transform = Transform2D(toward.angle(), lies)
	visuals.fall(
		Vector2(DoorConfig.fallen_length, width),
		-_along.dot(toward.rotated(-PI / 2.0)) < 0.0,
	)
	changed.emit()
	_post(&"down")


## The leaf has been pushed on a step: it turns on if nothing solid, not even a character, stands
## where it will be (a pushed leaf nudges no one: it stops), and its friction slows it. Reaching
## shut it latches, and it is a shut door again.
func _pushed(delta: float) -> void:
	var to := push.after(swing.angle, delta, open_angle)
	if is_equal_approx(
		to,
		swing.angle,
	) or push.walker_shuts_open_leaf(swing.angle, open_angle) or _blocked(to, delta, false):
		push.stop()
	else:
		swing.rest_at(to)
		global_transform = leaf_pose(to)
		push.slow(delta)
		if to <= 0.0 or to >= open_angle:
			push.stop()
	if push.moving():
		return
	if not is_equal_approx(swing.angle, push.began_at):
		changed.emit()
	if is_zero_approx(swing.angle):
		_post(&"shut")


## Whether something stops the leaf turning to `to` degrees open this step: furniture, a wall or
## anything else solid in the way, or a character it cannot nudge clear. A character the leaf would
## sweep over is moved out of the way as the leaf comes (`_nudged`) when `nudging`, else it stops
## the leaf; so does a piece of furniture the leaf would touch.
func _blocked(to: float, delta: float, nudging: bool) -> bool:
	var pose := leaf_pose(to)
	for body in _overlapping(pose, DoorConfig.probe_inset):
		if not _is_character(body):
			return true
		if nudging and not _nudged(body as CharacterBody2D, pose, delta):
			return true
	if nudging:
		return false
	# a pushed leaf nudges no one: it comes to rest touching a character or a loose piece of
	# furniture in its way, which a slimmer probe would let it overlap ever so slightly, and the
	# engine would press aside, a shove a frame for as long as the walker pushes
	for body in _overlapping(pose, 0.0):
		if _is_character(body) or body is RigidBody2D:
			return true
	return false


## The solid bodies the leaf standing at `pose`, `inset` px slimmer all round, overlaps.
func _overlapping(pose: Transform2D, inset: float) -> Array:
	_probe.size = leaf_size() - Vector2.ONE * inset * 2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _probe
	query.transform = pose
	query.collision_mask = PhysicsLayers.SOLID
	query.exclude = [get_rid()]
	var bodies := []
	for found in get_world_2d().direct_space_state.intersect_shape(query, 8):
		bodies.append(found["collider"])
	return bodies


## Whether `body` is a living character (one the leaf may nudge).
func _is_character(body: Object) -> bool:
	return body is CharacterBody2D and (body as Node).is_in_group(&"characters")


## Move character `body` clear of the leaf standing at `pose`, straight away from it, by what it
## takes (no more than `DoorConfig.nudge_speed` allows this step). False when it cannot be moved
## that far: the leaf outruns the nudge, or a wall, a piece of furniture or another body stands in
## its way.
func _nudged(body: CharacterBody2D, pose: Transform2D, delta: float) -> bool:
	var half := leaf_size().x * 0.5
	var line_a := pose * Vector2(-half, 0.0)
	var line_b := pose * Vector2(half, 0.0)
	var near := Geometry2D.get_closest_point_to_segment(body.global_position, line_a, line_b)
	var away := body.global_position - near
	var clearance: float = float(body.get("radius")) + DoorConfig.leaf_thickness * 0.5 + 0.5
	var need := clearance - away.length()
	if need <= 0.0:
		return true
	if need > DoorConfig.nudge_speed * delta:
		return false
	var aside := (away.normalized() if away.length() > 0.001 else pose.y) * need
	var excepted := body.get_collision_exceptions().has(self)
	if not excepted:
		body.add_collision_exception_with(self)
	var free := not body.test_move(body.global_transform, aside)
	if free:
		body.move_and_collide(aside)
	if not excepted:
		body.remove_collision_exception_with(self)
	return free


## Swing toward `to` degrees (clamped to the door's range), taking the share of
## `DoorConfig.swing_time` the turn is of a full swing.
func _turn_to(to: float) -> void:
	if _down:
		return
	var goal := clampf(to, 0.0, open_angle)
	if is_equal_approx(goal, swing.target) and not swing.moving():
		return
	push.stop()
	var opens := goal > swing.angle
	var begins := opens and GameClock.seconds() - _opened_at >= DoorConfig.latch_gap
	_opened_at = GameClock.seconds() if opens else -INF
	swing.begin(goal, DoorConfig.swing_time * absf(goal - swing.angle) / open_angle)
	changed.emit()
	if begins:
		_post(&"open")


## The latch has given: the door is thrown fully open at `DoorConfig.burst_speed`.
func _burst() -> void:
	push.stop()
	swing.begin(open_angle, (open_angle - swing.angle) / DoorConfig.burst_speed, false)
	changed.emit()
	_post(&"burst")


## The glass-panel door's panes shatter: the frame stays, and the leaf is drawn without its glass.
func _shatter() -> void:
	if look.broken:
		return
	look.broken = true
	visuals.refresh()
	_post(&"glass")


## The point the leaf turns about: the hinge, half a leaf's thickness toward the room it swings
## into.
func _pivot() -> Vector2:
	return hinge + swing_into * DoorConfig.leaf_thickness * 0.5


## The middle of the doorway, on the wall line.
func _doorway_middle() -> Vector2:
	return hinge + _along * width * 0.5


## Announce a stage of the door's life (`open`, `shut`, `burst`, `down`, `glass`) on the EventBus,
## for Audio: where the doorway's middle is, the door and its material.
func _post(stage: StringName) -> void:
	EventBus.post(&"door", {
		"position": _doorway_middle(),
		"door": self,
		"material": look.material,
		"stage": stage,
	})


## The door's shadow: an occluder over the leaf (`half` its half size) in the body's frame, so it
## turns with the leaf, on the walls' bit (it shadows every light, overhead ones too). A glass-panel
## door casts none, and none while `LightMasks.shadows` is off.
func _build_occluder(half: Vector2) -> void:
	if look.material == "glass":
		return
	var occ := LightMasks.occluder(
		PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]),
		LightMasks.WALL,
	)
	if occ != null:
		add_child(occ)
