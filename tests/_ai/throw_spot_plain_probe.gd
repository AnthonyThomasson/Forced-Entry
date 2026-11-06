extends RefCounted
## The throw-spot search before snapped-candidate lob deduplication, kept as an independent
## reference for ai/grenade/throw_spots_match_plain. Every candidate that passes the cheap tests is
## lob-tested, including one whose snapped point was already tried and rejected.


## The full undeduplicated candidate search, in the same order and with the same annotations as
## AgentTactics._throw_found.
static func found(tactics: RefCounted, ctx: Dictionary, aim: ThrowAim, ex: Array) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var out: Array = []
	for r: Vector2 in tactics._throw_raw(self_pos, aim):
		var p: Vector2 = tactics._throw_point(ctx, r, aim)
		if p == Vector2.INF:
			continue
		if (out.any(func(c): return (c["point"] as Vector2).distance_to(p) < 12.0)
				or not aim.lob.call(p)):
			continue
		var hidden: bool = tactics.blocked(ctx["space"], aim.spot, p, ex)
		out.append({
			"point": p,
			"hidden": hidden,
			"cover": "" if hidden else tactics._cover_near(ctx["space"], p, aim.spot, ex),
		})
	out.sort_custom(func(a, b):
		var ra: int = tactics._throw_rank(a)
		var rb: int = tactics._throw_rank(b)
		if ra != rb:
			return ra < rb
		return self_pos.distance_squared_to(a["point"]) < self_pos.distance_squared_to(b["point"]))
	return out
