extends Node3D
## Test probe (not a test): a 3D node a domain's builder might hand the mirror, with the two
## optional hooks the mirror calls on it: `mirror_update(body)` every frame it is shown and
## `on_body_died(body)` when the body dies (true: stay shown and keep following).

## How many times `mirror_update` ran, and the body it was last given.
var calls := 0
var last_body: Node
## What `on_body_died` answers.
var survives_death := false


func mirror_update(body: Node2D) -> void:
	calls += 1
	last_body = body


func on_body_died(_body: Node2D) -> bool:
	return survives_death
