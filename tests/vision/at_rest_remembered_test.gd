extends GameTest
## V6 (`docs/player-vision.md`): what comes to rest is remembered where it lies, and what is moved
## again is moving again. In an arena with the player (the viewer): a dead body is on `MOVING`
## until its ragdoll sleeps and on `WORLD` after, and on `MOVING` again from the frame a blast
## wakes it until it sleeps again; the gun it dropped and a spent casing are on `MOVING` while they
## move and on `WORLD` once they have lain still; a frag lying still is on `WORLD` from the
## `rest` event on and on `MOVING` in flight.
##
## It reads (tests/_vision/vision_probe.gd) each node's `visibility_layer`, the corpse's
## `anatomy.ragdoll.is_settled()`, the world's `grenade` events and what the nodes do (a place
## that moved, a place that held still).

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
## A node moved when it changed place by this much (px) in a frame; it lay still after this many
## frames with no move (a thing that has stopped skidding goes on turning for a second at most).
const MOVED := 1.0
const STILL_FRAMES := 90
## An explosion's shove on the corpse: from this point, this hard (`blast_push`).
const BLAST_FROM := Vector2(100, 350)
const BLAST_IMPULSE := 40_000.0
## At least this many frames of each kind of check must have run, or the test proves nothing.
const MIN_FRAMES := 5

var _last_at := {}
var _still := {}
var _moved := {}
var _rest := {}
var _wrong := {}
var _checked := {}
var _t: TestContext
var _corpse: Node2D = null


func describe() -> Dictionary:
	return {
		"name": "What comes to rest is remembered, and moves again when moved",
		"description": "A dead body once its ragdoll sleeps, the gun it dropped, a casing and a "
			+ "frag lying still are on WORLD; while they move, and a body a blast wakes, "
			+ "on MOVING.",
		"tags": ["vision", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.actor(&"you", &"player", Vector2(150, 350))
	s.actor(&"shooter", &"puppet", Vector2(600, 350), { "max_health": 100_000.0 })
	s.actor(&"victim", &"puppet", Vector2(1000, 350), { "start_slot": 3 })


func run(t: TestContext) -> void:
	_t = t
	var shooter := t.puppet(&"shooter")
	var victim := t.actor(&"victim")
	Grenades.arm(t.actor(&"shooter"), 0, 1)
	shooter.select_slot(3)
	shooter.aim_at(victim)
	await _watch(t, 0.5)
	shooter.shoot()
	await _watch(t, 1.5)
	await Grenades.throw_at(t, &"shooter", 8, Vector2(700, 620))
	await _watch(t, 4.0)
	# Killed on the run, so the gun it drops and its body carry its momentum.
	t.puppet(&"victim").walk(Vector2.RIGHT)
	await _watch(t, 0.5)
	_corpse = victim
	victim.take_damage(1000.0)
	await _watch(t, 6.0)
	t.require(
		victim.anatomy.ragdoll.is_settled(),
		"premise: the corpse's ragdoll has gone to sleep",
	)
	victim.blast_push(BLAST_FROM, BLAST_IMPULSE)
	await t.frames(1)
	t.require(
		not victim.anatomy.ragdoll.is_settled(),
		"premise: the blast woke the corpse's ragdoll",
	)
	await _watch(t, 6.0)
	for kind in ["casing", "gun", "grenade", "corpse"]:
		t.check(
			_moved.get(kind, 0) >= MIN_FRAMES and _rest.get(kind, 0) >= MIN_FRAMES,
			"premise: a %s was seen both moving (%d frames) and at rest (%d)"
			% [kind, _moved.get(kind, 0), _rest.get(kind, 0)],
		)
		t.check(
			_wrong.get(kind, 0) == 0,
			"every %s is on MOVING while it moves and on WORLD at rest (%d of %d frames not)"
			% [kind, _wrong.get(kind, 0), _checked.get(kind, 0)],
		)


## Run `seconds`, checking every node that can come to rest each frame.
func _watch(t: TestContext, seconds: float) -> void:
	for _i in int(seconds * 60.0):
		await t.frames(1)
		for node in t.world.find_children("*", "", true, false):
			var kind := _kind_of(node)
			if kind != "":
				_check(kind, node as Node2D)
		if _corpse != null and _corpse.is_dead:
			var asleep: bool = _corpse.anatomy.ragdoll.is_settled()
			_judge("corpse", _corpse, not asleep)


## One frame of one node: by what it did (a place that moved, a place that held still), or for a
## grenade by its `rest` event, which layer it must be on.
func _check(kind: String, node: Node2D) -> void:
	var key := node.get_instance_id()
	var moved: bool = (
		_last_at.has(key) and (_last_at[key] as Vector2).distance_to(node.global_position) >= MOVED
	)
	_last_at[key] = node.global_position
	_still[key] = 0 if moved else int(_still.get(key, 0)) + 1
	if kind == "grenade":
		var rested := _t.happened(
			&"grenade",
			func(d: Dictionary) -> bool: return d["stage"] == &"rest",
		)
		_judge(kind, node, not rested)
	elif moved:
		_judge(kind, node, true)
	elif _still[key] >= STILL_FRAMES:
		_judge(kind, node, false)


## `node` is moving (or not): it must be on `MOVING` (or `WORLD`).
func _judge(kind: String, node: Node2D, moving: bool) -> void:
	_checked[kind] = _checked.get(kind, 0) + 1
	if moving:
		_moved[kind] = _moved.get(kind, 0) + 1
	else:
		_rest[kind] = _rest.get(kind, 0) + 1
	var want: int = Probe.MOVING if moving else Probe.WORLD
	if node.visibility_layer != want:
		_wrong[kind] = _wrong.get(kind, 0) + 1


## What can come to rest `node` is, or "": a spent casing, a gun let go, a grenade in the world.
func _kind_of(node: Node) -> String:
	var named := String(node.name)
	var kind := ""
	if not node is Node2D:
		kind = ""
	elif named.begins_with("Casing") and not named.contains("Visuals"):
		kind = "casing"
	elif named.begins_with("Dropped") and not named.contains("Spoon"):
		# The spoon a throw pops falls where it stands, which a place cannot tell from lying still.
		kind = "gun"
	elif node.is_in_group(&"live_grenades"):
		kind = "grenade"
	return kind
