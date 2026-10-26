extends UnitSuite
## Native unit suite (pure logic): an NPC's tunables live in per-NPC topic nodes under its
## controller's `Tuning` child (`NpcTuning`). A test
## world and the match builder set them on an NPC before it joins the tree, so its scene must hand
## the controller its `tuning` hub and the hub its fifteen topics at `instantiate`; an indexed path
## (`tuning:entry:ready_timeout`) must reach that NPC's own topic; two NPCs must never share one;
## the presets keep their authored data (the defender hostile to trespassers, the invader unfamiliar
## with the house); and the hub a unit test builds alone in code frees with its topics. Read by
## name and path, so a missing piece fails the assertion that names it.

const NPC := "res://scenes/ai/npc.tscn"
const DEFENDER := "res://scenes/ai/npc_defender.tscn"
const INVADER := "res://scenes/ai/npc_invader.tscn"
## The hub's script, loaded by path.
const HUB := "res://scenes/ai/tuning/npc_tuning.gd"
## The fifteen topics the hub holds (the ADR's list).
const TOPICS := [
	&"decision", &"context", &"tactics", &"combat", &"coverage", &"memory", &"senses", &"radio",
	&"entry", &"entry_geometry", &"entry_guard", &"grenades", &"watch", &"hostility", &"pace",
]


## An instance of the scene at `path`, not in the tree, freed after the test.
func _instance(path: String) -> Node:
	return auto_free((load(path) as PackedScene).instantiate())


## The controller of `npc` (its `GoalController` child).
func _controller(npc: Node) -> Node:
	return npc.get_node("GoalController")


## The value at the indexed `path` under `controller` (`tuning:<topic>:<name>`), or null while it
## has no tuning hub.
func _read(controller: Node, path: String) -> Variant:
	if controller.get("tuning") == null:
		return null
	return controller.get_indexed(NodePath(path))


func test_an_instanced_npc_has_its_tuning_and_every_topic_before_the_tree() -> void:
	for path: String in [NPC, DEFENDER, INVADER]:
		var npc := _instance(path)
		assert_bool(npc.is_inside_tree()).is_false()
		var tuning: Object = _controller(npc).get("tuning")
		assert_object(tuning).override_failure_message("%s: no tuning hub" % path).is_not_null()
		if tuning != null:
			for topic: StringName in TOPICS:
				assert_object(tuning.get(topic)) \
					.override_failure_message("%s: no topic %s" % [path, topic]) \
					.is_not_null()


func test_an_indexed_path_sets_that_npcs_own_topic_before_the_tree() -> void:
	var controller := _controller(_instance(NPC))
	controller.set_indexed(NodePath("tuning:entry:ready_timeout"), 2.5)
	var entry := controller.get_node_or_null("Tuning/Entry")
	assert_object(entry).override_failure_message("no Tuning/Entry node").is_not_null()
	if entry != null:
		assert_that(entry.get("ready_timeout")).is_equal(2.5)


func test_two_npcs_do_not_share_a_topic() -> void:
	var a := _controller(_instance(NPC))
	var b := _controller(_instance(NPC))
	var first: Variant = _read(b, "tuning:combat:shoot_range")
	assert_that(first).override_failure_message("no tuning:combat:shoot_range").is_not_null()
	if first == null:
		return
	a.set_indexed(NodePath("tuning:combat:shoot_range"), float(first) + 100.0)
	assert_that(_read(b, "tuning:combat:shoot_range")).is_equal(first)
	assert_that(_read(a, "tuning:combat:shoot_range")).is_equal(float(first) + 100.0)


func test_the_presets_keep_their_authored_tuning() -> void:
	var d := _controller(_instance(DEFENDER))
	var i := _controller(_instance(INVADER))
	# The defender preset: hostile to trespassers and to attackers, fighting inside the house.
	assert_that(_read(d, "tuning:hostility:on_trespass")).is_equal(true)
	assert_that(_read(d, "tuning:hostility:on_attack")).is_equal(true)
	assert_that(_read(d, "tuning:decision:defend_territory")).is_equal(true)
	# The invader preset: hostile on sight, unfamiliar with the house, entering rooms tactically.
	assert_that(_read(i, "tuning:hostility:on_sight")).is_equal(true)
	assert_that(_read(i, "tuning:memory:familiar_with_house")).is_equal(false)
	assert_that(_read(i, "tuning:entry:enabled")).is_equal(true)
	assert_that(_read(i, "tuning:decision:defend_territory")).is_equal(false)


func test_a_hub_built_in_code_has_every_topic_and_frees_with_them() -> void:
	var hub_script: Script = load(HUB) if ResourceLoader.exists(HUB) else null
	assert_object(hub_script).override_failure_message("no hub script at %s" % HUB).is_not_null()
	if hub_script == null:
		return
	var hub: Node = hub_script.call(&"defaults")
	var ids: Array[int] = []
	for topic: StringName in TOPICS:
		var node: Object = hub.get(topic)
		assert_object(node).override_failure_message("defaults(): no topic %s" % topic) \
			.is_not_null()
		if node != null:
			ids.append(node.get_instance_id())
	hub.free()
	for id in ids:
		assert_bool(is_instance_id_valid(id)).is_false()
