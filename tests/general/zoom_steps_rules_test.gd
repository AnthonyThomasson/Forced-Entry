extends GameTest
## `ZoomSteps`, the 3D zoom's whole steps (#193 phase 2b), on the default steps 0.5, 1, 2 and 3 with
## a 15% hysteresis: the nearest step for an automatic zoom (a vehicle's), the largest step not over
## a fit, a step changed only once the automatic zoom is past the boundary by the margin (rising for
## a fit, both ways for the nearest), a fit falling at once, and the wheel's gathered fraction of a
## notch dropped by a pause. The expected steps are worked by hand: the nearest boundary between 0.5
## and 1 is sqrt(0.5) = 0.707, between 1 and 2 it is 1.414; a margin of 15% moves it to 0.615 and
## 0.813 going down and up from the middle one.


func describe() -> Dictionary:
	return {
		"name": "The 3D zoom's steps: nearest, fit, hysteresis, a paused trackpad scroll",
		"description": "ZoomSteps.snap picks the nearest step or the largest not over a fit, holds "
			+ "its step until the automatic zoom is 15% past a boundary (a fit falls at once), "
			+ "and wheel() forgets a gathered fraction after a pause.",
		"tags": ["camera", "zoom", "3d"],
		"timeout": 4.0,
	}


func configure(s: TestSetup) -> void:
	s.set_static(Zoom3dConfig, &"steps", PackedFloat32Array([0.5, 1.0, 2.0, 3.0]))
	s.set_static(Zoom3dConfig, &"hysteresis", 0.15)
	s.set_static(Zoom3dConfig, &"notch_idle", 0.3)


func run(t: TestContext) -> void:
	_nearest(t)
	_fit(t)
	_wheel_pause(t)


## The nearest step holds through a jitter across its boundary and moves once past the margin.
func _nearest(t: TestContext) -> void:
	var z := ZoomSteps.new()
	t.expect_eq(z.snap(1.0, false), 1.0, "the first reading takes its nearest step")
	for automatic: float in [0.72, 0.70, 0.72, 0.69, 0.71]:
		t.expect_eq(
			z.snap(automatic, false),
			1.0,
			"%s jitters at the boundary: 1 holds" % automatic,
		)
	t.expect_eq(z.snap(0.62, false), 1.0, "0.62 is not yet 15% past 0.707")
	t.expect_eq(z.snap(0.60, false), 0.5, "0.60 is: it falls to 0.5")
	for automatic: float in [0.70, 0.72, 0.69, 0.78, 0.80]:
		t.expect_eq(z.snap(automatic, false), 0.5, "%s jitters back up: 0.5 holds" % automatic)
	t.expect_eq(z.snap(0.84, false), 1.0, "0.84 is 15% past 0.707: it rises to 1")


## A fit takes the largest step not over it, rises only past the margin, and falls at once.
func _fit(t: TestContext) -> void:
	var z := ZoomSteps.new()
	t.expect_eq(z.snap(1.5, true), 1.0, "a fit of 1.5 shows 1")
	t.expect_eq(z.snap(2.1, true), 1.0, "2.1 is over 2 but not by the margin: still 1")
	t.expect_eq(z.snap(2.4, true), 2.0, "2.4 is: it rises to 2")
	t.expect_eq(
		z.snap(1.99, true),
		1.0,
		"a fit under its step falls at once, never leaving anyone off",
	)
	t.expect_eq(z.snap(0.3, true), 0.5, "under every step it is the smallest")


## A gathered fraction of a notch is kept for 0.3 s and no longer.
func _wheel_pause(t: TestContext) -> void:
	var z := ZoomSteps.new()
	z.wheel(0.6, 0)
	t.expect_eq(z.offset, 0, "0.6 of a notch is no step")
	z.wheel(0.6, 100)
	t.expect_eq(z.offset, 1, "0.6 again 0.1 s later is a step")
	var slow := ZoomSteps.new()
	slow.wheel(0.6, 0)
	slow.wheel(0.6, 1000)
	t.expect_eq(slow.offset, 0, "0.6 again a second later starts afresh: no step")
	slow.wheel(0.6, 1100)
	t.expect_eq(slow.offset, 1, "and the next one soon after finishes it")
