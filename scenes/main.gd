extends Node2D
## Top-down demo scene and the game's composition root (with the test runner, the only code that
## knows every domain). It keeps the UI flow (the setup window, the settings page, the endless run,
## the HUDs and the overlay bar) and starts each match through `start_match`, which builds it with
## the match builder (`MatchBuilder`).

## Spectator inspector (UI): Space-pause + click an NPC to show its tactical zones.
const SPECTATOR_INSPECTOR := preload("res://scenes/ui/hud/spectator_inspector.gd")
## The floor markers of the human's place in an AI stack (world space, under `World`).
const STACK_MARKERS := preload("res://scenes/ui/hud/stack_markers.gd")
## The human leader's command menu (UI, a right-click pauses and orders the teammates) and the order
## markers on the floor (world space, under `World`), built only when the human leads
## (`docs/leadership.md` LD11, LD12).
const COMMAND_MENU := preload("res://scenes/ui/hud/command_menu.gd")
const ORDER_MARKERS := preload("res://scenes/ui/hud/order_markers.gd")
const STUN_SCREEN := preload("res://scenes/ui/hud/stun_screen.gd")
## The overlay table (UI) and the in-game bar of toggle buttons built from it.
const OVERLAY_REGISTRY := preload("res://scenes/ui/overlays/overlay_registry.gd")
const OVERLAY_TOGGLES := preload("res://scenes/ui/overlays/overlay_toggles.gd")
## The test browser scene (Testing domain), opened from the setup window's Tests button.
const TEST_BROWSER := "res://scenes/testing/test_browser.tscn"
## The settings page (UI), opened over the setup window by its Settings button.
const SETTINGS_MENU := preload("res://scenes/ui/menus/settings_menu.gd")
## The endless run's state (`_endless`) and the debug overlays' state, nodes and routing
## (`_overlays`), parts built once with Main.
const MainEndless := preload("res://scenes/main_endless.gd")
const MainOverlays := preload("res://scenes/main_overlays.gd")

## The run's authoring knobs: the base match spec's (seed, floorplan, entrance, counts, placement
## clearances) and the mode's defaults (spectator, the human's side, Debug), a `MainRun` per Main.
@export var run: MainRun = MainRun.new()
## Endless run: seconds between a match ending and the next one starting.
@export var endless_delay: float = 5.0
## Endless run: seconds before an undecided match is called a draw, so a stalemate can't stall the
## run (0 = no limit).
@export var endless_time_limit: float = 180.0

## Where the player stood in the scene: the house is placed relative to this point (its front
## entrance just above), and an invading human starts here.
var _anchor: Vector2 = Vector2.ZERO
## Everything one match builds (house, nav map, NPCs, inspector, and the blood / debris they leave)
## lives under this node, so an endless run clears a match by freeing it.
var _world: Node2D = null
## This match's human (the spec's `human` node), null in a spectator match.
var _human: Node2D = null
## This match's handle (`MatchBuilder.build`'s): its world, house, rooms, doorways, combatants,
## squads (by faction), the human's stack radio and the navigation-holes and squad-leaders
## overlays; {} between matches.
var _match: Dictionary = {}
## The settings page while it is open over the setup window, else null.
var _settings_menu: CanvasLayer = null
## The endless run: on or not, the spec it draws from, its highest counts and its countdown.
var _endless := MainEndless.new()
## The debug overlays: their flags, the performance overlay, the toggle bar and the inspector a
## toggle reaches.
var _overlays := MainOverlays.new(self)

## The human player (freed in a spectator match).
@onready var _player: Node2D = $Player
## Pre-game setup window (General). On a fresh launch Main opens it and waits for Start before
## building the world; a scripted restart skips it (see `_ready`).
@onready var _setup_menu: CanvasLayer = $SetupMenu
## Dev-only Von server launcher (AI). The match start waits on it so no NPC decides against a cold
## server; absent (or resolved to "none coming") it imposes no delay.
@onready var _von_launcher: Node = get_node_or_null("DecisionServerLauncher")
## The match HUD (UI): the timer, the verdict and the endless run's countdown; null in a Main built
## without it.
@onready var _match_hud: CanvasLayer = get_node_or_null("MatchHUD")


func _ready() -> void:
	# The saved settings (key bindings, Debug) are layered over the defaults here, in the
	# composition root, so the headless test runner never reads a developer's file. The run's Debug
	# export seeds the setting first, so a file that doesn't name it leaves the export standing.
	Settings.debug = run.debug_overlays
	Settings.load_file()
	_overlays.initial(run.debug_overlays)
	_anchor = _player.global_position
	if _match_hud and _match_hud.has_signal("match_ended"):
		_match_hud.match_ended.connect(_on_match_ended)
	# A scripted restart (the dev command server's `restart`) sets `skip_setup` so a reloaded scene
	# builds immediately — the headless match harness never clicks the setup window. A fresh launch
	# opens the window first and builds the world once the player presses Start.
	if Engine.has_meta("skip_setup") or _setup_menu == null:
		_play(_base_spec())
	else:
		# Hide the debug overlay while the setup menu is shown so it doesn't bleed through.
		var _debug_ui := get_node_or_null("DebugUI")
		if _debug_ui:
			_debug_ui.visible = false
		_setup_menu.start_requested.connect(_on_setup_chosen)
		_setup_menu.tests_requested.connect(_open_tests)
		_setup_menu.settings_requested.connect(_open_settings)
		# The run's exports and the match spec's loadouts are the defaults; what the player chose
		# last time (kept in the settings file) wins.
		var base := _base_spec()
		var defaults := {
			"side": str(run.player_side),
			"seed": run.house_seed,
			"defenders": _side_defaults(base["defenders"]),
			"invaders": _side_defaults(base["invaders"]),
		}
		_setup_menu.open(_with_saved_setup(defaults).merged({
			"weapons": LoadoutConfig.options(),
			"grenades": LoadoutConfig.grenade_options(),
			"outfits": LoadoutConfig.outfit_options(),
			"ticket": _ticket(),
		}))


## Escape returns to the setup window to start a fresh match. Routed through Keybinds like all
## input, and handled here (not in a controller) so it works in both player and spectator mode — the
## dev command server's `menu` verb calls the same `return_to_setup()`.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(Keybinds.MENU) and not event.is_echo():
		return_to_setup()


## Endless run: tick the countdown (Main is pausable, so pausing the match pauses it), then replace
## the finished match with a fresh randomised one.
func _process(delta: float) -> void:
	if not _endless.tick(delta):
		if _endless.next_match_in > 0.0 and _match_hud:
			_match_hud.set_countdown(
				"Next match in %d...  (Esc to stop)" % ceili(_endless.next_match_in),
			)
		return
	if _match_hud:
		_match_hud.set_countdown("")
	_teardown_world()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_play(MatchBuilder.random_spec(rng, _endless.spec, _endless.most))


## The name this run is tagged with: the `GAME_TICKET` env var (`tools/editor.sh` sets it to the
## worktree name), else a `--ticket=<name>` user arg, else the worktree's directory name when run
## from the editor; blank in an exported build. The setup window shows it at the top.
func _ticket() -> String:
	var ticket := OS.get_environment("GAME_TICKET")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ticket="):
			ticket = arg.trim_prefix("--ticket=")
	if ticket.strip_edges().is_empty() and OS.has_feature("editor"):
		ticket = ProjectSettings.globalize_path("res://").trim_suffix("/").get_file()
	return ticket.strip_edges()


## The setup window's `defaults` with what the player chose last time (kept in the settings file)
## over them, side by side: a choice an older save does not name (the grenade counts, the outfit)
## keeps its default.
func _with_saved_setup(defaults: Dictionary) -> Dictionary:
	var out := defaults.merged(Settings.setup, true)
	for side in ["defenders", "invaders"]:
		if defaults[side] is Dictionary and Settings.setup.get(side) is Dictionary:
			out[side] = defaults[side].merged(Settings.setup[side], true)
	return out


## A side's setup-window defaults: `{ count, weapon, magazine, spares, stuns, frags, outfit }` from
## the side of a match spec (`{ count, loadout }`).
func _side_defaults(side: Dictionary) -> Dictionary:
	var out := LoadoutConfig.normalize(side["loadout"]).merged({ "count": int(side["count"]) })
	if out["spares"] < 0:
		out.erase("spares")  # unset: the window shows its own default
	return out


## Apply the parameters chosen in the setup window, then start the match. The window's `mode` is
## "play" (a human takes `side`), "watch" (the AIs alone: the spectator contest) or "endless"
## (watch, then a fresh randomised match after each one ends); anything but "play" has no human
## player. The config is read into a match spec over the run's (`MatchBuilder.spec_from_setup`).
func _on_setup_chosen(config: Dictionary) -> void:
	Settings.set_setup(config)
	var mode := str(config.get("mode", "play" if not run.spectator_mode else "watch"))
	run.spectator_mode = mode != "play"
	_endless.on = mode == "endless"
	var spec := MatchBuilder.spec_from_setup(config.merged({ "mode": mode }, true), _base_spec())
	if _endless.on:
		_endless.most = {
			"defenders": int(spec["defenders"]["count"]),
			"invaders": int(spec["invaders"]["count"]),
		}
	run.debug_overlays = Settings.debug
	_overlays.initial(run.debug_overlays)  # Recomputed now that the master switch is chosen.
	# Hold the start until the decision server is live, so the NPCs' first decisions don't fail
	# against a booting server and leave them holding steady. The window stays up (showing why)
	# until then; this returns immediately when a server is already up or none is coming.
	await _await_decision_server()
	if not is_inside_tree():
		return  # Escape returned us to setup (reloading the scene) while we were waiting.
	_setup_menu.queue_free()
	var _debug_ui := get_node_or_null("DebugUI")
	if _debug_ui:
		_debug_ui.visible = true  # restored here; _setup_spectator frees it in spectator mode
	_play(spec)


## Save the setup window's choices as they stand, if it is open, so leaving it without starting (to
## the test browser, or Escape reloading the scene) doesn't lose them.
func _remember_setup() -> void:
	if not is_instance_valid(_setup_menu) or _setup_menu.is_queued_for_deletion():
		return
	var config: Dictionary = _setup_menu.current_config()
	if not config.is_empty():  # empty = a scripted restart that never opened the window
		Settings.set_setup(config)


## The setup window's Tests button: leave for the test browser (Testing domain), which plays single
## game tests and returns here on Back.
func _open_tests() -> void:
	_remember_setup()
	get_tree().change_scene_to_file(TEST_BROWSER)


## The setup window's Settings button: open the settings page over it. The page only reports what
## the player changed; each change goes to `Settings` (which saves it) and the page's rows are
## redrawn from it.
func _open_settings() -> void:
	if _settings_menu != null:
		return
	_settings_menu = SETTINGS_MENU.new()
	add_child(_settings_menu)
	_settings_menu.debug_changed.connect(Settings.set_debug)
	_settings_menu.rebind_requested.connect(_on_rebind_requested)
	_settings_menu.reset_requested.connect(_on_reset_requested)
	_settings_menu.reset_all_requested.connect(_on_reset_all_requested)
	_settings_menu.back_requested.connect(_close_settings)
	_settings_menu.open({ "debug": Settings.debug, "rows": Settings.binding_rows() })


## The page captured a key or button for `action`: bind it and redraw the page.
func _on_rebind_requested(action: String, event: InputEvent) -> void:
	if Settings.rebind(action, event):
		_settings_menu.set_rows(Settings.binding_rows())


## The page reset one action: restore its default and redraw.
func _on_reset_requested(action: String) -> void:
	Settings.reset(action)
	_settings_menu.set_rows(Settings.binding_rows())


## The page reset every key: restore all defaults and redraw.
func _on_reset_all_requested() -> void:
	Settings.reset_all()
	_settings_menu.set_rows(Settings.binding_rows())


## Close the settings page, back to the setup window.
func _close_settings() -> void:
	_settings_menu.queue_free()
	_settings_menu = null


## Wait for the Von decision server to settle before the world is built. Returns at once when the
## launcher has already resolved — a reused server, or none coming (exported build, blank von_path,
## timeout) — so the usual case adds no delay at all. The launcher guarantees it always resolves, so
## this cannot stall the setup window indefinitely; a run without a server still starts, just with
## NPCs that hold steady.
func _await_decision_server() -> void:
	if (_von_launcher == null
			or not _von_launcher.has_method("is_resolved")
			or _von_launcher.is_resolved()):
		return
	if _setup_menu != null and _setup_menu.has_method("set_status"):
		_setup_menu.set_status("Waiting for the decision server…")
	var live: bool = await _von_launcher.resolved
	if not live:
		push_warning(
			"Starting without a decision server — NPCs will hold steady until one answers.",
		)


## Reopen the pre-game setup window for a fresh match: drop the `skip_setup` and `match_seed` metas
## a scripted restart may have set (so the reloaded scene shows the window again and the window's
## own seed choice — not a stale pin — decides the layout) and reload the scene. Also the `menu`
## command verb.
func return_to_setup() -> void:
	_remember_setup()
	if Engine.has_meta("skip_setup"):
		Engine.remove_meta("skip_setup")
	if Engine.has_meta("match_seed"):
		Engine.remove_meta("match_seed")
	get_tree().reload_current_scene()


## Main's one way into a match (a coroutine: await it): `MatchBuilder.build` of `spec`
## (`MatchBuilder.spec` overrides) under a fresh `World` node, so `_teardown_world` can clear it,
## its overlays Main's own flags in place of the spec's. Then the UI over the handle: for the spec's
## human the stack markers, the stun screen and, when it leads, the command menu and order markers;
## the match HUD, for a match with no human the spectator inspector, and the overlay bar. The
## scene's own `Player` goes when the human is another character. Returns the match handle, or {}
## when the match was torn down while it was built.
func start_match(spec: Dictionary) -> Dictionary:
	spec = MatchBuilder.spec(spec)
	spec["overlays"] = _overlays.flags.duplicate()
	var world := Node2D.new()
	world.name = "World"
	world.add_to_group(&"match_world")  # how the dev command server finds the match's nodes
	add_child(world)
	_world = world
	var built: Dictionary = await MatchBuilder.build(spec, world)
	if _world != world or not is_inside_tree() or built.is_empty():
		return {}  # torn down (a new match, or the scene left) while the maps synchronized
	_match = built
	var human: Variant = (spec["human"] as Dictionary).get("node")
	_human = human if is_instance_valid(human) else null
	var combatants: Array = built["combatants"]
	if _human != null:
		_build_markers()
		_build_stun_screen()
		if _human != _player and is_instance_valid(_player):
			_player.queue_free()
	_watch_side_stacks()
	if _human != null and bool(spec["human"].get("lead", false)):
		_build_command_menu(built["rooms"])
	_begin_match_hud(combatants)
	if _human == null:
		_setup_spectator(combatants)
	_overlays.build(run.debug_overlays)
	return built


## Start the match of `spec` as the setup flow does: the seed a dev/headless harness pins (the
## Engine `match_seed` meta, which survives the scene reload the `restart` command does) wins, and 0
## is resolved to a fresh random seed here, so the whole run (house and NPC placement) reproduces
## from it and it can be displayed and re-entered to pin this layout; then `start_match`.
func _play(spec: Dictionary) -> void:
	spec = spec.duplicate()
	if Engine.has_meta("match_seed"):
		spec["seed"] = int(Engine.get_meta("match_seed"))
	if int(spec["seed"]) == 0:
		spec["seed"] = randi()
	_endless.spec = spec
	await start_match(spec)


## The match spec Main's `run` names (`MatchBuilder.spec`, whose defaults hold each side's
## loadout): the house seed and floorplan, the front entrance `run.entrance_distance` above the
## player's anchor, each side's count, the human (in a played match: the player, on
## `run.player_side`) and the placement clearances.
func _base_spec() -> Dictionary:
	var human := {}
	if not run.spectator_mode and is_instance_valid(_player):
		human = { "node": _player, "side": run.player_side, "lead": false }
	return MatchBuilder.spec({
		"seed": run.house_seed,
		"plan": run.force_plan,
		"entrance": _anchor + Vector2(0, -run.entrance_distance),
		"defenders": { "count": run.defender_count },
		"invaders": { "count": run.invader_count },
		"human": human,
		"spawn_clearance": run.spawn_clearance,
		"invader_margin": run.invader_margin,
	})


## The stack markers (a played match) watch the human's side's squad too, so every stack that side
## forms shows its rings (LD18).
func _watch_side_stacks() -> void:
	var markers := _world.get_node_or_null("StackMarkers")
	var squad: Node = _squads().get(_human.get("faction")) if _human != null else null
	if markers != null and squad != null:
		markers.watch_squad(squad.view)


## When the human leads its squad (interface 21, `docs/leadership.md` LD11, LD12): the command menu,
## set up with the house's `rooms`, the human's teammates, the squad's `view()` and `resolve()` and,
## with Debug on, the overlay bar's column to keep clear of (`right_clear`, as the inspector's), its
## `order_requested` handed to the squad's `issue`; and the order markers under `World`, watching
## the same view and showing the menu's selection. Nothing is built, and nothing reads the COMMAND
## key, otherwise.
func _build_command_menu(rooms: Array) -> void:
	var squad: Node = _squads().get(_human.get("faction"))
	if squad == null or squad.leader() != _human:
		return
	var markers: Node2D = ORDER_MARKERS.new()
	markers.name = "OrderMarkers"
	_world.add_child(markers)
	markers.watch(squad.view)
	var menu: CanvasLayer = COMMAND_MENU.new()
	menu.name = "CommandMenu"
	_world.add_child(menu)
	menu.setup({
		"rooms": rooms,
		"teammates": squad.members().filter(func(m): return m != _human),
		"view": squad.view,
		"resolve": squad.resolve,
		"leader": _human,
		"right_clear": OVERLAY_TOGGLES.RESERVED_WIDTH if run.debug_overlays else 0.0,
	})
	menu.order_requested.connect(squad.issue)
	menu.selection_changed.connect(markers.set_selection)


## This match's squads (`ai/team/squad.gd`), by faction; {} between matches.
func _squads() -> Dictionary:
	return _match.get("squads", {})


## Free the match built by `start_match`: the whole `World` node (house, nav map, NPCs, inspector,
## and any blood / debris / casings they left) goes, and the bookkeeping that pointed into it is
## cleared. Removed from the tree at once (not just queued) so the next match's `World` takes the
## same name.
func _teardown_world() -> void:
	if is_instance_valid(_world):
		remove_child(_world)
		_world.queue_free()
	_world = null
	Sound.focus = null  # nobody's ears until the next match names the human
	_match = {}
	_human = null
	_overlays.inspector = null


## Start the match HUD on `combatants` (every character in the match, a human included, so a result
## is shown whichever way the match is played). An endless run gives it a time limit.
func _begin_match_hud(combatants: Array) -> void:
	if _match_hud and _match_hud.has_method("begin"):
		_match_hud.begin(combatants, endless_time_limit if _endless.on else 0.0)


## Turn the scene into a pure AI spectator match: drop the human player and its player-HUD, point
## the camera at the NPCs, and add the Space-pause / click-to-inspect inspector. Composition-root
## wiring only — each observer reads the characters' public API/signals, never their internals.
func _setup_spectator(combatants: Array) -> void:
	var cam := get_node_or_null("MainCamera")
	if cam and cam.has_method("frame"):
		cam.frame(combatants)
	# Space pauses the match; a click selects one NPC (showing only its enabled overlays) and a
	# click on one of its tactical points shows that point's details. Spectator-only (in player mode
	# Space is the player's INTERACT), so it is wired here, not on a gameplay node. It is handed the
	# same overlay toggles the setup menu chose, and reveals exactly those on the clicked NPC.
	var inspector := SPECTATOR_INSPECTOR.new()
	inspector.name = "SpectatorInspector"
	_world.add_child(inspector)
	_overlays.inspector = inspector
	var npc_flags := _overlays.flags.duplicate()
	for flag in OVERLAY_REGISTRY.GLOBAL:  # global overlays, not per NPC
		npc_flags.erase(flag)
	# its outfit panel keeps clear of the bar's column
	inspector.setup(combatants, npc_flags, OVERLAY_TOGGLES.RESERVED_WIDTH)
	var debug := get_node_or_null("DebugUI")
	if debug:
		debug.queue_free()
	if is_instance_valid(_player):
		_player.queue_free()


## Draw the human's place in an AI stack on the floor: the markers (a child of `World`, so world
## space) watch the human's stack radio. Only a human invader is ever reserved a slot, since only
## the invaders' entries come over the radio.
func _build_markers() -> void:
	var markers: Node2D = STACK_MARKERS.new()
	markers.name = "StackMarkers"
	_world.add_child(markers)
	markers.watch(_match["player_stack"])


## The human's stun: the white-out of a flash (a `CanvasLayer` under `World`, watching the human)
## and, through `Sound.focus`, the muffle and tinnitus of a bang. Both read the human's
## `stun.view()`; neither knows of the other.
func _build_stun_screen() -> void:
	Sound.focus = _human
	var screen: CanvasLayer = STUN_SCREEN.new()
	_world.add_child(screen)
	screen.watch(_human)


## The match HUD decided the match. In an endless run, start the countdown to the next one.
func _on_match_ended(_verdict: String) -> void:
	_endless.ended(endless_delay)


## Turn the debug overlay `flag` (a row of `overlay_registry.gd`) on or off, as the toggle bar's
## buttons do: record and save it, and apply it live (`_overlays.route`: the performance overlay,
## the spectator inspector, or the match by the one rule).
func set_overlay(flag: String, on: bool) -> void:
	_overlays.flags[flag] = on
	Settings.set_overlay(flag, on)
	_overlays.route(flag, on, _match)
