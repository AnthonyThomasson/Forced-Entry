extends GameTest
## G5: the grenade counts chosen in the setup window are saved with the rest of the setup, and an
## older save that does not name them keeps the defaults (invaders 1 stun + 1 frag, defenders none):
## Main lays what was saved over its defaults side by side. Read off the setup window Main opens,
## Main run whole (`tests/_main/main_probe.gd`) as a fresh launch starts it, through
## `SetupMenu.current_config()`. Runs against a scratch file, never the real one.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_grenades_test.json"


func describe() -> Dictionary:
	return {
		"name": "Saved setups keep the grenade counts, and old ones the defaults",
		"description": "The stun and frag counts a side was set to come back after a reload; a "
			+ "save written before they existed leaves invaders at 1 + 1 and defenders at 0 + 0 "
			+ "while keeping what it did name.",
		"tags": ["settings", "setup", "grenade", "persistence"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", Settings.debug)


func run(t: TestContext) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))  # no save yet
	var defaults := await _window(t)
	if not t.require(not defaults.is_empty(), "Main opened the setup window"):
		return
	t.expect_eq(
		[int(defaults["invaders"]["stuns"]), int(defaults["invaders"]["frags"])],
		[1, 1],
		"the invaders' defaults are 1 stun and 1 frag",
	)
	t.expect_eq(
		[int(defaults["defenders"]["stuns"]), int(defaults["defenders"]["frags"])],
		[0, 0],
		"the defenders' are none",
	)

	# A save from before the grenades: it names the counts of people and guns only.
	_write({
		"setup": {
			"side": "invader",
			"seed": 5,
			"defenders": { "count": 3, "weapon": "smg" },
			"invaders": { "count": 4 },
		},
	})
	var merged := await _window(t)
	t.expect_eq(
		int(merged["invaders"]["count"]),
		4,
		"what the old save names is kept (the invader count)",
	)
	t.expect_eq(str(merged["defenders"]["weapon"]), "smg", "and the defenders' weapon")
	t.expect_eq(
		[int(merged["invaders"]["stuns"]), int(merged["invaders"]["frags"])],
		[1, 1],
		"the invaders keep 1 stun and 1 frag",
	)
	t.expect_eq(
		[int(merged["defenders"]["stuns"]), int(merged["defenders"]["frags"])],
		[0, 0],
		"the defenders keep none",
	)

	# The counts a player chose are saved with the setup and come back.
	Settings.set_setup({
		"mode": "watch",
		"side": "defender",
		"seed": 9,
		"defenders": { "count": 2, "stuns": 3, "frags": 0 },
		"invaders": { "count": 2, "stuns": 0, "frags": 2 },
	})
	Settings.setup = {}
	merged = await _window(t)
	t.expect_eq(
		[int(merged["defenders"]["stuns"]), int(merged["defenders"]["frags"])],
		[3, 0],
		"the defenders' chosen counts come back after a reload",
	)
	t.expect_eq(
		[int(merged["invaders"]["stuns"]), int(merged["invaders"]["frags"])],
		[0, 2],
		"and the invaders' (a chosen 0 is not the default)",
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## Launch Main as a fresh launch does (it loads the settings file and opens the setup window) and
## return the window's choices as they stand ({} when it opened none); Main is freed after.
func _window(t: TestContext) -> Dictionary:
	var main = MainProbe.open(t.world)
	var menu := MainProbe.setup_menu(main)
	var config: Dictionary = menu.current_config() if menu != null else {}
	await MainProbe.close(t, main)
	return config


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
