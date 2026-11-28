extends GameTest
## V1 cost (`docs/player-vision.md`): a cone job holds the shapes its region query hit across
## ticks (`ViewShapes.fold_corners` reads a chunk of them a tick later), so a twin freed between the
## query and its chunk is a freed instance. A glass-panel door's twin is looked through (no corner),
## and `TwinSpace.retwin` frees it when the door is knocked down (`Door._fall`): the job skips the
## freed hit as the whole rebuild of the world after the fall, which sees the new twin and looks
## through it too, would give no corner for it.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Cone := preload("res://scenes/vision/view_cone.gd")
const Job := preload("res://scenes/vision/view_cone_job.gd")
const EYE := Vector2(450, 250)
const FACING := Vector2.RIGHT
## The shove of the blow that fells the door (a kick's: `docs/doors.md` DR10).
const KICK_IMPULSE := 2200.0

var _sight := {
	"fov_degrees": Probe.FOV,
	"view_distance": Probe.REACH,
	"awareness_radius": Probe.BUBBLE,
	"eye_height": Probe.SEE_OVER,
}


func describe() -> Dictionary:
	return {
		"name": "A glass door felled between the corners' query and its chunk is skipped",
		"description": "A cone job whose region query hit a glass-panel door, the door knocked "
			+ "down (its twin freed and twinned again) before the hits are folded, finishes "
			+ "as the whole rebuild of the world after the fall and reads no freed instance.",
		"tags": ["vision", "door"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(Probe.ROOMS, [Probe.doorway(250.0, "glass", "panes", "pane")])
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var door: Node2D = t.object(&"pane")
	var space := Probe.space(t)
	var kept := VisionSliceConfig.cost_shape
	VisionSliceConfig.cost_shape = VisionSliceConfig.slice_units
	var cone := Cone.new()
	cone.begin(space, EYE, FACING, [], _sight)
	cone.step(VisionSliceConfig.slice_units)
	VisionSliceConfig.cost_shape = kept
	var job: Variant = cone.get("_job")
	t.require(job.stage == Job.Stage.HITS, "premise: the query is read, its hits are not folded")
	var twin := TwinSpace.twin_for(door)
	var held: Array = cone.get("_build").hits.filter(
		func(hit: Dictionary) -> bool: return hit["collider"] == twin
	)
	t.require(not held.is_empty(), "premise: the query hit the glass door's twin")
	t.require(SightRay.looks_through(twin), "premise: the glass door is looked through")
	door.take_blow(&"kick", 1_000_000.0, Vector2.LEFT * KICK_IMPULSE, 30.0)
	await t.frames(3)
	t.require(door.is_down(), "premise: the door is down")
	t.require(not is_instance_valid(twin), "premise: its old twin is freed")
	cone.step(1 << 60)
	var whole := Cone.new()
	whole.rebuild(space, EYE, FACING, [], _sight)
	t.check(not job.stage != Job.Stage.DONE, "the job finishes")
	var why := Probe.polygons_differ(cone.cone, cone.bubble, whole.cone, whole.bubble)
	t.check(why == "", "the job's cone is the whole rebuild's after the fall: %s" % why)
	t.check(cone.corners_read == whole.corners_read, "and it read the same corners")
