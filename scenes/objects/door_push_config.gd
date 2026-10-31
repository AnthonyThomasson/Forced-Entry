class_name DoorPushConfig
## How an ajar or open door turns for a body walking into it (Objects domain, scenes/objects/door/;
## `docs/doors.md` DR5, DR10). The shove the walker already gives it turns the leaf about its hinge
## by the shove's moment against the leaf's weight (`DoorMaterialConfig` `weight`: steel turns
## slowest), and a hinge's friction stops it soon after. A `class_name` holder of `static var`s,
## read as `DoorPushConfig.<name>`; there is no instance and no autoload.

## What a unit of the leaf's weight resists a moment of a shove with: a shove's moment about the
## hinge (px x impulse) over `weight x resistance` is the degrees a second it adds to the leaf's
## turn. A walker's shove (about 900 a frame) at 30 px from the hinge turns a hollow door
## (weight 30) at about 95 degrees a second once the friction has taken its share.
static var resistance: float = 60.0
## The rate (per second) at which a hinge's friction takes the turn down: the spin decays as
## exp(-friction x seconds), no spring-back, so the leaf stops soon after the pusher.
static var friction: float = 10.0
## Degrees a second below which a pushed leaf has stopped.
static var rest_speed: float = 1.0
