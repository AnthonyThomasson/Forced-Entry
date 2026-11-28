extends Node2D
## Physics System, blood: a dead body's bleed-out pool: a BloodFlow flood-fill claims grid cells in
## per-frame batches, wrapping around walls and furniture into one continuous irregular puddle, then
## a front eases outward through them over the bleed-out duration. Started by `seed_bleed_out` at
## the point the body's blood leaves it. Despawner-tracked. It owns the fill only; the 3D render
## shows it (`pool_ink.gd`, told by `PhysicsFxHook.pool_changed`).

## Flow cells all the pools still claiming may claim between them in one physics frame (each claim
## costs its neighbours' collider queries, about 0.12 ms in a district: a pool claiming 60 a frame
## held 5 to 8 ms for four frames the frame its body died). The pools share it evenly, the remainder
## (16 % n) going to the first pools in list order, one claim at least each: so the most a frame
## claims is max(16, n), and a crowd of deaths flows together, slower, and no frame holds a lump.
## The front sweeps while the cells are claimed (`BloodFlow.advance`), so a pool shows at once.
const FLOW_CLAIMS_PER_FRAME := 16

## The pools that still have cells to claim, in the order they started.
static var _claimers: Array[Node] = []
## The pools claiming at the first claim of physics frame `_round_frame`, by instance id: the shares
## of one frame are cut from this list, so a pool that finishes (and leaves `_claimers`) mid-frame
## does not widen the others' shares that same frame.
static var _round: PackedInt64Array = PackedInt64Array()
static var _round_frame := -1

## The flood-fill (the 3D pool shows its cells).
var flow: BloodFlow
## The cell budget the flow may claim (porous cells cost more), and the seconds its front takes to
## sweep them.
var _budget := 0.0
var _flow_duration := 1.0


func _exit_tree() -> void:
	_claimers.erase(self)


func _physics_process(delta: float) -> void:
	# Claim the cells a batch per frame (each costs a collider query) and sweep the front over the
	# ones claimed, which waits where it meets one not yet claimed.
	if _claiming():
		flow.step(_share(), TwinSpace.space_of(self), global_position, _budget)
	var claiming := _claiming()
	if not claiming:
		_claimers.erase(self)
	flow.advance(delta, _flow_duration, claiming)
	flow.tick(delta)
	PhysicsFxHook.pool_changed(self)
	if not claiming and flow.settled() and not flow.soaking():
		set_physics_process(false)


## Start the pool: `cells` grid cells flowing out from its origin and leaning a random way, filling
## in over `duration` seconds once claimed. `exclude` is the body's twin RID(s), which the flow
## ignores.
func seed_bleed_out(cells: int, duration: float, exclude: Array) -> void:
	flow = BloodFlow.new(Vector2.RIGHT.rotated(randf() * TAU), exclude)
	BloodField.add_pool(self)
	_budget = cells
	_claimers.append(self)
	_flow_duration = duration
	set_physics_process(true)


## How many pools are still claiming (a test reads it: it is empty once the world is freed).
static func claimer_count() -> int:
	return _claimers.size()


## The claims this pool may make this physics frame: an even share of `FLOW_CLAIMS_PER_FRAME`, the
## remainder to the first pools in list order, and one at least (a pool that joined this frame).
func _share() -> int:
	var frame := Engine.get_physics_frames()
	if frame != _round_frame:
		_round_frame = frame
		_round.clear()
		for pool in _claimers:
			_round.append(pool.get_instance_id())
	var n := _round.size()
	var at := _round.find(get_instance_id())
	if at < 0 or n >= FLOW_CLAIMS_PER_FRAME:
		return 1
	var each := floori(float(FLOW_CLAIMS_PER_FRAME) / n)
	return each + (1 if at < FLOW_CLAIMS_PER_FRAME % n else 0)


## Whether the flow still has cells to claim: budget left and somewhere to flow.
func _claiming() -> bool:
	return flow.budget_used() < _budget and not flow.done()


## Blood dragged out of the pool to world `pos` at `level` 0..1 (a smear): grows its outline there.
func drag_out(pos: Vector2, level: float) -> void:
	if flow == null:
		return
	flow.add_trail(
		Vector2i(((pos - global_position) / BloodPoolConfig.flow_cell_size).floor()),
		level,
	)
	PhysicsFxHook.pool_changed(self)
