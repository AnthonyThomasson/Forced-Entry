class_name MirrorConfig
## Art domain, the 3D mirror (`world_mirror.gd`, interface 27): how a 2D body looks as a proxy in
## the 3D view until a domain's own mesh replaces it. A `class_name` holder of `static var`s, read
## as `MirrorConfig.<name>`. Heights are in 2D pixels, scaled by `RenderConfig.unit` with the
## ground, so changing the scale scales the world whole; height is visual only (the sim stays flat).

## How tall each kind of body stands: a wall (full height), a door's leaf, a character, a vehicle.
static var wall_height: float = 96.0
static var door_height: float = 84.0
static var character_height: float = 58.0
static var vehicle_height: float = 40.0
## A piece of furniture is its footprint's narrow side times this, clamped between its own least
## (never more than the footprint's narrow side, so a casing stays a speck) and most.
static var furniture_ratio: float = 0.7
static var furniture_min: float = 22.0
static var furniture_max: float = 70.0
## A floor is a flat slab this thick, sunk below the ground plane so it never fights what stands on
## it.
static var floor_thickness: float = 2.0
## The colour of a body that names none of its own (`art_color`, `color`): a floor, a door, a
## character with no faction, then the hue a name hashes to at this saturation and value.
static var floor_color: Color = Color(0.5, 0.45, 0.4)
static var door_color: Color = Color(0.55, 0.38, 0.24)
static var character_color: Color = Color(0.85, 0.45, 0.2)
static var hashed_saturation: float = 0.35
static var hashed_value: float = 0.7
