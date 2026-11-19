class_name Door
extends AnimatableBody2D
## A hinged door standing in a doorway (Objects domain, `docs/doors.md`). A driven body, not a
## physics hinge (`docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`): the code
## turns its leaf about the hinge, so a swing is exact and never knocked about by what leans on it.
## The leaf is led in 3D (#194 doors3d, D13): its truth is a `DoorBody` in the twin space (an
## `AnimatableBody3D` locked upright, `TwinSpace`, interface 29) that the swing turns, and this 2D
## body is its follower, written from it in the same step (`_drive`). Knocked down (0 HP) the leaf
## comes off its hinges as a free `DoorSlab` (D18, `docs/doors.md` DR11) that falls and lies as
## physics decides, this body its footprint. It publishes the door contract (architecture
## interface 24) and is hit, shoved and damaged through the hittable (3) and pushable (5)
## contracts. Shown by the 3D render (`door_mesh.gd`); its parts are `look`, `damage`, `swing` and
## `push`. Its tuning is `DoorConfig`, `DoorPushConfig` and `DoorMaterialConfig`. It posts a
## `&"door"` event on the EventBus at each stage of its life (interface 10), which Audio voices
## (`docs/doors.md` DR12).
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
const DoorFootprint = preload("res://scenes/objects/door/door_footprint.gd")
const DoorLook = preload("res://scenes/objects/door/door_look.gd")
const DoorPush = preload("res://scenes/objects/door/door_push.gd")
const DoorSwing = preload("res://scenes/objects/door/door_swing.gd")
const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
## The most bodies a swing's query reads at once.
const OVERLAP_HITS := 32

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
## (`door_swing.gd`) and the turn a walker gives it (`door_push.gd`);
## built with it.
var look := DoorLook.new()
var damage: DoorDamage
var swing := DoorSwing.new()
var push := DoorPush.new()
## The dents and holes its hits recorded (a child; stored in the leaf's frame,
## `DoorConfig.dent_depth` deep, up to `DoorConfig.dents`).
var deformable: Deformable
## The material's row of `DoorMaterialConfig.materials`.
var _row: Dictionary = {}
## Whether it has been knocked down.
var _down := false
## What a swing asks the twin space about before it turns there: the leaf's box, a pixel slimmer
## all round (`DoorConfig.probe_inset`), so a leaf lying against a jamb or a wall it clears by a
## hair is not counted as in it (`_overlapping` sizes it for each query).
var _probe := BoxShape3D.new()
## Unit vector along the shut leaf, hinge to latch.
var _along := Vector2.RIGHT
## The game second the door last began opening, -INF before it has or once a closing swing has begun
## since: a swing opening it within `DoorConfig.latch_gap` of that carries on one movement (a run of
## scroll notches), which has sounded its latch already.
var _opened_at := -INF


func _ready() -> void:
	collision_layer = PhysicsLayers.SOLID
	collision_mask = 0
	# the follower of its 3D leader, written in the step the leader is turned: the body is at the
	# pose written at once (a body synced to the physics step reads its old pose until the next)
	sync_to_physics = false
	var size := leaf_size()
	var col := CollisionShape2D.new()
	var leaf := RectangleShape2D.new()
	leaf.size = size
	col.shape = leaf
	col.name = DoorFootprint.COLLIDER
	add_child(col)
	deformable = Deformable.new()
	deformable.max_depth = DoorConfig.dent_depth
	deformable.allow_chunks = false
	deformable.max_impacts = DoorConfig.dents
	add_child(deformable)
	set_physics_process(swing.moving() or push.moving())


## Turn the leaf on a step if it is swinging, or being pushed.
func _physics_process(delta: float) -> void:
	if not swing.moving():
		if push.moving():
			_pushed(delta)
		if not push.moving():
			set_physics_process(false)
		return
	if _blocked(swing.after(delta), delta, true):
		swing.halt()
		set_physics_process(false)
		changed.emit()
		return
	swing.advance(delta)
	_drive(leaf_pose(swing.angle))
	if not swing.moving():
		set_physics_process(false)
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


## The door's surface for a striker (interface 3): its material's penetration, the
## surface material it sounds as (a steel door's is wood's) and, for the glass-panel door,
## `transparent`: sight passes through it.
func get_surface() -> Dictionary:
	var surface := {
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
## latch jamb, never more than the doorway; once the door is down what its fallen leaf leaves of the
## doorway (all of it when it lies flat or elsewhere, `DoorFootprint.clear_width`).
func gap() -> float:
	if _down:
		var middle := _doorway_middle()
		var half := _along * width * 0.5
		return DoorFootprint.clear_width(self, middle - half, middle + half)
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


## Whether the leaf has been knocked down (0 HP): off its hinges, a free body lying where it fell
## (`fallen_footprint()`), the doorway clear.
func is_down() -> bool:
	return _down


## A round or a blast struck the leaf (hittable contract, interface 3): a dent or hole shows, debris
## flies, the glass-panel door's panes shatter, and the hit takes its material's factor of its
## damage off the hit points (a blast is a hit with no speed: `speed_factor` 0 and no height; its
## shove is the grenade's, given by the pusher). A round that fells it throws the leaf by its own
## impulse at the height it struck. A door already down is a free body: a round throws debris and
## shoves it as a light piece (`Knockback.push`) at the height it struck, and costs it nothing.
func take_hit(hit: HitInfo) -> void:
	if _down:
		Physics.spawn_debris(get_parent(), hit, _debris_surface())
		if TwinSpace.leader_of(self) != null:
			Knockback.push(
				self,
				Physics.impact_impulse(hit),
				hit.position - global_position,
				hit.height,
			)
		return
	var kind := &"blast" if hit.speed_factor <= 0.0 and hit.height < 0.0 else &"round"
	deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, _debris_surface())
	if look.material == "glass":
		_shatter()
	_hurt(hit.damage, kind, hit.direction, Physics.impact_impulse(hit), hit.height)


## A strike of `kind` (`&"punch"` or `&"kick"`, the melee strike's own name for itself) dealt
## `amount` while shoving along `impulse` at `height` px up (the character's melee, interface 3; -1:
## no height known): the hit points drop by the material's factor for that kind, and a kick from the
## push side wears the latch. A blow that fells the leaf throws it by that shove, at that height (a
## kick's, at the lock: the leaf's middle).
func take_blow(kind: StringName, amount: float, impulse: Vector2, height := -1.0) -> void:
	if _down:
		return
	var kicked := kind == &"kick"
	# a breaching kick is aimed at the lock, at the leaf's middle: a foot's resting height (knee
	# high) would kick the leaf's foot out from under it and tip it back onto the kicker
	_hurt(amount, &"kick" if kicked else &"melee", impulse, impulse, -1.0 if kicked else height)


## Plain damage with no kind (a test's wound, the contract's `take_damage`): counted as a punch.
func take_damage(amount: float) -> void:
	take_blow(&"punch", amount, Vector2.ZERO)


## A shove (the pushable contract, interface 5). A shut door never moves for it, nor does a leaf a
## hand or a burst is swinging; an ajar or open one is turned about its hinge by the shove's moment
## against its weight, away from the body (`door.push`, `docs/doors.md` DR5, DR10). `at` is where
## it lands, from the leaf's middle.
func apply_impulse(impulse: Vector2, at := Vector2.ZERO) -> void:
	if _down:
		# the free body that is the leaf now (a door with no twin space has none to push)
		if TwinSpace.leader_of(self) != null:
			Knockback.push(self, impulse, at)
		return
	if swing.moving() or swing.angle <= 0.0:
		return
	if not push.moving():
		push.began_at = swing.angle
	push.shove(impulse, global_position + at, _pivot(), swing.turn, float(_row["weight"]))
	if push.moving():
		set_physics_process(true)


## The leaf's mass, read by a pusher.
func get_mass() -> float:
	return float(_row["weight"])


## A hit of `kind` dealing `strike` damage pushing along `direction`: the hit points drop by the
## material's factor for that kind of it. A kick or a blast from the push side (it pushes the way
## the door swings) throws an ajar door fully open at once, whatever its material: it is not
## latched. On a shut door it wears the latch by the strike itself (a boot cannot move a steel
## door's bolt), and when the latch gives the door bursts open.
func _hurt(
	strike: float,
	kind: StringName,
	direction: Vector2,
	shove := Vector2.ZERO,
	height := -1.0,
) -> void:
	push.note_blow()
	if damage.hurt(strike * damage.factor(kind)):
		_fall(direction, shove, height)
		return
	changed.emit()
	if kind != &"kick" and kind != &"blast":
		return
	if direction.dot(swing_into) <= 0.0 or swing.target >= open_angle:
		return
	if swing.angle > 0.0 or (damage.wears_latch(kind) and damage.wear(strike)):
		_burst()


## The leaf comes off its hinges at 0 HP (D18, `docs/doors.md` DR11): its leader is replaced by a
## free body that stands where the leaf stood (`TwinSpace.retwin`, a `DoorSlab`), thrown by the blow
## that felled it (`shove`, plan space, at `height` px up; a blast's is given by its pusher next)
## and wrenched over across its face the way the blow came (`direction`; the room it swings into
## when the blow had none), and it falls and lies as physics decides. This body is its footprint
## from then: solid while the leaf stands or leans higher than a step, no collider once it lies
## flat, and in the doorway's way no more. It is unusable, and the doorway counts as clear (`gap`).
func _fall(direction: Vector2, shove: Vector2, height: float) -> void:
	_down = true
	set_physics_process(false)
	swing.angle = open_angle
	swing.halt()
	push.stop()
	var across := global_transform.y.normalized()
	var side := signf(direction.dot(across))
	if is_zero_approx(side):
		side = signf(across.dot(swing_into))
	TwinSpace.retwin(self)
	var slab := TwinSpace.twin_for(self) as DoorSlab
	if slab != null:
		slab.release(shove, height, across * (side if side != 0.0 else 1.0))
	else:
		collision_layer = 0  # no twin space to fall in: out of the way
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
		_drive(leaf_pose(to))
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
		# (a vehicle is no `RigidBody2D` now, but the footprint of a free 3D body, as a piece
		# is: it is as loose as one)
		if _is_character(body) or body is RigidBody2D or TwinSpace.leader_of(body) != null:
			return true
	return false


## The solid bodies the leaf standing at `pose`, `inset` px slimmer all round, overlaps: their 2D
## bodies, each once, by where they stand (the order the engine reports them in is not stable
## run to run), found with the leaf's box in the twin space, so a tipped piece or a door lying on
## its side is where it really is. None in a world with no twin space.
func _overlapping(pose: Transform2D, inset: float) -> Array:
	var space := TwinSpace.space_of(self)
	var own := TwinSpace.twin_for(self) as CollisionObject3D
	if space == null or own == null:
		return []
	var size := leaf_size()
	var height := ObjectStructureMeshConfig.door_height
	_probe.size = Vector3(size.x, height, size.y) * RenderConfig.unit - Vector3.ONE * inset * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = PlanSpace.lift_transform(pose, height * 0.5)
	query.collision_mask = (
		PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_VEHICLE | PhysicsLayers.TWIN_CHARACTER
	)
	query.exclude = [own.get_rid()]
	var bodies := []
	for found in space.intersect_shape(query, OVERLAP_HITS):
		var body := TwinSpace.owner_of(found["collider"])
		if body != null and body != self and not bodies.has(body):
			bodies.append(body)
	bodies.sort_custom(_nearer_the_origin)
	return bodies


## Bodies in a fixed order: by where they stand.
static func _nearer_the_origin(a: Node2D, b: Node2D) -> bool:
	if a.global_position.x != b.global_position.x:
		return a.global_position.x < b.global_position.x
	return a.global_position.y < b.global_position.y


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
	var walker := TwinSpace.walker_of(body)
	var leaf := TwinSpace.twin_for(self) as PhysicsBody3D
	return walker != null and leaf != null and walker.call(&"shift", aside, leaf)


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
	set_physics_process(true)
	changed.emit()
	if begins:
		_post(&"open")


## The latch has given: the door is thrown fully open at `DoorConfig.burst_speed`.
func _burst() -> void:
	push.stop()
	swing.begin(open_angle, (open_angle - swing.angle) / DoorConfig.burst_speed, false)
	set_physics_process(true)
	changed.emit()
	_post(&"burst")


## The glass-panel door's panes shatter: the frame stays, and the leaf is shown without its glass.
func _shatter() -> void:
	if look.broken:
		return
	look.broken = true
	_post(&"glass")


## Move the leaf to `pose` (the world transform of its middle): its 3D leader is turned and this
## body written from it (`DoorBody.drive`). With no twin space the body is moved directly.
func _drive(pose: Transform2D) -> void:
	var leader := TwinSpace.twin_for(self) as DoorBody
	if leader != null:
		leader.drive(pose)
	else:
		global_transform = pose


## The footprint of a fallen leaf that is an obstacle (a ring in the world, from its collider), or
## empty when the leaf stands, is gone, or lies flat to be walked over: what a nav bake carves
## (interface 9, 24).
func fallen_footprint() -> PackedVector2Array:
	return DoorFootprint.ring(self) if _down else PackedVector2Array()


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
