class_name GrenadeArt extends ItemArt
## Items domain: how a grenade is drawn, a `GrenadeItem`'s `art` part: its row's look in its weapon
## style (`GrenadeConfig.look`: the painter and colours) at its row's `art_size`, in the hand with
## the lever held down, or in the air and on the floor with the lever gone. It holds the grenade's
## row id and its weapon hand, never the item.

## The kinds and styles whose art `prepaint` has painted: [kind, style] -> true.
static var _prepainted := {}

## The kind's id: its `GrenadeConfig` row.
var kind: StringName = &""
## The hand that holds it (its item's `weapon_hand()`).
var hand := 0


func _init(id: StringName, weapon_hand: int) -> void:
	kind = id
	hand = weapon_hand


## How it is drawn: its row's look in its weapon style (`GrenadeConfig.look`: `painter`, colours,
## `finish`).
func look() -> Dictionary:
	return GrenadeConfig.look(kind, style)


## Draw the grenade in the hand, the lever still held down (in the look's lever colour): lit for the
## nearest lighting step, drawn rotated to the exact angle of the character's `weapon.facing()`.
func draw_weapon(canvas: CanvasItem, user: Object) -> void:
	var facing: Vector2 = user.weapon.facing()
	var size := _art_size()
	var angle := facing.angle() - PI * 0.5
	var tex := _texture(PixelArt.snap_angle(angle), true)
	var at: Vector2 = user.anatomy.hands.hand_position(hand)
	canvas.draw_set_transform(at + facing * 2.0, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The grenade in the air or on the floor (the lever gone), centered at `at` and pointing along
## `angle`.
func draw_dropped(canvas: CanvasItem, at: Vector2, angle: float, modulate: Color = Color.WHITE,
		_opts: Dictionary = {}) -> void:
	var turn := angle - PI * 0.5
	var size := _art_size()
	var tex := _texture(PixelArt.snap_angle(turn), false)
	canvas.draw_set_transform(at, turn, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Paint this grenade's art ahead of time, once per kind and style: at every lighting step, lever
## held (in the hand) and gone (in the air, on the floor), as `_texture` asks for it. The same
## cached textures: what is drawn never changes.
func prepaint() -> void:
	var key := [kind, style]
	if _prepainted.has(key):
		return
	_prepainted[key] = true
	var drawn := look()
	var step := TAU / maxi(1, ArtCanvasConfig.turn_steps)
	for k in ArtCanvasConfig.turn_steps:
		for spoon in [true, false]:
			PixelArt.render_turned(
				drawn["painter"], _art_size(), drawn["shell"], PixelArt.snap_angle(k * step),
				{
					"kind": kind, "look": _look_handle(drawn), "spoon": spoon,
					"material": drawn["finish"],
				},
			)


## The art's footprint (px): width across, length along (the row's `art_size`).
func _art_size() -> Vector2:
	return GrenadeConfig.row(kind).get("art_size", Vector2.ZERO)


## The grenade's art in its look, lit for the lighting step `angle`, with the lever held down
## (`spoon`) or gone.
func _texture(angle: float, spoon: bool) -> Texture2D:
	var drawn := look()
	var tex := PixelArt.render_turned(
		drawn["painter"], _art_size(), drawn["shell"], angle,
		{
			"kind": kind, "look": _look_handle(drawn), "spoon": spoon,
			"material": drawn["finish"],
		},
	)
	_note_drawn(tex)
	return tex
