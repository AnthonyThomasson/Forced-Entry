extends RefCounted
## Shared helper for the tests that pin where an ambush order's members wait to a capture
## (`docs/leadership.md` LD15, D17; not a test itself): `const AmbushPosts :=
## preload("res://tests/_ai/ambush_posts_probe.gd")`.
##
## The posts are read through the published entry geometry (`agent_entry.gd`, loaded by path, as
## `slots_probe.gd` reads it): `new()`, `set_house(openings, rooms)`, `opening_id(o)`,
## `geometry(id, into, map, space)` and `posts.ambush_spot(entry, g, place, map, space)`, the body's
## crouched height handed to its `posts` as the perception hands it in (`crouch`). The capture
## beside each test holds the full ranking (every post's grenade landings counted, each member its
## own): for every doorway of the house, laid from each room it joins, every member `nth` of an
## order to `count` (1 to `MAX_COUNT`), the post `ambush_spot` gave (`[x, y, seen]`, `[]` for none).

const ENTRY_SCRIPT := "res://scenes/ai/perception/agent_entry.gd"
## The largest order a capture holds: past the hidden posts of a side, the later members fall to
## posts seen from outside, where the ranks below `seen` still decide.
const MAX_COUNT := 6
## How near (px) a post must lie to its captured spot.
const SPOT_TOLERANCE := 0.01


## Every post of the world's house (`t.world`'s rooms and openings, its navigation map and physics
## space): "<opening id>><room key>#<nth>/<count>" -> `[x, y, seen]`, or `[]` for no post.
static func posts_of(t: TestContext) -> Dictionary:
	var script := load(ENTRY_SCRIPT) as GDScript
	var entry: RefCounted = script.new()
	entry.set_house(t.world.openings, t.rooms)
	entry.posts.crouch = float(CharacterPostureConfig.postures[&"crouch"]["coverage"])
	var map: RID = t.world.get_world_2d().navigation_map
	var space := t.world.get_world_2d().direct_space_state
	var ways: Array = []
	for o: Dictionary in t.world.openings:
		for k in o.get("rooms", []):
			ways.append(entry.geometry(String(script.opening_id(o)), String(k), map, space))
	var out := {}
	for g: Dictionary in ways:
		for count in range(1, MAX_COUNT + 1):
			for nth in count:
				var at: Dictionary = entry.posts.ambush_spot(
					entry, g, Vector2i(nth, count), map, space,
				)
				out["%s>%s#%d/%d" % [g["id"], g["into"], nth, count]] = (
					[]
					if at.is_empty()
					else [(at["spot"] as Vector2).x, (at["spot"] as Vector2).y, at["seen"]]
				)
	return out


## Check the world's posts (`posts_of`) against the capture at `path`, one check per post that
## differs (and one for the set of posts asked).
static func check_capture(t: TestContext, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not t.require(file != null, "the capture exists (%s)" % path):
		return
	var expected: Dictionary = JSON.parse_string(file.get_as_text())
	var got := posts_of(t)
	var keys := got.keys()
	keys.sort()
	var want_keys := expected.keys()
	want_keys.sort()
	if not t.require(
			keys == want_keys,
			"the same doorways, rooms and places as the capture (%d, captured %d)"
				% [keys.size(), want_keys.size()],
	):
		return
	var differ: Array = []
	for key: String in keys:
		if not _same(got[key], expected[key]):
			differ.append("%s: %s, captured %s" % [key, got[key], expected[key]])
	t.check(
		differ.is_empty(),
		"every post of the %d asked is the captured one (%d differ: %s)"
			% [keys.size(), differ.size(), differ.slice(0, 8)],
	)


## Whether post `a` (`posts_of`) is the captured `b`: both none, or the same `seen` and a spot
## within `SPOT_TOLERANCE`.
static func _same(a: Array, b: Array) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	return (Vector2(a[0], a[1]).distance_to(Vector2(b[0], b[1])) <= SPOT_TOLERANCE
			and int(a[2]) == int(b[2]))
