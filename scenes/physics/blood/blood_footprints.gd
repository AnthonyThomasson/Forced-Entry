class_name BloodFootprints
extends Node
## Physics System, blood: bloody footprints for a walker (a Node child of the host, composed like
## BloodWound). The owner reports each footfall with `step`; a foot that lands in wet blood
## (BloodField) soaks up a load of it, and every footfall after that stamps a sole print whose
## opacity follows the load, which drops a little per print, so the trail fades out over a dozen
## steps. A low load prints broken and patchy (the arch and edges drop out); a fast, heavy foot
## slips a little forward. Prints go to the world's BloodDecals. Nothing is stamped in blood that is
## already thick, nor with BloodPrintConfig.footprints_enabled off.

## Points along the sole outline, per side.
const SOLE_STEPS := 14

## Blood on each foot, 0..1, by the owner's foot id.
var _load: Dictionary = {}


## The owner's foot `foot` lands as `fall` says: at world `at` (the middle of the sole), toes toward
## unit `direction`, sole `length` x `width` px, moving at `speed` px/s, its arch on the `inner`
## side (+1/-1) of the direction's frame (+y = `direction.orthogonal()`).
func step(foot: int, fall: Footfall) -> void:
	if not (BloodConfig.enabled and BloodPrintConfig.footprints_enabled):
		return
	var host := get_parent()
	if host == null or host.get_parent() == null:
		return
	var at := fall.at
	var direction := fall.direction
	var length := fall.length
	var wet := 0.0
	for k in [-0.35, 0.0, 0.35]:
		wet = maxf(wet, BloodField.wetness_at(at + direction * length * k))
	var soak: float = maxf(_load.get(foot, 0.0), wet * BloodPrintConfig.pickup_gain)
	if soak >= BloodPrintConfig.min_load and wet < BloodPrintConfig.thick_blood:
		var poly := _sole(fall, soak)
		var alpha := lerpf(
			BloodPrintConfig.alpha_min,
			BloodPrintConfig.alpha_max,
			clampf(soak, 0.0, 1.0),
		)
		BloodDecals.layer(host.get_parent()).print_at(poly, alpha)
		soak -= BloodPrintConfig.decay
	_load[foot] = maxf(soak, 0.0)


## The sole outline in world space for `fall`: heel at the back, arch on the `inner` side, ball,
## rounded toe. `soak` (the foot's load) thins the arch and roughens the edge; `speed` and `soak`
## slip it forward.
func _sole(fall: Footfall, soak: float) -> PackedVector2Array:
	var fraction := clampf(soak, 0.0, 1.0)
	var length := (fall.length
			+ BloodPrintConfig.slip * fraction * clampf(fall.speed / 120.0, 0.0, 1.0))
	var turn := randf_range(-1.0, 1.0) * BloodPrintConfig.turn_jitter
	var forward := fall.direction.rotated(turn)
	var centre := fall.at + Vector2.from_angle(randf() * TAU) * randf() * BloodPrintConfig.jitter
	var frame := PackedVector2Array([centre, forward, forward.orthogonal()])
	return _dedupe(_sole_outline(frame, length, fall.width, fall.inner, fraction))


## The sole's outline round `frame` (its centre, forward and side), `length` x `width` px: the
## outer edge heel to toe, then the inner edge (the arch, on the `inner` side) back; `fraction` (the
## load) thins the arch and roughens the edge.
func _sole_outline(frame: PackedVector2Array, length: float, width: float, inner: float,
		fraction: float) -> PackedVector2Array:
	var rough := (1.0 - fraction) * 0.25
	var arch := lerpf(0.05, 0.55, smoothstep(0.1, 0.6, fraction))  # how much of the arch prints
	var outer_pts := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	for i in SOLE_STEPS + 1:
		var t := float(i) / SOLE_STEPS
		var along := (t - 0.5) * length
		var half := _half_width(t, width)
		var arch_dip := 1.0 - (1.0 - arch) * _arch_weight(t)
		var half_out := half * (1.0 + randf_range(-rough, rough))
		var half_in := half * arch_dip * (1.0 + randf_range(-rough, rough))
		outer_pts.append(frame[0] + frame[1] * along - frame[2] * inner * half_out)
		inner_pts.append(frame[0] + frame[1] * along + frame[2] * inner * half_in)
	inner_pts.reverse()
	outer_pts.append_array(inner_pts)
	return outer_pts


## Half the sole's `width` at `t` along it (0 heel .. 1 toe), the caps rounded off.
func _half_width(t: float, width: float) -> float:
	var cap := sqrt(clampf(t / 0.1, 0.0, 1.0)) * sqrt(clampf((1.0 - t) / 0.16, 0.0, 1.0))
	return width * 0.5 * _profile(t) * cap


## Width of the sole along its length (0 heel .. 1 toe): a narrow heel, a wide ball.
func _profile(t: float) -> float:
	return lerpf(0.62, 1.0, smoothstep(0.35, 0.75, t))


## 1 across the arch (about a third of the way along), falling to 0 at heel and ball.
func _arch_weight(t: float) -> float:
	return smoothstep(0.18, 0.34, t) * (1.0 - smoothstep(0.46, 0.62, t))


## The outline without the repeated points the rounded caps make, which would break triangulation.
func _dedupe(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 0.0004:
			out.append(p)
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) <= 0.0004:
		out.remove_at(out.size() - 1)
	return out
