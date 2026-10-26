extends RefCounted
## The composition root's endless run, a data leaf Main builds once and holds as `_endless`: whether
## the run is on, the spec the next match is drawn from, the highest counts it may draw and the
## countdown to the next match. It holds no owner; Main writes the HUD line and plays the match.

## On while the setup window's Endless button chose it.
var on: bool = false
## The spec of the match the setup window or the endless run last started (Main's `_play`:
## `MatchBuilder.spec`, its seed resolved), which the endless run draws the next one from.
var spec: Dictionary = {}
## The highest defender / invader counts a random match may draw (the counts chosen in setup).
var most := { "defenders": 1, "invaders": 1 }
## Seconds left until the next match (-1 while a match is being played).
var next_match_in: float = -1.0


## Tick the countdown by `delta`: false at once while none runs, or while the next match is still
## to come; true on the frame it is due (the countdown is then stopped).
func tick(delta: float) -> bool:
	if next_match_in < 0.0:
		return false
	next_match_in -= delta
	if next_match_in > 0.0:
		return false
	next_match_in = -1.0
	return true


## The match ended: in an endless run, start the countdown of `delay` seconds to the next one.
func ended(delay: float) -> void:
	if on:
		next_match_in = delay
