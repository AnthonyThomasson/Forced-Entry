extends CanvasLayer
## Fixture stand-in for the MatchHUD (scenes/ui/hud/match_hud.gd): the signal that tells Main a match is decided.

signal match_ended(verdict: String)


func finish(verdict: String) -> void:
	match_ended.emit(verdict)
