extends Node
## A solid thing for a test: it holds `coverage` as a property and counts the times it is asked for
## its whole surface (`get_surface`), the read a cover test need not make (not a test itself).

## How well it hides someone (0 to 100).
var coverage := 0.0
## Times `get_surface` was called.
var surface_calls := 0


## What a bullet or a cover test reads of it.
func get_surface() -> Dictionary:
	surface_calls += 1
	return { "coverage": coverage, "penetration": 0.0, "material": "", "color": Color.WHITE }
