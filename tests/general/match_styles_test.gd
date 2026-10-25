extends GameTest
## R2 and R3's arming (ticket #61): a match's crew is armed from the match seed (`MatchBuilder.arm`,
## as Main's match arms it, over the spec's `seed` and each side's loadout), and the styles come
## with the arms:
## - R2: every invader, the human invader too, wears one police unit (`CharacterWardrobe.style`
##   `zenitex` or `trauma`), the same for every invader of a match; the unit is drawn from the seed
##   (re-arming with the same seed gives the same one, and across seeds both units come up). Each
##   defender is seeded to `merc` or `borg` (both in a crew of twelve) and to a look seed of its
##   own.
## - R3 (`LoadoutConfig.apply` hands each item the wielder's weapon style): an invader's gun and
##   grenades are `police` issue; a defender's are `scrap` or `pipe`, one style for all it carries,
##   and both come up across the crew.
## - The unit's ranks (`docs/outfits.md`, styles): its first invader is the lead
##   (`CharacterWardrobe.rank` 2), the second the sergeant (1), the rest troopers (0); a defender
##   has no rank.
## Read through `CharacterWardrobe.style` / `look_seed` / `rank` and each carried gun's and
## grenade's `Item.style`.

const DEFENDERS := 12
const INVADERS := 4
const SEED := 61
## Seeds the unit is drawn for (both units must come up).
const UNIT_SEEDS := 24
const UNITS := [&"zenitex", &"trauma"]
const DEFENDER_STYLES := [&"merc", &"borg"]
const DEFENDER_WEAPONS := [&"scrap", &"pipe"]
const INVADER_WEAPON := &"police"
## Both sides carry a gun and a grenade of each kind, so every kind of item is checked.
const DEFENDER_LOADOUT := { "weapon": &"pistol", "stuns": 1, "frags": 1 }
const INVADER_LOADOUT := { "weapon": &"rifle", "stuns": 1, "frags": 1 }
## The invaders' ranks in the order they are armed: the lead, the sergeant, then troopers (the human
## last).
const INVADER_RANKS := [2, 1, 0, 0, 0]


func describe() -> Dictionary:
	return {
		"name": "A match's invaders share a police unit, its defenders mix merc and borg",
		"description": "A match arms its crew from the seed: every invader (and the human) gets "
			+ "one unit, drawn from the seed; defenders are seeded merc or borg; every gun and "
			+ "grenade carries its wielder's weapon style.",
		"tags": ["style", "match", "loadout", "setup"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	for i in DEFENDERS:
		s.actor(
			_defender(i),
			&"puppet",
			Vector2(100 + (i % 6) * 110, 100 + floori(i / 6.0) * 90),
			{ "faction": MatchBuilder.DEFENDER_FACTION },
		)
	for i in INVADERS:
		s.actor(
			_invader(i),
			&"puppet",
			Vector2(100 + i * 110, 320),
			{ "faction": MatchBuilder.INVADER_FACTION },
		)
	# The human invader: the player's own character and controller, joined to the invaders' side as
	# Main joins it.
	s.actor(&"human", &"player", Vector2(600, 400), { "faction": MatchBuilder.INVADER_FACTION })


func run(t: TestContext) -> void:
	var defenders: Array = []
	for i in DEFENDERS:
		defenders.append(t.actor(_defender(i)))
	var invaders: Array = []
	for i in INVADERS:
		invaders.append(t.actor(_invader(i)))
	invaders.append(t.actor(&"human"))
	MatchBuilder.arm(defenders + invaders, _spec(SEED))
	var unit: StringName = invaders[0].wardrobe.style
	t.check(
		unit in UNITS,
		"the first invader wears a police unit, zenitex or trauma (got %s)" % [unit],
	)
	for c: Node in invaders:
		t.expect_eq(c.wardrobe.style, unit, "%s wears the match's unit" % c.name)
		_check_items(t, c, [INVADER_WEAPON])
	_check_ranks(t, invaders, defenders, "armed")
	var styles := _check_defenders(t, defenders)
	_check_reseeded(t, invaders, defenders, unit, styles)
	_check_units(t, invaders)


## Each of the armed `defenders` is seeded merc or borg with a look seed of its own, carrying
## defender weapons; the crew has both styles and both weapon styles among it. Returns each
## defender's style.
func _check_defenders(t: TestContext, defenders: Array) -> Dictionary:
	var styles := {}  # defender -> its style
	var weapons := {}  # weapon style -> true
	var seeds := {}  # look seed -> true
	for c: Node in defenders:
		var style: StringName = c.wardrobe.style
		styles[c] = style
		t.check(style in DEFENDER_STYLES, "%s is seeded merc or borg (got %s)" % [c.name, style])
		var weapon: Variant = _check_items(t, c, DEFENDER_WEAPONS)
		if weapon != null:
			weapons[weapon] = true
		seeds[c.wardrobe.look_seed] = true
	for style in DEFENDER_STYLES:
		t.check(
			styles.values().has(style),
			"a crew of %d defenders has a %s among it" % [DEFENDERS, style],
		)
	for weapon in DEFENDER_WEAPONS:
		t.check(
			weapons.has(weapon),
			"a crew of %d defenders carries %s weapons among it" % [DEFENDERS, weapon],
		)
	t.check(
		seeds.size() == DEFENDERS,
		"each defender has a look seed of its own (%d distinct of %d)" % [seeds.size(), DEFENDERS],
	)
	return styles


## Drawn from the seed: the same seed arms the same way (the invaders' `unit`, each defender's
## style in `styles`, the ranks).
func _check_reseeded(
	t: TestContext,
	invaders: Array,
	defenders: Array,
	unit: StringName,
	styles: Dictionary,
) -> void:
	MatchBuilder.arm(defenders + invaders, _spec(SEED))
	t.expect_eq(
		invaders[0].wardrobe.style,
		unit,
		"re-armed with the same seed, the invaders wear the same unit",
	)
	for c: Node in defenders:
		t.expect_eq(
			c.wardrobe.style,
			styles[c],
			"re-armed with the same seed, %s keeps its style" % c.name,
		)
	_check_ranks(t, invaders, defenders, "re-armed")


## Across seeds both units come up, one per match, worn by all the `invaders`.
func _check_units(t: TestContext, invaders: Array) -> void:
	var units := {}
	for s in range(1, UNIT_SEEDS + 1):
		MatchBuilder.arm(invaders, _spec(s))
		var drawn: StringName = invaders[0].wardrobe.style
		units[drawn] = true
		for c: Node in invaders:
			var got: StringName = c.wardrobe.style
			if not t.check(
					got == drawn,
					"seed %d: %s wears the match's unit %s (got %s)" % [s, c.name, drawn, got],
			):
				break
	for u in UNITS:
		t.check(
			units.has(u),
			"across %d seeds, the invaders are %s in some match (units drawn: %s)"
				% [UNIT_SEEDS, u, units.keys()],
		)


## The match spec the crew is armed by: the match seed `seed_value` and both sides' loadouts.
func _spec(seed_value: int) -> Dictionary:
	return MatchBuilder.spec({
		"seed": seed_value,
		"defenders": { "loadout": DEFENDER_LOADOUT },
		"invaders": { "loadout": INVADER_LOADOUT },
	})


## Check the ranks: the invaders' (in the order they were armed) are `INVADER_RANKS`, every
## defender's 0; `when` names the arming.
func _check_ranks(t: TestContext, invaders: Array, defenders: Array, when: String) -> void:
	var ranks := []
	for c: Node in invaders:
		ranks.append(c.wardrobe.rank)
	t.expect_eq(
		ranks,
		INVADER_RANKS,
		("%s, the unit's first invader is its lead (rank 2), the second its sergeant (1), the rest "
				+ "troopers (0)") % when,
	)
	for c: Node in defenders:
		t.expect_eq(c.wardrobe.rank, 0, "%s, %s (a defender) has no rank" % [when, c.name])


## Check that every gun and grenade `c` carries has a weapon style in `allowed`, one style for all
## of them; returns it (null when none could be read). Each is held in turn to be read
## (`select_slot`, `current_item`); the gun is held again afterwards.
func _check_items(t: TestContext, c: Node, allowed: Array) -> Variant:
	var gun: int = c.inventory.gun_slot()
	var slots := [gun, ItemRegistry.STUN_SLOT, ItemRegistry.FRAG_SLOT]
	var found: Variant = null
	for slot: int in slots:
		if not t.check(
			c.inventory.has_item(slot),
			"%s carries an item in slot %d" % [c.name, slot],
		):
			continue
		c.inventory.select_slot(slot)
		var item: Item = c.inventory.current_item()
		var style: StringName = item.style
		t.check(
			style in allowed,
			"%s's %s has a weapon style in %s (got %s)" % [
				c.name,
				c.inventory.item_name(),
				allowed,
				style,
			],
		)
		if found == null:
			found = style
		else:
			t.check(
				style == found,
				"%s's %s has the same weapon style as the rest it carries (%s, got %s)"
					% [c.name, c.inventory.item_name(), found, style],
			)
	c.inventory.select_slot(gun)
	return found


func _defender(i: int) -> StringName:
	return StringName("defender_%d" % i)


func _invader(i: int) -> StringName:
	return StringName("invader_%d" % i)
