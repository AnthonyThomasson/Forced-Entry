class_name WorldGenTowerConfig
## World Generation domain tuning: how a district's tower is dressed to read as tall
## (TowerDressing). A `class_name` holder of `static var`s, read as `WorldGenTowerConfig.<name>`;
## there is no instance and no autoload.

## The podium band's depth (px) past a tower's wall face.
static var podium_depth: float = 20.0
## The band is cut into segments at most `podium_segment` px long, none under `podium_min`.
static var podium_segment: float = 144.0
static var podium_min: float = 24.0
## The band stays this far (px) each side of an exterior doorway's width: room for the invaders'
## stack on that side, up to three bodies each about 44 px apart along the wall past the jamb, so a
## band beside the door never stands where a slot against the wall would be.
static var podium_door_gap: float = 150.0
## A tower's shadow is its footprint dragged this far (px) away from the light.
static var shadow_length: float = 170.0
## A tower's body for the street furniture is its podium band and this much more (px): the wall's
## face and a little room.
static var margin: float = 10.0
