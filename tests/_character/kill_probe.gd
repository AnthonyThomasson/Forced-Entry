extends RefCounted
## Shared helpers for the Character tests that need real fallen bodies (not a test itself):
## `const Kill := preload("res://tests/_character/kill_probe.gd")`. A puppet `shooter` shoots
## its targets dead, so their ragdolls land.


## The shooter (puppet `shooter`) shoots each of the `count` targets (`target0`, `target1`, ...)
## dead. Whether they all died (false after a failed `require`).
static func kill_targets(t: TestContext, count: int) -> bool:
	var shooter := t.puppet(&"shooter")
	for i in count:
		var id := StringName("target%d" % i)
		shooter.aim_at(t.actor(id))
		await t.seconds(0.4)
		shooter.shoot()
		if not t.require(
				await t.until(
					func(): return t.happened(&"died", func(d): return d["actor"] == id),
					2.0,
				),
				"%s dies" % id,
		):
			return false
	return true
