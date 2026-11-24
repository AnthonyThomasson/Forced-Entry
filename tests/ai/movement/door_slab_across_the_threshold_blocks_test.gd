extends GameTest
## D18 / D14 (#194 doors3d, `docs/doors.md` DR11, DR14): a door that fell and rests leaning across
## its doorway (propped on a wardrobe close beyond it) is an obstacle like a tipped piece, and the
## AI's read of the door agrees with the nav map's and the body's: `gap()` is what the slab leaves
## of the doorway (not the whole width), the nav map has no way through, a walker sent past it
## never touches it, and the door state the AI's kept walks are made at changes when the slab
## comes to rest elsewhere (`SnapshotLeadMemo.door_state`).

const Probe := preload("res://tests/_ai/investigate_probe.gd")
const PieceProbe := preload("res://tests/_objects/piece_probe.gd")
const SnapshotLeadMemo := preload(
	"res://scenes/ai/perception/snapshot/snapshot_lead_memo.gd"
)
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
const WARDROBE_AT := Vector2(440, 300)
const KICK_IMPULSE := 4000.0
const WEST := Vector2(300, 300)
## Where the gunfire is heard: beyond the doorway.
const GUNFIRE := Vector2(620, 300)
## A character's body radius (px), the spec's number (DR14).
const BODY_RADIUS := 14.0
const WAIT := 12.0


func describe() -> Dictionary:
	return {
		"name": "A door leaning across its doorway blocks the AI as it blocks the nav map",
		"description": "A fallen door propped across the threshold leaves a gap below a body's "
			+ "width, the nav map has no way through it, and a defender sent to gunfire beyond "
			+ "it never touches it; the AI's door state changes as the slab moves.",
		"tags": ["ai", "movement", "door", "navigation", "3d", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 600) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 600) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "felled", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"nav.rebake", true)
	s.von_script([{ "pick": "investigate" }])
	s.actor(&"npc", &"defender", WEST, { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var door = t.object(&"felled")
	var standing: int = SnapshotLeadMemo.door_state(t.world.get_tree())
	door.take_blow(&"kick", 1000.0, Vector2.RIGHT * KICK_IMPULSE, 40.0)
	t.require(door.is_down(), "premise: the door is felled")
	t.require(await PieceProbe.settle(t, door, WAIT), "premise: it comes to rest")
	t.require(
		PieceProbe.top(door) > DoorFallConfig.step_over,
		"premise: it rests leaning (top %.1f px)" % PieceProbe.top(door),
	)
	await t.frames(2)
	t.check(
		door.gap() < 2.0 * BODY_RADIUS,
		"its gap is what the slab leaves, too little for a body (%.1f of %.0f px)"
			% [door.gap(), door.width],
	)
	var propped: int = SnapshotLeadMemo.door_state(t.world.get_tree())
	t.check(propped != standing, "the AI's door state changed when it fell")
	await _nav_agrees(t)
	await _walker_keeps_off(t, door)
	await _state_follows_the_slab(t, door, propped)


## The nav map, re-baked, has no way from the west room to the east one: the slab is a hole
## across the doorway.
func _nav_agrees(t: TestContext) -> void:
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	var through := func() -> bool:
		var path := NavPlan.path(map, WEST, GUNFIRE)
		return path.is_empty() or path[path.size() - 1].distance_to(GUNFIRE) > 20.0
	t.check(await t.until(through, WAIT), "the nav map has no way through the doorway")


## A defender sent to the gunfire beyond the doorway is not walked into the slab.
func _walker_keeps_off(t: TestContext, door: Node2D) -> void:
	var npc := t.actor(&"npc")
	Probe.gunfire(GUNFIRE)
	var closest := INF
	var waited := 0.0
	while waited < 8.0:
		await t.seconds(0.1)
		waited += 0.1
		closest = minf(closest, _to_ring(door.fallen_footprint(), npc.global_position))
	t.check(
		closest > BODY_RADIUS,
		"the defender never touched the slab (closest %.1f px)" % closest,
	)


## The slab shoved clear of the doorway: the AI's door state changes again, and the gap reads
## what the slab leaves then.
func _state_follows_the_slab(t: TestContext, door: Node2D, before: int) -> void:
	var gap: float = door.gap()
	Knockback.push(door, Vector2(0.0, 60_000.0), Vector2.ZERO, 3.0)
	await t.seconds(0.5)
	t.check(await PieceProbe.settle(t, door, WAIT), "the slab comes to rest after the shove")
	await t.frames(2)
	t.check(door.gap() != gap, "its gap changed with it (%.1f -> %.1f px)" % [gap, door.gap()])
	t.check(
		SnapshotLeadMemo.door_state(t.world.get_tree()) != before,
		"and the AI's door state with it",
	)


## How far `p` is from the ring `ring` (a polygon): 0 inside it, INF with none.
static func _to_ring(ring: PackedVector2Array, p: Vector2) -> float:
	if ring.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(p, ring):
		return 0.0
	var best := INF
	for i in ring.size():
		var on := Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()])
		best = minf(best, p.distance_to(on))
	return best
