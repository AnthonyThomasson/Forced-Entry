extends GameTest
## The ranking of an ambush doorway's posts (`docs/leadership.md` LD15) is the same whether it is
## worked out whole or a chunk of candidate offsets at a time (`EntryPosts.ambush_begin` /
## `ambush_step`): a decision's build takes it a chunk a piece (`SnapshotBuild.Piece.AMBUSH`), so a
## cold ranking (15 to 23 ms in the grenade match's district) is not one frame's lump, and the posts
## an NPC picks must not depend on how it was spread. In a generated house (the posts capture's:
## seed 7 on garage_home, furnished), for every doorway laid from each room it joins, a ranking in
## chunks of `chunked.posts.AMBUSH_CHUNK` and in chunks of 7 holds the posts (spot, side, seen,
## score) and landings the whole one holds, and holds nothing until its last chunk is through. No
## actors: each ranking is made on an entry geometry of its own, with no NPC.

const ENTRY_SCRIPT := "res://scenes/ai/perception/agent_entry.gd"
const SEED := 7
const PLAN := "garage_home"
const ODD_CHUNK := 7


func describe() -> Dictionary:
	return {
		"name": "An ambush ranking in chunks is the whole ranking",
		"description": "Every doorway of a generated house, from each room it joins: the ambush "
			+ "posts ranked a chunk of offsets at a time are the ones ranked whole, and nothing "
			+ "is ranked before the last chunk (LD15).",
		"tags": ["ai", "combat", "leadership", "ambush", "scripted", "regression"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.switch(&"worldgen.doors", false)
	s.house(SEED, PLAN)


func run(t: TestContext) -> void:
	await t.frames(2)
	var script := load(ENTRY_SCRIPT) as GDScript
	var entries: Array = [_entry(t, script), _entry(t, script), _entry(t, script)]
	var ways := 0
	var with_posts := 0
	for o: Dictionary in t.world.openings:
		for k in o.get("rooms", []):
			var id := String(script.opening_id(o))
			var want := _ranking(t, entries[0], id, String(k), entries[0].posts.AMBUSH_WHOLE)
			if want.is_empty():
				continue
			ways += 1
			with_posts += 0 if (want["ranking"]["posts"] as Array).is_empty() else 1
			var chunk: int = entries[1].posts.AMBUSH_CHUNK
			var got := _ranking(t, entries[1], id, String(k), chunk)
			t.check(got["ranking"] == want["ranking"], "%s>%s: chunks of %d" % [id, k, chunk])
			t.check(int(got["steps"]) > 1, "%s>%s: more than one step (%d)" % [id, k, got["steps"]])
			var odd := _ranking(t, entries[2], id, String(k), ODD_CHUNK)
			t.check(odd["ranking"] == want["ranking"], "%s>%s: chunks of 7" % [id, k])
	t.require(
		ways > 0 and with_posts > 0,
		"premise: doorways ranked (%d), with posts (%d)" % [ways, with_posts],
	)


func _entry(t: TestContext, script: GDScript) -> RefCounted:
	var entry: RefCounted = script.new()
	entry.set_house(t.world.openings, t.rooms)
	return entry


## The ranking of the doorway `id` into room `into` by `entry`, `count` offsets a step:
## `{ ranking, steps }` (`ranking` held only after the last step), {} for a way it does not know.
func _ranking(
	t: TestContext, entry: RefCounted, id: String, into: String, count: int,
) -> Dictionary:
	var map: RID = t.world.get_world_2d().navigation_map
	var space := TwinSpace.space_of(t.world)
	var g: Dictionary = entry.geometry(id, into, map, space)
	if g.is_empty():
		return {}
	var work: Dictionary = entry.posts.ambush_start(entry, g, map)
	var steps := 0
	while not work.has("ranking"):
		entry.posts.ambush_step(work, map, space, count)
		steps += 1
	return { "ranking": work["ranking"], "steps": steps }
