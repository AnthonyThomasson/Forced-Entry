class_name ItemArt extends RefCounted
## Items domain: how a held item is drawn and in which weapon style, the item's `art` part, which
## the character's visuals call every frame it is drawn (`draw_weapon`), a `DroppedItem` or a
## `ThrownGrenade` while it lies or flies (`draw_dropped`) and the registry once it is made
## (`prepaint`). Built once with its item (`Item._init`) and never replaced: this base is the inert
## default (fists, unarmed, key, magazine: nothing drawn), and a kind that is drawn hands up its own
## (`GunArt`, `GrenadeArt`, `SpoonArt`). It holds no reference to its item.

## The weapon style it is drawn in, its wielder's (`police` issue for the invaders, `scrap` or
## `pipe` for a defender): stamped on every item a loadout makes (`ItemRegistry.inventory_for`, from
## `LoadoutConfig.apply`). An item never given one is `police`. A gun or grenade draws its config
## row's look for it (`GunConfig.look` / `GrenadeConfig.look`); a dropped gun and a thrown grenade
## keep it. Looks only: nothing the item does depends on it.
var style: StringName = &"police"
## The textures the last frame's draws of the item painted, in order (`drawn_art`).
var _art: Array[Texture2D] = []
## The process frame `_art` was painted in.
var _art_frame := -1
## The look last drawn (a config `looks` row) and its painters' handle, so it is hashed once.
var _look_row := {}
## The painters' handle of `_look_row`.
var _look_id := 0


## The textures the item's last draw (`draw_weapon` or `draw_dropped`, every call in the frame it
## was last drawn: a lying item's shadow and art) painted, in order. Pixel art is cached by what it
## depicts, so the same drawing gives the same textures and a changed look new ones. Empty for an
## item never drawn or that draws nothing.
func drawn_art() -> Array:
	return _art.duplicate()


## Record `tex` as painted by this frame's draw of the item (`drawn_art`).
func _note_drawn(tex: Texture2D) -> void:
	var frame := Engine.get_process_frames()
	if frame != _art_frame:
		_art_frame = frame
		_art.clear()
	if not _art.has(tex):
		_art.append(tex)


## The painters' handle of `look` (a gun's or grenade's config `looks` row, `PixelArt.handle`),
## registered again only when the row drawn is another one (a new style, or a config row replaced).
func _look_handle(look: Dictionary) -> int:
	if not is_same(look, _look_row):
		_look_row = look
		_look_id = PixelArt.handle(look)
	return _look_id


## Paint ahead of time the art this item can be drawn with, so no first paint lands mid-fight
## (`ItemRegistry` asks every item it makes). Only fills PixelArt's cache with the textures the
## draws would paint: what is drawn never changes. Default: none.
func prepaint() -> void:
	pass


## Draw the item's weapon art onto `canvas` (the character's visuals Node2D), held by `user`.
## Default: none.
func draw_weapon(_canvas: CanvasItem, _user: Object) -> void:
	pass


## Draw the item lying loose, centered at `at` on `canvas` and pointing along `angle`, tinted by
## `modulate` (its art, or its shadow). `opts` is how it landed, picked once when dropped
## (`flip`: which side faces up). Default: none.
func draw_dropped(_canvas: CanvasItem, _at: Vector2, _angle: float, _modulate: Color = Color.WHITE,
		_opts: Dictionary = {}) -> void:
	pass
