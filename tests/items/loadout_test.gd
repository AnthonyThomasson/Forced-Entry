extends GameTest
## LoadoutConfig arms a character through Character.set_loadout: only the chosen gun (plus hands,
## fists and key), the chosen magazine and spare count; "random" draws a gun; the choices come from
## GunConfig.


func describe() -> Dictionary:
	return {
		"name": "Loadouts arm the right gun",
		"description": "A chosen gun is carried alone with its extended magazine and spares; "
			+ "random draws a real gun; the options list every gun with only its own magazines; "
			+ "random loadouts are always valid.",
		"tags": ["item", "loadout", "setup"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"gunman", &"puppet", Vector2(200, 250))
	s.actor(&"lottery", &"puppet", Vector2(200, 400))


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_check_named_gun(t, rng)
	_check_random_gun(t, rng)
	_check_fallbacks(t)
	_check_options(t)
	_check_random_loadouts(t, rng)


## A loadout naming the SMG, its extended magazine and three spares arms the gunman with them.
func _check_named_gun(t: TestContext, rng: RandomNumberGenerator) -> void:
	var gunman := t.actor(&"gunman")
	var armed := LoadoutConfig.apply(
		gunman,
		{ "weapon": &"smg", "magazine": &"smg_extended", "spares": 3 },
		rng,
	)
	t.expect_eq(armed, &"smg", "the SMG was chosen")
	t.expect_eq(gunman.current_slot(), int(GunConfig.row(&"smg")["slot"]), "and is held")
	t.check(not gunman.has_item(int(GunConfig.row(&"pistol")["slot"])), "no other gun is carried")
	t.expect_eq(
		gunman.ammo(),
		MagazineConfig.capacity_of(&"smg_extended"),
		"it is loaded with the extended magazine",
	)
	t.expect_eq(gunman.spare_magazines(), 3, "three spares are carried")


## A random weapon draws a real gun, with that gun's own spares.
func _check_random_gun(t: TestContext, rng: RandomNumberGenerator) -> void:
	var lottery := t.actor(&"lottery")
	var drawn := LoadoutConfig.apply(lottery, { "weapon": LoadoutConfig.RANDOM }, rng)
	t.check(not GunConfig.row(drawn).is_empty(), "random draws a real gun (%s)" % drawn)
	t.expect_eq(
		lottery.spare_magazines(),
		int(GunConfig.row(drawn)["spare_magazines"]),
		"with that gun's own spares",
	)


## Blank or unknown choices fall back to random; spares are capped.
func _check_fallbacks(t: TestContext) -> void:
	t.expect_eq(
		LoadoutConfig.normalize({ "weapon": &"nonsense" })["weapon"],
		LoadoutConfig.RANDOM,
		"an unknown weapon is random",
	)
	t.expect_eq(
		LoadoutConfig.normalize({ "weapon": &"pistol", "spares": 99 })["spares"],
		LoadoutConfig.max_spares,
		"spares are capped",
	)


## options(): Random first, then every gun, each with only its own gun's magazines (its own
## listed first).
func _check_options(t: TestContext) -> void:
	var options := LoadoutConfig.options()
	t.expect_eq(options[0]["id"], LoadoutConfig.RANDOM, "Random is listed first")
	t.expect_eq(options.size(), GunConfig.guns.size() + 1, "every gun is offered")
	for option in options.slice(1):
		var gun: StringName = option["id"]
		t.check(not option["magazines"].is_empty(), "%s offers magazines" % gun)
		t.expect_eq(
			option["magazines"][0]["id"],
			StringName(GunConfig.row(gun)["magazine"]),
			"%s lists its own magazine first" % gun,
		)
		for m in option["magazines"]:
			t.expect_eq(
				MagazineConfig.types[m["id"]]["gun"],
				gun,
				"%s only offers its own magazines" % gun,
			)


## Every random loadout is a valid one, naming a real gun.
func _check_random_loadouts(t: TestContext, rng: RandomNumberGenerator) -> void:
	for i in 40:
		var pick := LoadoutConfig.random(rng)
		t.check(
			pick["weapon"] != LoadoutConfig.RANDOM and pick == LoadoutConfig.normalize(pick),
			"a random loadout is valid (%s)" % pick,
		)
