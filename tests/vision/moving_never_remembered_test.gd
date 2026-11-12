extends GameTest
## V5 (`docs/player-vision.md`): what moves is never remembered, so each moving thing sits on the
## visibility bit `MOVING` (2) and the view's capture, which paints the memory, leaves that bit
## out of its cull mask. In an arena with the player (the viewer), a puppet that walks, shoots
## another puppet and throws a frag: the living puppets and what they hold, the bullet, the grenade
## in flight, the hit particles, the flying debris, the blood spray in flight (the blood-red bursts
## a wound throws) and the explosion's look are each on `MOVING` and not drawn by the capture, while
## a piece of furniture, a wall and the blood already settled (a splatter) are (the premise that the
## read tells them apart). The flash lights (a shot's, a burst's) are lights, which the cull mask
## does not reach: they are out of the capture by their canvas.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView`'s `capture()` cull mask and each
## node's `visibility_layer`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
## The moving things the run must have seen, by kind, or the test proves nothing.
const KINDS := ["bullet", "grenade", "particles", "blood spray", "debris", "explosion"]
## The colour a blood burst starts as (`HitParticles`' `blood` tint).
const BLOOD_RED := Color(0.6, 0.05, 0.06)
## Blood that has landed is settled: a splatter or a pool, remembered where it lies.
const SETTLED := ["splat"]

var _seen := {}
var _wrong := {}


func describe() -> Dictionary:
	return {
		"name": "What moves is on the MOVING bit and never in the capture",
		"description": "The living, their held gun, a bullet, a grenade in flight, hit particles, "
			+ "flying debris and an explosion's look are on MOVING, which the capture leaves out, "
			+ "and the flash lights are on a canvas it does not draw; furniture and a wall are "
			+ "drawn by it.",
		"tags": ["vision", "scripted"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.object(&"wardrobe", "wardrobe", Vector2(300, 100))
	s.actor(&"you", &"player", Vector2(150, 350))
	s.actor(&"shooter", &"puppet", Vector2(600, 350), { "max_health": 100_000.0 })
	s.actor(&"victim", &"puppet", Vector2(1000, 350), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	var mask := view.capture().canvas_cull_mask
	t.check((mask & Probe.MOVING) == 0, "the capture's cull mask leaves MOVING out")
	t.check((mask & Probe.OVERLAY) == 0, "the capture's cull mask leaves OVERLAY out")
	t.check((mask & Probe.WORLD) != 0, "the capture's cull mask keeps WORLD")
	t.check(
		Probe.in_capture(view, t.object(&"wardrobe")),
		"premise: a piece of furniture is drawn by the capture",
	)
	var shooter := t.puppet(&"shooter")
	Grenades.arm(t.actor(&"shooter"), 0, 1)
	shooter.select_slot(3)
	await _watch(t, view, 0.3)
	shooter.aim_at(t.actor(&"victim"))
	await _watch(t, view, 0.5)
	shooter.shoot()
	await _watch(t, view, 1.0)
	shooter.walk_to(Vector2(800, 250))
	await _watch(t, view, 1.0)
	await Grenades.throw_at(t, &"shooter", 8, Vector2(1100, 150))
	await _watch(t, view, 5.0)
	_check_kinds(t)
	for who in [&"you", &"shooter", &"victim"]:
		var body := t.actor(who)
		t.check(body.visibility_layer == Probe.MOVING, "%s, alive, is on MOVING" % who)
		t.check(not Probe.in_capture(view, body), "%s, alive, is not drawn by the capture" % who)
	var shooter_body := t.actor(&"shooter")
	t.check(
		not Probe.in_capture(view, shooter_body.get_node("Visuals")),
		"what the shooter draws (its body, its held gun) is not drawn by the capture",
	)
	_check_flashes(t, view)


## A light is not a canvas item to the engine: the cull mask never reaches it (measured windowed: a
## flash lit the capture's floor exactly as the live one, whatever its `visibility_layer`; 4.4's
## `renderer_viewport.cpp` gathers a viewport's lights from its canvases alone). The flash lights
## are out of the capture by being on a canvas the capture does not draw.
func _check_flashes(t: TestContext, view: PlayerView) -> void:
	var lights := t.world.find_children("Flash*", "PointLight2D", true, false)
	t.check(not lights.is_empty(), "premise: the flash pool's lights exist")
	var sky := t.world.find_child("Sky", true, false) as CanvasItem
	t.check(
		sky != null and Probe.light_in_capture(view, sky),
		"premise: the sky, a light of the world's canvas, is lit in the capture",
	)
	var burst_lights := 0
	for light in lights:
		t.check(
			not Probe.light_in_capture(view, light),
			"%s is not lit in the capture" % light.name,
		)
		if _check_flash_on_screen(t, light):
			burst_lights += 1
	t.require(
		burst_lights > 0,
		"premise: a shot's or a burst's flash lit the world (%d of %d lights)"
		% [burst_lights, lights.size()],
	)


## A flash still lights the live world where it burst: its point on the screen is the main
## viewport's canvas transform of its world position, as a world item's is (a flash off its own
## canvas that did not follow the camera would light the wrong place). False when the light is
## not at a burst of this run (a pooled light that was never used).
func _check_flash_on_screen(t: TestContext, light: Node2D) -> bool:
	var bursts := t.events_of(&"shot") + t.events_of(&"explosion")
	var at := light.global_position
	if not bursts.any(func(e: Dictionary) -> bool: return e["position"].distance_to(at) < 1.0):
		return false
	var on_screen := light.get_global_transform_with_canvas().origin
	var expected := Pointer.screen_of(t.world, at)
	t.check(
		on_screen.distance_to(expected) < 0.5,
		"%s lights the screen at %s, where its burst is (%s)" % [light.name, on_screen, expected],
	)
	return true


## What the run saw of each kind of thing: the settled blood on `WORLD`, the moving things on
## `MOVING`.
func _check_kinds(t: TestContext) -> void:
	for kind in SETTLED:
		t.check(_seen.get(kind, 0) > 0, "premise: a %s was seen" % kind)
		t.check(
			_wrong.get(kind, 0) == 0,
			"every settled blood %s is on WORLD and drawn by the capture (%d of %d not)"
			% [kind, _wrong.get(kind, 0), _seen.get(kind, 0)],
		)
	for kind in KINDS:
		t.check(_seen.get(kind, 0) > 0, "premise: a %s was seen" % kind)
		t.check(
			_wrong.get(kind, 0) == 0,
			"every %s seen is on MOVING and out of the capture (%d of %d not)"
			% [kind, _wrong.get(kind, 0), _seen.get(kind, 0)],
		)


## Run `seconds`, looking at every moving thing in the world each frame.
func _watch(t: TestContext, view: PlayerView, seconds: float) -> void:
	for _i in int(seconds * 60.0):
		await t.frames(1)
		for node in t.world.find_children("*", "", true, false):
			var kind := _kind_of(node)
			if kind == "grenade" and _rested(t):
				continue  # lying still it is remembered (tests/vision/at_rest_remembered_test.gd)
			if kind != "":
				_seen[kind] = _seen.get(kind, 0) + 1
				if _is_wrong(kind, node, view):
					_wrong[kind] = _wrong.get(kind, 0) + 1


## Whether `node`, of `kind`, is on the wrong layer: a moving thing must be on `MOVING` and out of
## the capture, settled blood on `WORLD` and in it.
func _is_wrong(kind: String, node: CanvasItem, view: PlayerView) -> bool:
	if kind in SETTLED:
		return node.visibility_layer != Probe.WORLD or not Probe.in_capture(view, node)
	return node.visibility_layer != Probe.MOVING or Probe.in_capture(view, node)


## Whether a grenade has come to rest (a `grenade` event of stage `rest`).
func _rested(t: TestContext) -> bool:
	return t.happened(&"grenade", func(d: Dictionary) -> bool: return d["stage"] == &"rest")


## What moving thing `node` is, or "" when it is none (by the name it was given or the group it
## joined).
func _kind_of(node: Node) -> String:
	var named := String(node.name)
	var kind := ""
	if not node is CanvasItem:
		kind = ""
	elif named.begins_with("Projectile") and not named.contains("Visuals"):
		kind = "bullet"
	elif node.is_in_group(&"live_grenades"):
		kind = "grenade"
	elif node is CPUParticles2D and named.begins_with("HitParticles"):
		kind = "blood spray" if _is_blood(node) else "particles"
	elif named.begins_with("BloodSplat"):
		kind = "splat"
	elif named.begins_with("Explosion"):
		kind = "explosion"
	elif node.get_child_count() > 0 and node.get_child(0).name == "DebrisVisuals":
		kind = "debris"
	return kind


## Whether a burst of hit particles is blood: it starts as the blood red.
func _is_blood(burst: CPUParticles2D) -> bool:
	return burst.color_ramp != null and burst.color_ramp.colors[0].is_equal_approx(BLOOD_RED)
