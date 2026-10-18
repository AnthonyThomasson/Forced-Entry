extends Node
## Fixture worker: plays a match a few physics frames long, then emits `pinged` (wired to Main only in main.tscn).

signal pinged


func start(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
	pinged.emit()


## A match that never ends (a stalemate seed), near real time, so a run can be capped or killed mid-match.
func stall() -> void:
	while true:
		OS.delay_msec(10)
		await get_tree().physics_frame
