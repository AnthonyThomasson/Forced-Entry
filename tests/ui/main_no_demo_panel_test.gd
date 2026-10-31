extends GameTest
## Main's player-mode scene (`main.tscn`) carries no demo label and no player debug panel: no
## `DebugUI` node and no label saying "Top-down demo". Read off the packed scene's own node list
## (instancing it would start the Von launcher and the command server), so it is what Main builds.

const MAIN_SCENE := "res://scenes/main.tscn"


func describe() -> Dictionary:
	return {
		"name": "Main's scene has no demo label and no debug panel",
		"description": "main.tscn holds no DebugUI node and no label containing 'Top-down demo'.",
		"tags": ["ui", "hud", "debug"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
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
