extends CanvasLayer
## Fixture stand-in for the setup window (scenes/ui/menus/setup_menu.gd): the signal a click on Start emits.

signal start_requested(config: Dictionary)


func click(config: Dictionary) -> void:
	start_requested.emit(config)
