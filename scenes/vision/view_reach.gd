extends RefCounted
## Vision domain: where the cone's rays can pass, and how far a blocker may be from where the job
## saw it and be where it was (`ViewWatch`; `docs/player-vision.md` V1, the cost rule). `now` is the
## sector of the job's pose (`ViewSector`: what "within reach" means for the world's change);
## `still` is `ViewWatch.STILL_PX`, or `VisionSliceConfig.settle_px` while a settling job is in
## flight.

const Sector := preload("res://scenes/vision/view_sector.gd")

## Where a ray of the job's pose can pass.
var now := Sector.new()
## How far (px) a blocker may be from the job's snapshot of it and be where it was.
var still := 0.0


func _init(bound: float) -> void:
	still = bound
