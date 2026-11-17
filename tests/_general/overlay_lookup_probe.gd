extends RefCounted
## Shared helper for the tests that look an NPC's overlay up the way the spectator's detail card
## does (not a test itself):
## `const Lookup := preload("res://tests/_general/overlay_lookup_probe.gd")`. The card reads
## `card_lines()` off the overlay it names, through `OverlayRegistry.overlay_of`.

const OverlayRegistry := preload("res://scenes/ui/overlays/overlay_registry.gd")


## `npc`'s overlay called `overlay_name`, found as the card finds it (null when it has none).
static func named(npc: Node, overlay_name: String) -> Node:
	return OverlayRegistry.overlay_of(npc, overlay_name)


## Whether `npc` has an overlay called `overlay_name` the card can read lines from.
static func found(npc: Node, overlay_name: String) -> bool:
	var overlay := OverlayRegistry.overlay_of(npc, overlay_name)
	return overlay != null and overlay.has_method(&"card_lines")
