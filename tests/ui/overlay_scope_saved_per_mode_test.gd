extends GameTest
## The overlay bar's "Show on" scope is saved per mode and restored: Main run whole
## (`main_probe.gd`) as the setup window's Start launches it, against a scratch settings file (never
## the real one), with the vision toggle saved on. A watched match starts on `selected` (nobody
## shows), and the scope chosen on the bar (`Main.set_overlay_scope`) shows at once on the NPCs of
## that side and is written to the file under `watch` alone; a fresh launch (the statics put back,
## the file read again) restores it, and an endless run keeps it into the next match it plays. A
## played match has its own scope: `all` at first, whatever the watched one is, and the one chosen
## there comes back in the next played match. Who shows is read off the NPCs' own vision overlays.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_overlay_scope_test.json"
const WATCH := {
	"mode": "watch", "seed": 7, "defenders": { "count": 1 }, "invaders": { "count": 1 },
}
const ENDLESS := {
	"mode": "endless", "seed": 7, "defenders": { "count": 1 }, "invaders": { "count": 1 },
}
const PLAY := {
	"mode": "play", "side": "invader", "seed": 7, "lead": false,
	"defenders": { "count": 1 }, "invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "The overlay scope is saved per mode and restored",
		"description": "Through Main run whole: a watched match starts on selected, the bar's "
			+ "scope applies at once and is saved under watch only; a fresh launch and an endless "
			+ "run's next match keep it; a played match has its own scope, all at first, saved "
			+ "and restored apart.",
		"tags": ["ui", "overlay", "settings", "endless"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"overlay_scopes", {})
	s.set_static(Settings, &"debug", true)
	s.von_script([])


func run(t: TestContext) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	await _launch_watch(t)
	await _launch_endless(t)
	await _launch_play(t)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## A first launch: the watched match shows nobody, then the side chosen on the bar.
func _launch_watch(t: TestContext) -> void:
	_fresh_process(true)
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var world: Node = await _start(t, main, WATCH)
	if world == null:
		await MainProbe.close(t, viewport)
		return
	t.expect_eq(_shown(world), [], "a watched match starts on selected: nobody shows")
	main.set_overlay_scope("invaders")
	t.expect_eq(_shown(world), ["invader"], "the scope invaders shows the invaders at once")
	t.expect_eq(
		_saved(),
		{ "watch": "invaders" },
		"and is saved under watch, play untouched",
	)
	await MainProbe.close(t, viewport)


## A fresh launch restores the watch scope; an endless run keeps the one chosen into its next match.
func _launch_endless(t: TestContext) -> void:
	_fresh_process(false)
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport, {}, Vector2.ZERO, true)
	main.endless_delay = 0.2
	var world: Node = await _start(t, main, ENDLESS)
	if world == null:
		await MainProbe.close(t, viewport)
		return
	t.expect_eq(_shown(world), ["invader"], "a fresh launch restores the watch scope: invaders")
	main.set_overlay_scope("defenders")
	t.expect_eq(_shown(world), ["household"], "and the bar's new scope shows at once")
	var killed := false
	for npc in _npcs(world):
		if npc.faction == &"household" and not killed:
			npc.take_damage(1.0e9)
			killed = true
	var next: Node = await _await_world(t, main, world.get_instance_id())
	if next == null:
		await MainProbe.close(t, viewport)
		return
	t.expect_eq(_shown(next), ["household"], "the endless run's next match keeps the scope")
	t.expect_eq(
		_saved(),
		{ "watch": "defenders" },
		"and it is the one saved under watch",
	)
	await MainProbe.close(t, viewport)


## A played match is on all at first, whatever the watched scope is, then the one chosen there.
func _launch_play(t: TestContext) -> void:
	_fresh_process(false)
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var world: Node = await _start(t, main, PLAY)
	if world == null:
		await MainProbe.close(t, viewport)
		return
	t.expect_eq(_shown(world), ["household", "invader"], "a played match starts on all")
	main.set_overlay_scope("defenders")
	t.expect_eq(_shown(world), ["household"], "the scope defenders shows the defenders only")
	t.expect_eq(
		_saved(), { "watch": "defenders", "play": "defenders" }, "and is saved under play too",
	)
	await MainProbe.close(t, viewport)

	_fresh_process(false)
	viewport = MainProbe.viewport(t)
	main = MainProbe.open(viewport)
	world = await _start(t, main, PLAY)
	if world == null:
		await MainProbe.close(t, viewport)
		return
	t.expect_eq(_shown(world), ["household"], "the next played match restores the play scope")
	await MainProbe.close(t, viewport)


## Put the statics as a new process finds them (the defaults, Main reads the file as it launches);
## `first` also writes the file with the vision toggle saved on.
func _fresh_process(first: bool) -> void:
	Settings.overlay_scopes = {}
	Settings.overlays = {}
	Settings.setup = {}
	if first:
		Settings.overlays = { "show_vision": true }
		Settings.save()


## The window's Start of `config` on `main`, and the match world it builds (null after a failed
## premise).
func _start(t: TestContext, main: Node, config: Dictionary) -> Node:
	var menu := MainProbe.setup_menu(main)
	if not t.require(menu != null, "premise: Main opened the setup window"):
		return null
	menu.start_requested.emit(config.duplicate(true))
	return await _await_world(t, main, 0)


## The match world Main builds after the one of instance id `previous_id` (0: the first), once its
## NPCs and the overlay bar are in; null after a failed premise.
func _await_world(t: TestContext, main: Node, previous_id: int) -> Node:
	var built := func():
		var world := _world(main)
		return (
			world != null
			and world.get_instance_id() != previous_id
			and _npcs(world).size() >= 2
			and main.get_node_or_null("OverlayToggles") != null
		)
	if not t.require(await t.until(built, 30.0), "premise: Main builds a match"):
		return null
	return _world(main)


## Main's match world (its child in the group `match_world`), or null.
func _world(main: Node) -> Node:
	if not is_instance_valid(main):
		return null
	for child in main.get_children():
		if child.is_in_group(&"match_world"):
			return child
	return null


## The NPCs under `world`: the characters with an AI controller.
func _npcs(world: Node) -> Array:
	return world.get_children().filter(func(c): return (
		c.is_in_group(&"characters") and TestContext.controller_of(c) != null
	))


## The factions with an NPC whose vision overlay is on, sorted.
func _shown(world: Node) -> Array:
	var out: Array = []
	for npc in _npcs(world):
		for child in npc.get_children():
			if "show_vision" in child and bool(child.show_vision) and not out.has(npc.faction):
				out.append(npc.faction)
	var names: Array = out.map(func(f): return String(f))
	names.sort()
	return names


## The scopes the settings file holds, as a new launch would read them.
func _saved() -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SCRATCH)) != OK:
		return {}
	return json.data.get("overlay_scopes", {})
