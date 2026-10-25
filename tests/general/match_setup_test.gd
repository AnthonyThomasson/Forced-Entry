extends GameTest
## A match's setup logic (`MatchBuilder`, and Main's setup window): each side is armed with its own
## loadout, by faction (`MatchBuilder.arm`); an endless run's next match
## (`MatchBuilder.random_spec`) draws counts within the setup's limits and valid loadouts, keeping
## the grenade counts it was set up with; a setup window's per-side config is read into counts and
## loadouts over the base spec (`MatchBuilder.spec_from_setup`); and the window Main opens shows
## each side's count, leaving a spare count Main's defaults do not set to the window's own default.
## The window is read off Main run whole (`tests/_main/main_probe.gd`), through
## `SetupMenu.current_config()`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
## The setup window's own spare-magazine default (its Spares row), shown when Main names none.
const WINDOW_SPARES := 2


func describe() -> Dictionary:
	return {
		"name": "A match arms its sides, randomises endless matches and reads the setup",
		"description": "Each faction gets its side's gun, magazine and spares; endless draws stay "
			+ "within the chosen counts with valid loadouts and the grenades set up; the setup "
			+ "config is read over the base spec; Main's window shows each side's count.",
		"tags": ["setup", "match", "loadout"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.set_static(Settings, "path", "user://test_match_setup_settings.json")
	s.set_static(Settings, "setup", {})
	s.set_static(Settings, "overlays", {})
	s.set_static(Settings, "debug", Settings.debug)
	s.actor(&"home", &"puppet", Vector2(200, 250), { "faction": &"household" })
	s.actor(&"raider", &"puppet", Vector2(600, 250), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var home := t.actor(&"home")
	var raider := t.actor(&"raider")
	MatchBuilder.arm([home, raider], MatchBuilder.spec({
		"seed": 99,
		"defenders": { "loadout": { "weapon": &"smg", "magazine": &"smg_extended", "spares": 3 } },
		"invaders": { "loadout": { "weapon": &"rifle" } },
	}))
	t.expect_eq(
		home.current_slot(),
		int(GunConfig.row(&"smg")["slot"]),
		"the defender holds the SMG",
	)
	t.expect_eq(
		home.ammo.rounds(),
		MagazineConfig.capacity_of(&"smg_extended"),
		"loaded with the extended magazine",
	)
	t.expect_eq(home.ammo.spare_magazines(), 3, "and carries three spares")
	t.expect_eq(
		raider.current_slot(),
		int(GunConfig.row(&"rifle")["slot"]),
		"the invader holds the rifle",
	)
	t.expect_eq(
		raider.ammo.spare_magazines(),
		int(GunConfig.row(&"rifle")["spare_magazines"]),
		"with the rifle's own spares",
	)

	_check_endless(t)
	_check_setup_config(t)
	await _check_window(t)


## The endless run's next match: an empty side stays empty, a drawn count is within 1..its setup
## count, the seed is a fresh one and each side's loadout is valid, with the grenades it was set up
## with.
func _check_endless(t: TestContext) -> void:
	var base := MatchBuilder.spec({
		"seed": 7,
		"defenders": { "loadout": { "stuns": 2, "frags": 0 } },
		"invaders": { "loadout": { "stuns": 0, "frags": 3 } },
	})
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 50:
		var drawn := MatchBuilder.random_spec(rng, base, { "defenders": 0, "invaders": 3 })
		var n := int(drawn["invaders"]["count"])
		t.check(n >= 1 and n <= 3, "a drawn count is within 1..3 (%d)" % n)
		if not t.check(
				int(drawn["defenders"]["count"]) == 0,
				"an empty side stays empty (%d)" % int(drawn["defenders"]["count"]),
		):
			break

	var next := MatchBuilder.random_spec(rng, base, { "defenders": 3, "invaders": 0 })
	t.check(
		int(next["defenders"]["count"]) >= 1 and int(next["defenders"]["count"]) <= 3,
		"endless defenders are within the chosen count (%d)" % int(next["defenders"]["count"]),
	)
	t.expect_eq(int(next["invaders"]["count"]), 0, "endless invaders stay at zero")
	t.expect_eq(int(next["seed"]), 0, "endless asks for a fresh seed")
	for side in ["defenders", "invaders"]:
		var loadout: Dictionary = next[side]["loadout"]
		t.expect_eq(loadout, LoadoutConfig.normalize(loadout), "the %s' loadout is valid" % side)
	t.expect_eq(
		LoadoutConfig.grenade_counts(next["defenders"]["loadout"]),
		{ "stuns": 2, "frags": 0 },
		"the defenders keep the grenades they were set up with",
	)
	t.expect_eq(
		LoadoutConfig.grenade_counts(next["invaders"]["loadout"]),
		{ "stuns": 0, "frags": 3 },
		"and the invaders theirs",
	)


## The setup window's config read over a base spec: a side it leaves out keeps the base's count, a
## side's count is read, and a side's loadout keys are laid over the base's loadout.
func _check_setup_config(t: TestContext) -> void:
	var base := MatchBuilder.spec({
		"defenders": { "count": 1, "loadout": {} },
		"invaders": { "count": 4 },
	})
	t.expect_eq(
		int(MatchBuilder.spec_from_setup({}, base)["defenders"]["count"]),
		1,
		"a side the config leaves out keeps the base's count",
	)
	var read := MatchBuilder.spec_from_setup(
		{ "defenders": { "count": 2, "weapon": "pistol", "spares": 1 } },
		base,
	)
	t.expect_eq(int(read["defenders"]["count"]), 2, "a side dict's count is read")
	t.expect_eq(
		read["defenders"]["loadout"],
		{ "weapon": "pistol", "spares": 1 },
		"a side dict's loadout keys are kept",
	)
	t.expect_eq(int(read["invaders"]["count"]), 4, "and the other side keeps the base's count")


## The window Main opens: each side's count is Main's, and a spare count Main's defaults leave unset
## is the window's own default.
func _check_window(t: TestContext) -> void:
	var main = MainProbe.open(t.world, { "defender_count": 2, "invader_count": 3 })
	var menu := MainProbe.setup_menu(main)
	var config: Dictionary = menu.current_config() if menu != null else {}
	if t.require(not config.is_empty(), "Main opened the setup window"):
		t.expect_eq(
			int(config["defenders"]["count"]),
			2,
			"the window shows the defenders' count",
		)
		t.expect_eq(int(config["invaders"]["count"]), 3, "and the invaders'")
		t.expect_eq(
			int(config["defenders"].get("spares", -1)),
			WINDOW_SPARES,
			"an unset spare count is left to the window's default",
		)
	await MainProbe.close(t, main)
