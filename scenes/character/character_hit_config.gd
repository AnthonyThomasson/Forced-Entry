class_name CharacterHitConfig
## The body as a hittable (scenes/character/): its flesh surface (material, penetration, colour),
## its dents, the hit zones and their damage share, and the front / flank / back angles. A
## `class_name` holder of `static var`s, read as `CharacterHitConfig.<name>`; there is no instance
## and no autoload.

## Material tag handed to the debris system; selects the blood chip style + tint.
static var flesh_material: String = "flesh"
## (The body's coverage is its posture's: see `CharacterPostureConfig.postures`.)
## Resistance to being shot through, 0–100. Low: bullets tear through flesh.
static var flesh_penetration: float = 15.0
## Base color handed to debris styling; the "flesh" material re-tints chips blood-red, so
## this is only the color `get_surface()` reports.
static var flesh_color: Color = Color(0.85, 0.55, 0.5)
## Deepest a bullet dent may cave into the body silhouette (px). The central core keeps the
## deformed circle from folding, so this can be a large fraction of the body radius for
## pronounced dents without corrupting the polygon.
static var flesh_deform_max_depth: float = 9.0
## How many bullet dents the body remembers. Kept modest so dents from many angles don't
## saturate the small silhouette (recent hits replace old ones).
static var flesh_deform_max_impacts: int = 14
## Whether a hard hit carves a jagged "missing piece". Off for a small body: a chunk's reach
## would span the whole silhouette and fold it.
static var flesh_allow_chunks: bool = false
## `[zone, highest fraction]`, feet up; anything above the last row is the head.
static var zones: Array = [[&"feet", 0.08], [&"legs", 0.45], [&"torso", 0.85]]
## The share of a round's damage each zone takes (melee, through `take_damage`, is not zoned).
static var zone_damage: Dictionary = { &"feet": 0.6, &"legs": 0.6, &"torso": 1.0, &"head": 2.0 }
## The side a round strikes: the angle (degrees) between the way back to the shooter and the
## shoulders' facing. Up to `side_front_deg` is the front, from `side_back_deg` the back, the flank
## between.
static var side_front_deg: float = 60.0
## From this angle (degrees) on, the round strikes the back.
static var side_back_deg: float = 120.0
