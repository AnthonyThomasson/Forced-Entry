extends GameTest
## Main's player-mode scene (`main.tscn`) carries no demo label and no player debug panel: no
## `DebugUI` node and no label saying "Top-down demo". Read off the packed scene's own node list
## (instancing it would start the Von launcher and the command server), so it is what the scene
## authors; and off the live tree of Main run whole with a played match, so it is also what Main
## builds at run time.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const MATCH_SEED := 12


func describe() -> Dictionary:
	return {
		"name": "Main's scene has no demo label and no debug panel",
		"description": "main.tscn holds no DebugUI node and no label containing 'Top-down demo'.",
		"tags": ["ui", "hud", "debug"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.set_static(Settings, "path", "user://test_main_no_demo_panel_settings.json")
	s.set_static(Settings, "overlays", {})
	s.set_static(Settings, "setup", {})
	s.set_static(Settings, "debug", Settings.debug)
	s.von_script([])


func run(t: TestContext) -> void:
	_check_scene(t)
	await _check_live_match(t)


## The packed scene's own nodes.
func _check_scene(t: TestContext) -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if not t.require(scene != null, "main.tscn loads"):
		return
	var state := scene.get_state()
	var nodes: Array[String] = []
	var demo_labels: Array[String] = []
	for i in state.get_node_count():
		var path := str(state.get_node_path(i))
		nodes.append(str(state.get_node_name(i)))
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"text" \
					and str(state.get_node_property_value(i, p)).contains("Top-down demo"):
				demo_labels.append(path)
	t.check(not nodes.has("DebugUI"), "main.tscn has no DebugUI node")
	t.check(demo_labels.is_empty(), "no label says 'Top-down demo': %s" % [demo_labels])
	t.check(nodes.has("MatchHUD"), "premise: the scene's other nodes are read (MatchHUD is there)")


## Main run whole with a played match (a human invader among NPCs), its live tree walked.
func _check_live_match(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var built: Dictionary = await main.start_match(MatchBuilder.spec({
		"seed": MATCH_SEED,
		"defenders": { "count": 1 },
		"invaders": { "count": 1 },
		"human": { "node": main.get_node("Player"), "side": &"invader" },
	}))
	if not t.require(
			not built.is_empty() and built["combatants"].size() >= 3,
			"premise: Main's played match is built, the human among its combatants",
	):
		await MainProbe.close(t, viewport)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
		return
	await t.frames(3)
	var walked := main.find_children("*", "", true, false)
	# a match is hundreds of nodes (house, NPCs, HUDs): a handful would mean nothing was walked
	t.check(walked.size() > 50, "premise: the live tree is walked (%d nodes)" % walked.size())
	t.check(main.find_children("DebugUI", "", true, false).is_empty(), "no DebugUI node live")
	var demo: Array[String] = []
	for node: Node in walked:
		if "text" in node and str(node.get("text")).contains("Top-down demo"):
			demo.append(str(node.get_path()))
	t.check(demo.is_empty(), "no live node says 'Top-down demo': %s" % [demo])
	await MainProbe.close(t, viewport)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
