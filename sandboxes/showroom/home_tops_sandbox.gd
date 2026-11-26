extends GameTest
## A showroom of the home tops that carry their props as items (`docs/stacked-items.md` SI14): you
## are the player, with a pistol (3) and fists (2), in a room holding a desk (a monitor, a keyboard,
## a mug and papers), a side table, a console table, a nightstand, a dresser, a kitchen counter, an
## island and a workbench, each carrying the items its row names, at the row's places. Each item is
## its own body: shove or shoot the monitor and the keyboard stays; knock a piece over and its
## items spill. Walk over a keyboard or papers knocked to the floor: they are stepped over.
##
## The items are carried once the world's lights are built, so the monitor gives none here (a built
## house carries before its lights: the desk glows in a match).
##
## Nothing is asserted. Temporary showroom.

const ARENA := Rect2(0, 0, 1000, 560)
## Each emptied piece: its catalogue key and where it stands.
const PIECES := [
	["desk", Vector2(180, 90)],
	["side_table", Vector2(380, 90)],
	["console_table", Vector2(540, 90)],
	["nightstand", Vector2(700, 90)],
	["dresser", Vector2(840, 90)],
	["kitchen_counter", Vector2(200, 300)],
	["kitchenette_counter", Vector2(400, 300)],
	["island", Vector2(620, 300)],
	["workbench", Vector2(840, 300)],
]


func describe() -> Dictionary:
	return {
		"name": "Home tops showroom",
		"description": "Player sandbox: WASD, mouse, LMB fire, 2 fists, 3 pistol. A desk, side "
			+ "table, console, nightstand, dresser, two counters, an island and a workbench, "
			+ "each carrying the monitor, keyboard, mug, books, clock, vase, bowl, board, "
			+ "tools and vise its painted props became. Shoot or shove any of them: it "
			+ "moves alone.",
		"tags": ["sandbox", "player", "items", "unbake", "furniture", "showroom"],
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.actor(&"you", &"player", Vector2(290, 175), { "start_slot": 3 })
	for row: Array in PIECES:
		s.object(StringName(row[0]), row[0], row[1])
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	for row: Array in PIECES:
		var key: String = row[0]
		RoomItems.carry(
			t.object(StringName(key)), ObjectDefinitions.get_definition(key), t.world, "showroom"
		)
