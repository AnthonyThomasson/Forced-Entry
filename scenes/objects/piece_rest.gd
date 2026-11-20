class_name PieceRest
extends RefCounted
## Objects domain, where a piece rests (#194 stack-a, D20, `docs/stacked-items.md`): how high it
## was put down (`ObjectFactory.spawn_on`) and whether it lies within a step. Held by
## `EnvironmentObject.rest`; its free body (`PieceBody`, `ItemBody`) reads and writes it.

## How high (px above the floor) the piece was set down: on another piece's top. Its free body
## starts there and settles; 0 is the floor.
var lift := 0.0
## Whether the piece lies no higher than a step (`DoorFallConfig.step_over`): a walker passes it and
## it is no hole in the nav bake. Written by `ItemBody`; false for every other piece.
var walk_over := false
