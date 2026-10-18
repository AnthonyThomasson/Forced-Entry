extends Node
## Fixture autoload, registered after the probe: its _ready only counts if the probe is the first autoload.

var started := 0


func _ready() -> void:
	started += 1
