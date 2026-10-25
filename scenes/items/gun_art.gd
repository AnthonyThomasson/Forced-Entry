class_name GunArt extends ItemArt
## Items domain: how a gun is drawn, a `GunItem`'s `art` part: its row's look in its weapon style
## (`GunConfig.look`: the painter and colours) at its row's sizes (`art_size`, `flat_size`,
## `grip_back`), held at the weapon hand, raised off a wall or lying on the floor. It holds the
## gun's row id and its item's `strike` (a sibling part, so a punch turns the drawn gun as the
## blow does), never the item.

## How far the pulled-up barrel shortens at full raise (fraction of its length): pointed up, a
## top-down view sees it foreshortened. The art is re-rendered at `RAISE_STEPS` lengths between full
## and this, so it stays crisp and cached.
const RAISED_LENGTH := 0.42
const RAISE_STEPS := 5

## The guns and styles whose art `prepaint` has painted: [gun, style] -> true.
static var _prepainted := {}

## The gun's id: its `GunConfig` row.
var gun: StringName = &""
## The item's melee geometry (`ItemStrike`): the weapon hand, and how a blow turns the gun.
var strike: ItemStrike


func _init(id: StringName, melee: ItemStrike) -> void:
	gun = id
	strike = melee


## How it is drawn: its row's look in its weapon style (`GunConfig.look`: `painter`, colours,
## `finish`).
func look() -> Dictionary:
	return GunConfig.look(gun, style)


## Draw the gun's pixel art at the weapon hand, its butt behind the hand and the muzzle along the
## character's weapon.facing() (trailing the aim a touch as it turns): lit for the nearest lighting
## step, drawn rotated to the exact angle. Raised off a wall, the barrel foreshortens about the
## hand.
func draw_weapon(canvas: CanvasItem, user: Object) -> void:
	var facing: Vector2 = user.weapon.facing()
	# A punch turns a long gun about its grip until the butt leads.
	facing = strike.direction(facing, user.anatomy.hands.punch_amount(strike.hand))
	var step := clampi(roundi(float(user.weapon.raise()) * RAISE_STEPS), 0, RAISE_STEPS)
	var shrink := lerpf(1.0, RAISED_LENGTH, float(step) / RAISE_STEPS)
	var art_size := _art_size()
	var size := Vector2(art_size.x, maxf(roundf(art_size.y * shrink), 4.0))
	var centre: Vector2 = (user.anatomy.hands.hand_position(strike.hand)
			+ facing * (size.y * 0.5 - _grip_back() * shrink))
	_draw_art(canvas, centre, facing, size)


## The gun lying flat on its side, centered at `at`, its muzzle along `angle`, in its look's painter
## lying (`flat`); `opts.flip` picks the side facing up.
func draw_dropped(canvas: CanvasItem, at: Vector2, angle: float, modulate: Color = Color.WHITE,
		opts: Dictionary = {}) -> void:
	var turn := angle - PI * 0.5
	var size := _flat_size()
	var flip: bool = opts.get("flip", false)
	var drawn := look()
	var tex := PixelArt.render_turned(
		drawn["painter"], size, drawn["body"], PixelArt.snap_angle(turn),
		{
			"gun": gun, "look": _look_handle(drawn), "flat": true, "flip": flip,
			"material": drawn["finish"],
		},
	)
	_note_drawn(tex)
	canvas.draw_set_transform(at, turn, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Paint this gun's art ahead of time, once per gun and style: held at every raise step
## (`draw_weapon`) and lying on the floor either side up (`draw_dropped`), each at every lighting
## step. A gun turns, is raised off walls and skids from a dead hand through those, and each first
## paint (0.3 to 0.5 ms) would land in the busiest frames of a fight. The same calls the draws make,
## so the same cached textures: what is drawn never changes.
func prepaint() -> void:
	var key := [gun, style]
	if _prepainted.has(key):
		return
	_prepainted[key] = true
	var drawn := look()
	var handle := _look_handle(drawn)
	var art_size := _art_size()
	var step := TAU / maxi(1, ArtCanvasConfig.turn_steps)
	for k in ArtCanvasConfig.turn_steps:
		var angle := PixelArt.snap_angle(k * step)
		for raise in RAISE_STEPS + 1:
			var shrink := lerpf(1.0, RAISED_LENGTH, float(raise) / RAISE_STEPS)
			var size := Vector2(art_size.x, maxf(roundf(art_size.y * shrink), 4.0))
			PixelArt.render_turned(
				drawn["painter"],
				size,
				drawn["body"],
				angle,
				{ "gun": gun, "look": handle, "material": drawn["finish"] },
			)
		for flip in [false, true]:
			PixelArt.render_turned(
				drawn["painter"], _flat_size(), drawn["body"], angle,
				{
					"gun": gun, "look": handle, "flat": true, "flip": flip,
					"material": drawn["finish"],
				},
			)


## The held art's footprint (px): width across, length from butt to muzzle (the row's
## `art_size`).
func _art_size() -> Vector2:
	return GunConfig.row(gun).get("art_size", Vector2.ZERO)


## The flat art's footprint (px): its profile across, its length along (the row's `flat_size`).
func _flat_size() -> Vector2:
	return GunConfig.row(gun).get("flat_size", Vector2.ZERO)


## How far the butt end sits behind the weapon hand's center (px; the row's `grip_back`).
func _grip_back() -> float:
	return float(GunConfig.row(gun).get("grip_back", 0.0))


## The held art of `size` centered at `centre`, muzzle along `facing`, in its look's painter: lit
## for the nearest lighting step, drawn rotated to the exact angle.
func _draw_art(canvas: CanvasItem, centre: Vector2, facing: Vector2, size: Vector2) -> void:
	var angle := facing.angle() - PI * 0.5
	var drawn := look()
	var tex := PixelArt.render_turned(
		drawn["painter"], size, drawn["body"], PixelArt.snap_angle(angle),
		{ "gun": gun, "look": _look_handle(drawn), "material": drawn["finish"] },
	)
	_note_drawn(tex)
	canvas.draw_set_transform(centre, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
