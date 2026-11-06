extends GameTest
## With open ears the game bus needs no per-frame work. Deafness still closes and releases its
## low-pass filter, including the final write that disables it again.

const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "An open ear skips audio bus writes",
		"description": "An unmuffled frame writes neither the filter's enabled state nor its "
			+ "cutoff; a stun still closes it and the release still opens and disables it.",
		"tags": ["audio", "perf"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.actor(&"human", &"puppet", Vector2(300, 200))


func run(t: TestContext) -> void:
	var service: Node = Sound
	service.set("focus", null)
	await t.seconds(2.0)
	var before = service.get_meta(&"bus_writes")
	if not t.require(before != null, "the audio service counts its muffle bus writes"):
		return
	await t.frames(30)
	t.check(service.get_meta(&"bus_writes") == before, "open ears write nothing to the audio bus")

	var human := t.actor(&"human")
	service.set("focus", human)
	Probe.stun(human, 0.0, 0.4)
	await t.frames(6)
	var muffled_writes: int = service.get_meta(&"bus_writes")
	t.check(muffled_writes > before, "deafness still writes the closing filter")
	await t.seconds(2.0)
	t.check(
		service.get_meta(&"bus_writes") > muffled_writes,
		"the final release writes the open filter",
	)
	var bus := AudioServer.get_bus_index(Sound.GAME_BUS)
	t.check(not AudioServer.is_bus_effect_enabled(bus, 0), "the released filter is disabled")
	before = service.get_meta(&"bus_writes")
	await t.frames(30)
	t.check(
		service.get_meta(&"bus_writes") == before,
		"open ears are quiet again after the release",
	)
	service.set("focus", null)
