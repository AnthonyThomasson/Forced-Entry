extends GameTest
## The ranking of an ambush doorway's posts (`docs/leadership.md` LD15) is the same whether it is
## worked out whole or a chunk of candidate offsets at a time (`EntryPosts.ambush_begin` /
## `ambush_step`): a decision's build takes it a chunk a piece (`SnapshotBuild.Piece.AMBUSH`), so a
## cold ranking (15 to 23 ms in the grenade match's district) is not one frame's lump, and the posts
## an NPC picks must not depend on how it was spread. In a generated house (the posts capture's:
## seed 7 on garage_home, furnished), for every doorway laid from each room it joins, a ranking in
## chunks of `chunked.posts.AMBUSH_CHUNK` and in chunks of 7 holds the posts (spot, side, seen,
## score) and landings the whole one holds, and holds nothing until its last chunk is through. A
## ranking whose house changed under its chunks (a door in the way) is kept nowhere and says
## `stale`, and begun again on the new house it is the one made whole there. No actors: each ranking
## is made on an entry geometry of its own, with no NPC.

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
	_house_changes_mid_ranking(t, script)


## A ranking begun on one house and ended on another (an opening changed: a door was hit open, a
## wall broke) is a mix of two: nothing keeps it, it is `stale`, and the ranking begun again on the
## new house is the whole one the new house has.
func _house_changes_mid_ranking(t: TestContext, script: GDScript) -> void:
	var o: Dictionary = t.world.openings[0]
	var id := String(script.opening_id(o))
	var into := String((o.get("rooms", []) as Array)[0])
	var entry := _entry(t, script)
	var work := _begun(t, entry, id, into)
	if not t.require(not work.has("ranking"), "premise: a ranking to work out"):
		return
	_run(t, entry, work, 1)
	var changed: Array = (t.world.openings as Array).duplicate(true)
	changed[0]["changed_since"] = true
	entry.set_house(changed, t.rooms)
	_run(t, entry, work, 1000)
	t.check(work.has("stale") and not work.has("ranking"), "a house changed mid-ranking: stale")
	t.check(entry.posts.cache.is_empty(), "... and kept in no ranking of the entry's own")
	var again := _begun(t, entry, id, into)
	_run(t, entry, again, 1000)
	var fresh := _entry(t, script)
	fresh.set_house(changed, t.rooms)
	var want := _ranking(t, fresh, id, into, fresh.posts.AMBUSH_WHOLE)
	t.check(again.has("ranking") and want.has("ranking"), "begun again on the new house: ranked")
	t.check(again["ranking"] == want["ranking"], "... the ranking the new house has whole")


## The ranking of doorway `id` into `into` by `entry`, begun.
func _begun(t: TestContext, entry: RefCounted, id: String, into: String) -> Dictionary:
	var map: RID = NavWorld.map_of(t.world)
	var g: Dictionary = entry.geometry(id, into, map, TwinSpace.space_of(t.world))
	return entry.posts.ambush_start(entry, g, map)


## Up to `chunks` chunks of `work`, fewer when it ends (ranked or stale).
func _run(t: TestContext, entry: RefCounted, work: Dictionary, chunks: int) -> void:
	var map: RID = NavWorld.map_of(t.world)
	var space := TwinSpace.space_of(t.world)
	var done := 0
	while done < chunks and not work.has("ranking") and not work.has("stale"):
		entry.posts.ambush_step(work, map, space, entry.posts.AMBUSH_CHUNK)
		done += 1


func _entry(t: TestContext, script: GDScript) -> RefCounted:
	var entry: RefCounted = script.new()
	entry.set_house(t.world.openings, t.rooms)
	return entry


## The ranking of the doorway `id` into room `into` by `entry`, `count` offsets a step:
## `{ ranking, steps }` (`ranking` held only after the last step), {} for a way it does not know.
func _ranking(
	t: TestContext, entry: RefCounted, id: String, into: String, count: int,
) -> Dictionary:
	var map: RID = NavWorld.map_of(t.world)
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
