extends GameTest
## V5 (`docs/player-vision.md`): what moves is drawn only inside the cone, so each moving thing
## sits on the visibility bit `MOVING` (2) and what is at rest on `WORLD` (1): the 3D mirror reads
## that bit to hide a body while the cone does not reach it (`art/mirror_hides_unseen_movers`), and
## the shader's cut is read off the mark its parts carry (`art/moving_mark`: a burst's bits and
## sparks, a blast's parts, the bullet batch). In an arena with the player (the viewer), a puppet
## that walks, shoots another puppet and throws a frag: the living puppets and the bullet and the
## grenade in flight are each on `MOVING`, while a piece of furniture, a wall and the blood
## already settled (a splatter) are on `WORLD` (the premise that the read tells them apart).
##
## It reads (tests/_vision/vision_probe.gd) each node's `visibility_layer`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
## The moving things the run must have seen, by kind, or the test proves nothing.
const KINDS := ["bullet", "grenade"]
## Blood that has landed is settled: a splatter or a pool, remembered where it lies.
const SETTLED := ["splat"]

var _seen := {}
var _wrong := {}


func describe() -> Dictionary:
	return {
		"name": "What moves is on the MOVING bit, what is settled on WORLD",
		"description": "The living, a bullet and a grenade in flight are on MOVING, which the 3D "
			+ "mirror reads to hide them outside the cone; furniture, a wall and settled blood "
			+ "are on WORLD.",
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
	t.check(
		t.object(&"wardrobe").visibility_layer == Probe.WORLD,
		"premise: a piece of furniture is on WORLD",
	)
	var shooter := t.puppet(&"shooter")
	Grenades.arm(t.actor(&"shooter"), 0, 1)
	shooter.select_slot(3)
	await _watch(t, 0.3)
	shooter.aim_at(t.actor(&"victim"))
	await _watch(t, 0.5)
	shooter.shoot()
	await _watch(t, 1.0)
	shooter.walk_to(Vector2(800, 250))
	await _watch(t, 1.0)
	await Grenades.throw_at(t, &"shooter", 8, Vector2(1100, 150))
	await _watch(t, 5.0)
	_check_kinds(t)
	for who in [&"you", &"shooter", &"victim"]:
		t.check(t.actor(who).visibility_layer == Probe.MOVING, "%s, alive, is on MOVING" % who)


## What the run saw of each kind of thing: the settled blood on `WORLD`, the moving things on
## `MOVING`.
func _check_kinds(t: TestContext) -> void:
	for kind in SETTLED:
		t.check(_seen.get(kind, 0) > 0, "premise: a %s was seen" % kind)
		t.check(
			_wrong.get(kind, 0) == 0,
			"every settled blood %s is on WORLD (%d of %d not)"
			% [kind, _wrong.get(kind, 0), _seen.get(kind, 0)],
		)
	for kind in KINDS:
		t.check(_seen.get(kind, 0) > 0, "premise: a %s was seen" % kind)
		t.check(
			_wrong.get(kind, 0) == 0,
			"every %s seen is on MOVING (%d of %d not)"
			% [kind, _wrong.get(kind, 0), _seen.get(kind, 0)],
		)


## Run `seconds`, looking at every moving thing in the world each frame.
func _watch(t: TestContext, seconds: float) -> void:
	for _i in int(seconds * 60.0):
		await t.frames(1)
		for node in t.world.find_children("*", "", true, false):
			var kind := _kind_of(node)
			if kind == "grenade" and _rested(t):
				continue  # lying still it is at rest (tests/vision/at_rest_remembered_test.gd)
			if kind != "":
				_seen[kind] = _seen.get(kind, 0) + 1
				if _is_wrong(kind, node):
					_wrong[kind] = _wrong.get(kind, 0) + 1


## Whether `node`, of `kind`, is on the wrong bit: a moving thing must be on `MOVING`, settled
## blood on `WORLD`.
func _is_wrong(kind: String, node: CanvasItem) -> bool:
	return node.visibility_layer != (Probe.WORLD if kind in SETTLED else Probe.MOVING)


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
	elif named.begins_with("BloodSplat"):
		kind = "splat"
	return kind
