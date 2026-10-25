class_name DroppedItemConfig
## How an item let go into the world moves (Items domain, `dropped_item.gd`): its fall, bounce,
## skid, spin and glance off walls, its size against them and its shadow. A `class_name` holder of
## `static var`s, read as `DroppedItemConfig.<name>`, like the other config holders, so a test or
## tool can change them (tests restore them with `set_static`).

## Fall acceleration (px/s²), as a falling body's.
static var gravity: float = 610.0
## Height it is let go from (px): about hand height.
static var start_height: float = 50.0
## Share of its fall speed each bounce keeps.
static var bounce: float = 0.35
## Skid deceleration on the floor (px/s²).
static var friction: float = 520.0
## Share of its speed kept glancing off a wall.
static var wall_bounce: float = 0.45
## Spin deceleration on the floor (rad/s²).
static var spin_friction: float = 14.0
## Its size against walls (px).
static var radius: float = 3.0
## Shadow shift per px of height.
static var shadow_per_height: float = 0.06
