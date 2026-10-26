extends RefCounted
## The composition root's debug overlays, a part Main builds once and holds as `_overlays`: every
## overlay's on/off state, the performance overlay and the toggle bar it builds under Main, and the
## routing of a toggle (the performance overlay, the spectator inspector, or the match by the match
## builder's one rule). Built with its Main, it holds it (a node, so no reference cycle) to add the
## bar and the performance overlay and to connect the bar to `main.set_overlay`.

## The overlay table (UI) and the in-game bar of toggle buttons built from it.
const OVERLAY_REGISTRY := preload("res://scenes/ui/overlays/overlay_registry.gd")
const OVERLAY_TOGGLES := preload("res://scenes/ui/overlays/overlay_toggles.gd")
## The performance overlay (docks left of the toggle bar).
const PERFORMANCE_OVERLAY := preload("res://scenes/ui/overlays/performance_overlay.gd")

## The Main it belongs to.
var main: Node
## Every debug overlay's on/off state, `{ show_<x>: bool }` keyed like `overlay_registry.gd`.
var flags: Dictionary = {}
## The performance overlay (the one global overlay that isn't the match's); null when Debug is off.
var perf: CanvasLayer = null
## The overlay toggle bar (built once, kept across an endless run's matches); null when Debug is
## off.
var toggles: Node = null
## The spectator inspector (spectator mode only), told of live toggles so the selected NPC follows
## them.
var inspector: Node = null


func _init(owner: Node) -> void:
	main = owner


## Seed `flags`, the overlays' starting state: each registry default, overridden by the player's
## saved toggles (`Settings.overlays`); with Debug off (`debug`) every overlay starts off.
func initial(debug: bool) -> void:
	flags = OVERLAY_REGISTRY.defaults()
	for flag in Settings.overlays:  # the player's last toggles win over the defaults
		if flags.has(flag):
			flags[flag] = Settings.overlays[flag]
	if not debug:
		for flag in flags:
			flags[flag] = false


## The performance overlay and the toggle bar, built under Main the first time a match starts with
## Debug on (`debug`) and kept for the rest of an endless run.
func build(debug: bool) -> void:
	if not debug or is_instance_valid(toggles):
		return
	perf = PERFORMANCE_OVERLAY.new()
	perf.name = "PerformanceOverlay"
	main.add_child(perf)
	perf.set_shown(flags.get(OVERLAY_REGISTRY.PERF, false))
	var bar := OVERLAY_TOGGLES.new()
	bar.name = "OverlayToggles"
	main.add_child(bar)
	bar.setup(flags)
	bar.overlay_toggled.connect(main.set_overlay)
	toggles = bar


## Apply the overlay `flag` live: the performance flag to the performance overlay; in spectator mode
## an NPC's own overlay to the inspector (it shows overlays on the selected NPC only); the rest to
## the match `handle` by the one rule (`MatchBuilder.set_overlay`): the navigation holes and the
## squad leaders to the match's single overlays, and in player mode an NPC's own overlay to every
## NPC.
func route(flag: String, on: bool, handle: Dictionary) -> void:
	if flag == OVERLAY_REGISTRY.PERF:
		if is_instance_valid(perf):
			perf.set_shown(on)
	elif (inspector != null and is_instance_valid(inspector)
			and not OVERLAY_REGISTRY.is_global(flag)):
		inspector.set_flag(flag, on)
	else:
		MatchBuilder.set_overlay(handle, flag, on)
