class_name ItemArt extends RefCounted
## Items domain: how an item looks and in which weapon style, the item's `art` part: the 3D mesh
## and flat art the character's body holds (`held_mesh`), a `DroppedItem` or a `ThrownGrenade` shows
## while it lies or flies (`dropped_mesh`), and the registry's warm-up once it is made (`prepaint`).
## Built once with its item (`Item._init`) and never replaced: this base is the inert default
## (fists, unarmed, key, magazine: nothing shown), and a kind that is shown hands up its own
## (`GunArt`, `GrenadeArt`, `SpoonArt`). It holds no reference to its item.

## The weapon style it is drawn in, its wielder's (`police` issue for the invaders, `scrap` or
## `pipe` for a defender): stamped on every item a loadout makes (`ItemRegistry.inventory_for`, from
## `LoadoutConfig.apply`). An item never given one is `police`. A gun or grenade draws its config
## row's look for it (`GunConfig.look` / `GrenadeConfig.look`); a dropped gun and a thrown grenade
## keep it. Looks only: nothing the item does depends on it.
var style: StringName = &"police"
## The look last shown (a config `looks` row) and its painters' handle, so it is hashed once.
var _look_row := {}
## The painters' handle of `_look_row`.
var _look_id := 0


## The painters' handle of `look` (a gun's or grenade's config `looks` row, `PixelArt.handle`),
## registered again only when the row drawn is another one (a new style, or a config row replaced).
func _look_handle(look: Dictionary) -> int:
	if not is_same(look, _look_row):
		_look_row = look
		_look_id = PixelArt.handle(look)
	return _look_id


## Make ahead of time what this item shows (`ItemRegistry` asks every item it makes): its held and
## loose meshes and flat art, which the mesh and the paint caches then hand out, so no first paint
## or build lands mid-fight. Fills the caches only: what is shown never changes. Nothing for an item
## that shows nothing.
func prepaint() -> void:
	held_mesh()
	held_texture()
	for flip in [false, true]:
		dropped_mesh(flip)
		dropped_texture(flip)


## The item's 3D mesh in a hand, for the 3D render (`GunMesh`, `GrenadeMesh`): shared by kind
## and look, its origin the weapon hand and its front along +z, sized and coloured from the config
## row the 2D art reads. Null: nothing is shown (the default: fists, unarmed, key, magazine). A
## character's body places it (`domain-character`, `body-mesh.md`); Items builds no node.
func held_mesh() -> Mesh:
	return null


## The flat 2D art the held mesh wears (`PixelArt.render_flat` of the item's painter, projected
## straight down onto it: `MeshNodes.textured`), and `held_rect` where it lies in the mesh's frame
## (px). Null: the mesh is plain (the default).
func held_texture() -> Texture2D:
	return null


## Where the held art lies in the held mesh's frame (px).
func held_rect() -> Rect2:
	return Rect2()


## The item's 3D mesh lying loose or in the air (`DroppedItem`, `ThrownGrenade`; `LyingItemMesh`):
## by default the held mesh itself. `flipped` is the side of a gun lying on its side that faces up
## (`DroppedItem.flipped`). Null: nothing is shown.
func dropped_mesh(_flipped := false) -> Mesh:
	return held_mesh()


## The flat art the loose mesh wears, and `dropped_rect` where it lies in the mesh's frame (px): by
## default the held art. Null: the mesh is plain.
func dropped_texture(_flipped := false) -> Texture2D:
	return held_texture()


## Where the loose art lies in the loose mesh's frame (px).
func dropped_rect() -> Rect2:
	return held_rect()


## The flat direction the held mesh points along, as the 2D art is drawn (a unit vector): the
## weapon's facing, or what a blow turns it to. Read each frame.
func held_aim(user: Object) -> Vector2:
	return user.weapon.facing()


## How far the held mesh is pitched up (radians) about the hand: a long gun held up off a wall,
## which the 2D art shows foreshortened. Zero by default.
func held_lift(_user: Object) -> float:
	return 0.0
