extends RefCounted
## Helper of the tests of a free body resting on a character who leaves (#194,
## `docs/twins.md`): a character held where it stands by a low anchored post (so a body that falls
## on it cannot bowl it away) and the three ways it can leave: walk off, die, be moved by a script.

const Probe := preload("res://tests/_objects/piece_probe.gd")
## A low post (a test definition: no art, so as tall as a table is, under a character's chest), the
## character stands against its west face, 1 px clear of it.
const POST := {
	"name": "Post", "shape": "rect", "size": Vector2(20, 90), "color": Color(0.3, 0.3, 0.3),
	"material": "metal", "weight": 6, "penetration": 85, "anchored": true,
}
const POST_AT := 77.0
const PUPPET_AT := 55.0
## The ways a character leaves what rests on it.
const WALKS := &"walks off"
const DIES := &"dies"
const MOVED := &"is moved"
const LEAVES := [WALKS, DIES, MOVED]
## How long (s) a body that lost its support has to come to rest, and how flat it must lie: its top
## at most this (px) above the floor, a bookshelf on its side being 40.
const FALLS_WITHIN := 8.0
const FLAT := 45.0
## How long (s) a body has to be asleep, resting on a character held in place, and how far (px) the
## character may be moved in the 2 s after (a body at rest pushes no one).
const ASLEEP_WITHIN := 4.0
const NO_CREEP := 0.5


## A held character `id` at plan point `row` on the x of `x`, with its post.
static func hold(s: TestSetup, id: StringName, x: float, y: float) -> void:
	s.object(StringName("post_%s" % id), POST, Vector2(x + POST_AT, y))
	s.actor(id, &"puppet", Vector2(x + PUPPET_AT, y))


## Make character `id` leave its place in the way `how` names.
static func leave(t: TestContext, id: StringName, how: StringName) -> void:
	var who := t.actor(id)
	match how:
		WALKS:
			t.puppet(id).walk(Vector2.UP)
		DIES:
			who.take_damage(1000.0)
		MOVED:
			who.global_position += Vector2(0.0, 120.0)


## The label of a pair.
static func label(what: String, how: StringName) -> String:
	return "%s on a character who %s" % [what, how]


## Whether the 3D body of `leaf` touches (within 1 px) the 3D body of the piece `post`.
static func touches(leaf: Node2D, post: Node2D) -> bool:
	var body := Probe.body(leaf)
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PhysicsLayers.TWIN_WORLD
	query.margin = 1.0
	query.exclude = [body.get_rid()]
	for child in body.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		query.shape = holder.shape
		query.transform = body.global_transform * holder.transform
		for hit: Dictionary in body.get_world_3d().direct_space_state.intersect_shape(query, 16):
			if TwinSpace.owner_of(hit["collider"]) == post:
				return true
	return false
