class_name GunArt extends ItemArt
## Items domain: how a gun is drawn, a `GunItem`'s `art` part: its row's look in its weapon style
## (`GunConfig.look`: the painter and colours) at its row's sizes (`art_size`, `flat_size`,
## `grip_back`), held at the weapon hand, raised off a wall or lying on the floor. It holds the
## gun's row id and its item's `strike` (a sibling part, so a punch turns the drawn gun as the
## blow does), never the item.

## How far the pulled-up barrel shortens at full raise (fraction of its length): pointed up, a
## top-down view sees it foreshortened, so the held mesh is pitched (`held_lift`) by the angle whose
## cosine is that length.
const RAISED_LENGTH := 0.42

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


## The gun's 3D mesh in the hand (`GunMesh`): the silhouette of its held art, stood up.
func held_mesh() -> Mesh:
	var drawn := look()
	return GunMesh.held(gun, drawn, _look_handle(drawn))


## The held art the mesh wears: the painter's unlit render, projected straight down.
func held_texture() -> Texture2D:
	var drawn := look()
	return GunMesh.held_texture(gun, drawn, _look_handle(drawn))


## Where the held art lies in the mesh's frame.
func held_rect() -> Rect2:
	return GunMesh.held_rect(gun)


## The gun lying on its side: the silhouette of its flat (side-profile) art, `flipped` the side up.
func dropped_mesh(flipped := false) -> Mesh:
	var drawn := look()
	return GunMesh.lying(gun, drawn, _look_handle(drawn), flipped)


## The flat art of the gun lying on its side, the side up that `flipped` says.
func dropped_texture(flipped := false) -> Texture2D:
	var drawn := look()
	return GunMesh.lying_texture(gun, drawn, _look_handle(drawn), flipped)


## Where the lying art lies in the lying mesh's frame.
func dropped_rect() -> Rect2:
	return GunMesh.lying_rect(gun)


## The direction the gun points: the weapon's facing, turned about the
## grip by a punch (a long gun swung butt first).
func held_aim(user: Object) -> Vector2:
	return strike.direction(user.weapon.facing(), user.anatomy.hands.punch_amount(strike.hand))


## How far a gun held up off a wall is pitched: a barrel pointing up is seen from above shortened to
## `RAISED_LENGTH` at full raise, so the pitch is the angle whose cosine is that length.
func held_lift(user: Object) -> float:
	return acos(lerpf(1.0, RAISED_LENGTH, clampf(float(user.weapon.raise()), 0.0, 1.0)))
