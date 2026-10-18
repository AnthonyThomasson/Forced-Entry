extends Node
## Raises one script error at a known line, so a run of the instrumented copy shows whether the lines the engine
## names still match the source.


func _ready() -> void:
	get_tree().quit.call_deferred()
	var nothing: Variant = null
	nothing.missing_method()
