class_name CharacterDoorConfig
## How far a character reaches for a door (`character_doors.gd`, `docs/doors.md` DR6): a
## `class_name` holder of `static var`s, read as `CharacterDoorConfig.<name>`; there is no instance
## and no autoload. Distances are px.

## A door is in reach while its leaf has a point this near the body's centre (and ahead of it): a
## character beside a door at the edge of its collider is about 17 px from the leaf's middle line,
## and 48 px is a little under an arm and a half, the span of the vehicle's own door reach (60) less
## its handle's set-back.
static var reach: float = 48.0
