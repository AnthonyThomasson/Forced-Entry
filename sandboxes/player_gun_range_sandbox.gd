extends GameTest
## A sandbox to play: you are the player in a furnished arena with every gun — pistol (3), SMG (5)
## and assault rifle (6) — plus fists (2), a few target dummies, and walls and furniture to press
## the barrel against. Nothing is asserted — compare the guns' fire rate (hold LMB for the
## automatics), damage and penetration (the rifle shoots through the east wall at the dummy behind
## it), see how each is held, and walk the rifle or SMG up to a wall or the chair to watch it come
## up and stop firing.
##
## The player also carries 3 stun (7) and 3 frag (8) grenades, thrown on LMB: 2 s after the last one
## goes off (none of the player's still live, no reload or throw under way) both are topped back up
## to 3, the range re-arming the player as Main arms a spawn (`Character.inventory.set_loadout`),
## which restocks the guns and their spare magazines too. West of where the player starts a dummy
## crouches against the far (west) face of a couch: lob a frag or a stun short of the couch to see
## it shield the crouched body (`docs/grenades.md` G7, G11), and one over it to see it does not.
##
## South of that is the armour range (docs/outfits.md): a firing line of nine numbered lanes, each
## ending at a dummy dressed in one outfit — plain clothes, a helmet, the tactical vest, the plate
## carrier empty and with each plate, the invaders' whole kit turned away and a ceramic carrier
## turned side on. Stand on a lane's mark and shoot its dummy to see what each outfit stops and lets
## through, watch a plate wear down, and compare a plate's front with its back (lane 8) and with a
## shot that takes it in the flank (lane 9). The label on the floor under each dummy keeps its
## outfit (the debug panel's wording), plate condition and health current. A shoved dummy walks back
## to its spot.
##
## North of the range, built onto the outside of its north wall (y < 0), is a row of four small
## rooms with doors (docs/doors.md), seven doors in all, one of each catalogue door. Each room opens
## onto the range through a doorway with a door whose material a floor label beside it names: a
## hollow-core flush door (shut, swinging into its room), a solid wood panelled one (ajar, swinging
## out into the range), a riveted steel one (shut: the tough one to kick or shoot open) and a
## glass-panel one (shut, with a dummy inside the room, seen through the panes). Between the rooms
## a hollow panelled door (shut), a solid plank door (ajar) and a steel peephole door (open) join
## each pair. E opens and shuts a door in reach, held E and the wheel open it by steps; kick a shut
## one from the push side (the side it swings away from) to burst its latch; an ajar or open door
## has no latch (one kick throws it open, steel too) and turns about its hinge as you walk into it;
## shoot or kick a door down, and shoot the glass door's panes to shatter them.

const OutfitLines := preload("res://scenes/ui/hud/outfit_lines.gd")
const ARENA := Rect2(-680, 0, 1680, 1300)
## The firing line's y, and the y of the dummies at the end of its lanes (the labels sit under them,
## by the south wall).
const FIRE_Y := 780.0
const DUMMY_Y := 1120.0
## The first lane's x and the gap between lanes: wide enough that no label runs into the next.
const LANE_X := -560.0
const LANE_GAP := 180.0
const DUMMY_HEALTH := 1000.0
## Grenades the player carries of each kind, topped back up `RESTOCK_AFTER` s after the last one
## goes off.
const GRENADES := 3
const RESTOCK_AFTER := 2.0
## The cover spot: a couch turned north-south (spanning 50 x 120 px) and a dummy crouched against
## its west face, the far side from the player, a body's width and a little off it.
const COUCH := Vector2(-120, 320)
const CROUCHED := Vector2(-165, 320)
## The doors' rooms: four side by side over the range's north wall (y = 0), each `ROOM_SIZE` px
## square, the first starting at x = `ROOMS_X`. Every doorway is `DOORWAY` px wide; the walls' ends
## reach 6 px into it, so the free gap between the jambs is 48 px and a door's hinge sits `JAMB` px
## from the doorway's middle (docs/doors.md DR3).
const ROOM_SIZE := 240.0
const ROOMS_X := -360.0
const DOORWAY := 60.0
const JAMB := 24.0
## The doorways onto the range, one per room in order: the room's door (a `DoorCatalog` material and
## style), the side its hinge is on (-1 the west jamb, 1 the east), where it swings (`into`: UP into
## its room, DOWN out into the range), its start angle (0 shut, else ajar), and the words on its
## floor label.
const RANGE_DOORS := [
	{
		"name": "door_flush", "material": "hollow", "style": "flush", "hinge": -1.0,
		"into": Vector2.UP, "angle": 0.0, "title": "Hollow-core wood", "note": "flush, shut",
	},
	{
		"name": "door_solid_panelled", "material": "solid", "style": "panelled", "hinge": 1.0,
		"into": Vector2.DOWN, "angle": 30.0, "title": "Solid wood",
		"note": "panelled, ajar, swings out",
	},
	{
		"name": "door_riveted", "material": "steel", "style": "riveted", "hinge": -1.0,
		"into": Vector2.UP, "angle": 0.0, "title": "Steel", "note": "riveted, shut",
	},
	{
		"name": "door_panes", "material": "glass", "style": "panes", "hinge": 1.0,
		"into": Vector2.UP, "angle": 0.0, "title": "Glass-panel", "note": "panes, shut: look in",
	},
]
## The doorways between neighbouring rooms, first to last: the door, the y of its hinge (on the
## north or south jamb of the doorway at y = -`ROOM_SIZE` / 2), the side it swings to (`into`) and
## its start angle (shut, ajar, open).
const ROOM_DOORS := [
	{
		"name": "door_hollow_panelled", "material": "hollow", "style": "panelled",
		"hinge_y": -144.0, "into": Vector2.RIGHT, "angle": 0.0,
	},
	{
		"name": "door_plank", "material": "solid", "style": "plank", "hinge_y": -96.0,
		"into": Vector2.LEFT, "angle": 25.0,
	},
	{
		"name": "door_peephole", "material": "steel", "style": "peephole", "hinge_y": -144.0,
		"into": Vector2.RIGHT, "angle": 90.0,
	},
]
## The dummy standing in the glass-panel door's room, facing the doorway, seen through the panes.
const GLASS_DUMMY := Vector2(480, -110)
## The lineup, lane by lane: what it is, what it wears and which way it faces (the firing line is
## north of it).
const LANES := [
	{
		"title": "Plain clothes", "facing": Vector2.UP,
		"outfit": { "body": &"tshirt", "pants": &"jeans", "feet": &"shoes" },
	},
	{
		"title": "Helmet + t-shirt", "facing": Vector2.UP,
		"outfit": { "head": &"helmet", "body": &"tshirt", "pants": &"jeans", "feet": &"shoes" },
	},
	{
		"title": "Tactical vest", "facing": Vector2.UP,
		"outfit": {
			"body": &"tshirt", "vest": &"tactical_vest", "pants": &"jeans", "feet": &"shoes",
		},
	},
	{
		"title": "Carrier, no plates", "facing": Vector2.UP,
		"outfit": {
			"body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
		},
	},
	{
		"title": "Carrier + soft IIIA", "facing": Vector2.UP,
		"outfit": {
			"body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
			"front_plate": &"soft_iiia", "back_plate": &"soft_iiia",
		},
	},
	{
		"title": "Carrier + steel III", "facing": Vector2.UP,
		"outfit": {
			"body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
			"front_plate": &"steel_iii", "back_plate": &"steel_iii",
		},
	},
	{
		"title": "Carrier + ceramic IV", "facing": Vector2.UP,
		"outfit": {
			"body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
			"front_plate": &"ceramic_iv", "back_plate": &"ceramic_iv",
		},
	},
	{
		"title": "Invader kit, back turned", "note": "shots strike the back plate",
		"facing": Vector2.DOWN,
		"outfit": {
			"head": &"helmet", "body": &"shirt", "vest": &"plate_carrier",
			"pants": &"tactical_pants", "feet": &"boots", "front_plate": &"steel_iii",
			"back_plate": &"steel_iii",
		},
	},
	{
		"title": "Ceramic IV, side on", "note": "shots strike the flank", "facing": Vector2.RIGHT,
		"outfit": {
			"body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
			"front_plate": &"ceramic_iv", "back_plate": &"ceramic_iv",
		},
	},
]


func describe() -> Dictionary:
	return {
		"name": "Gun range",
		"description": "Player-controlled sandbox: WASD to move, mouse to aim, LMB to fire (hold "
			+ "it for the SMG and rifle) or throw, R to reload, F to punch, V to kick, E to use a "
			+ "door, 2 fists, 3 pistol, 5 SMG, 6 rifle, 7 stun grenades, 8 frag grenades (3 of "
			+ "each, topped back up 2 s after the last one goes off; the range restocks the guns "
			+ "and spare magazines with them). Press a long gun against a wall or a chair to see "
			+ "it raised. West of the start a dummy crouches behind a couch: throw a grenade short "
			+ "of the couch to see its cover, over it to see none. South of it, the armour range: "
			+ "nine lanes off a firing line, each dummy (1000 health) in one outfit — plain "
			+ "clothes, helmet, tactical vest, plate carrier empty and with soft IIIA, steel III "
			+ "or ceramic IV, the invader kit turned away (back plate) and a ceramic carrier side "
			+ "on (flank). Shoot each from its lane mark, watch its plates wear on the floor label "
			+ "and compare front, back and flank. North of the range, built onto its north wall, "
			+ "four small rooms with seven doors, one of each material and style, a floor label "
			+ "naming each door that opens onto the range: tap E beside a door to open or shut "
			+ "it, hold E and scroll to open it by steps, kick it (V) from the push side, the side "
			+ "it swings away from, to burst its latch (hollow: two kicks, steel: never; an ajar "
			+ "door has no latch: one kick opens it), walk into an ajar door to push it about its "
			+ "hinge, shoot a door down (steel stops the pistol, not the rifle), and look through "
			+ "the glass door's panes at the dummy in its room, then shoot them out.",
		"tags": [
			"sandbox", "player", "gun", "pistol", "smg", "rifle", "grenade", "stun", "frag",
			"cover", "outfit", "armour", "plate", "door",
		],
		"manual": true,
	}


func configure(s: TestSetup) -> void:
	s.layout(_rooms(), _doorways())
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })
	s.actor(&"dummy_a", &"puppet", Vector2(700, 200), { "max_health": 200.0, "faction": &"dummy" })
	s.actor(&"dummy_b", &"puppet", Vector2(760, 440), { "max_health": 200.0, "faction": &"dummy" })
	# Just outside the east wall: only the rifle's rounds reach it.
	s.actor(
		&"dummy_behind_wall",
		&"puppet",
		Vector2(1040, 320),
		{ "max_health": 200.0, "faction": &"dummy" },
	)
	s.object(&"chair", "chair", Vector2(420, 200))
	s.object(&"armchair", "armchair", Vector2(460, 460))
	s.object(&"couch", "sofa", COUCH, { "rotated": true })
	s.actor(&"crouched", &"puppet", CROUCHED, { "max_health": DUMMY_HEALTH, "faction": &"dummy",
		"facing": Vector2.RIGHT, "movement:aim_point": CROUCHED + Vector2.RIGHT * 300.0 })
	for i in LANES.size():
		var home := _home(i)
		var facing: Vector2 = LANES[i]["facing"]
		s.actor(_lane_id(i), &"puppet", home, { "max_health": DUMMY_HEALTH, "faction": &"dummy",
			"facing": facing, "movement:aim_point": home + facing * 300.0 })
	s.actor(&"dummy_glass", &"puppet", GLASS_DUMMY, { "max_health": 200.0, "faction": &"dummy",
		"facing": Vector2.DOWN, "movement:aim_point": GLASS_DUMMY + Vector2.DOWN * 300.0 })
	s.camera_follow([&"you"])


## Arm the player with its grenades, crouch the dummy behind the couch, dress the lineup, hold each
## dummy's facing with its puppet's aim, and lay a station (lane mark and floor label) under each.
func run(t: TestContext) -> void:
	var restock := Restock.new()
	restock.name = "GrenadeRestock"
	restock.setup(t.actor(&"you"))
	t.world.add_child(restock)
	var cover := CoverSpot.new()
	cover.name = "CoverSpot"
	cover.setup(t.actor(&"crouched"), t.puppet(&"crouched"))
	t.puppet(&"crouched").aim_at(CROUCHED + Vector2.RIGHT * 300.0)
	t.world.add_child(cover)
	cover.global_position = CROUCHED
	t.puppet(&"dummy_glass").aim_at(GLASS_DUMMY + Vector2.DOWN * 300.0)
	for i in RANGE_DOORS.size():
		var door_sign := DoorSign.new()
		door_sign.name = "Door%dSign" % (i + 1)
		door_sign.setup(RANGE_DOORS[i])
		t.world.add_child(door_sign)
		door_sign.global_position = Vector2(_room_centre_x(i), 0.0)
	for i in LANES.size():
		var lane: Dictionary = LANES[i]
		var dummy := t.actor(_lane_id(i))
		dummy.wardrobe.outfit.set_ids(lane["outfit"])
		var home := _home(i)
		var puppet := t.puppet(_lane_id(i))
		puppet.aim_at(home + (lane["facing"] as Vector2) * 300.0)
		var station := Station.new()
		station.name = "Lane%dStation" % (i + 1)
		station.setup(dummy, puppet, i + 1, lane)
		t.world.add_child(station)
		station.global_position = home


## The layout's rooms: the range over `ARENA` (a concrete floor, the arena's walls) and the four
## rooms of the doors along the outside of its north wall, each sharing that wall with it.
static func _rooms() -> Array:
	var rooms: Array = [{ "key": "range", "type": "arena", "rect": ARENA, "floor": "concrete" }]
	for i in RANGE_DOORS.size():
		var room_name: String = (RANGE_DOORS[i]["name"] as String).trim_prefix("door_")
		rooms.append({
			"key": "%s_room" % room_name, "type": "living_room",
			"rect": Rect2(ROOMS_X + ROOM_SIZE * i, -ROOM_SIZE, ROOM_SIZE, ROOM_SIZE),
		})
	return rooms


## The seven doorways: the four onto the range through the north wall (y = 0), then the three
## between neighbouring rooms through their shared walls, each with its door.
static func _doorways() -> Array:
	var doorways: Array = []
	for i in RANGE_DOORS.size():
		var spec: Dictionary = RANGE_DOORS[i]
		var middle := Vector2(_room_centre_x(i), 0.0)
		doorways.append(_doorway(middle, spec, middle + Vector2(JAMB * float(spec["hinge"]), 0.0)))
	for i in ROOM_DOORS.size():
		var spec: Dictionary = ROOM_DOORS[i]
		var middle := Vector2(ROOMS_X + ROOM_SIZE * (i + 1), -ROOM_SIZE * 0.5)
		doorways.append(_doorway(middle, spec, Vector2(middle.x, float(spec["hinge_y"]))))
	return doorways


## A doorway at `middle` holding the door `spec` names, hinged at `hinge`.
static func _doorway(middle: Vector2, spec: Dictionary, hinge: Vector2) -> Dictionary:
	return {
		"pos": middle, "width": DOORWAY,
		"door": {
			"name": spec["name"], "material": spec["material"], "style": spec["style"],
			"hinge": hinge, "swing_into": spec["into"], "angle": spec["angle"],
		},
	}


## The x of the middle of room `i` (and of its doorway onto the range).
static func _room_centre_x(i: int) -> float:
	return ROOMS_X + ROOM_SIZE * (i + 0.5)


## Where lane `i`'s dummy stands.
static func _home(i: int) -> Vector2:
	return Vector2(LANE_X + LANE_GAP * i, DUMMY_Y)


## The actor id of lane `i`'s dummy.
static func _lane_id(i: int) -> StringName:
	return StringName("lane_%d" % (i + 1))


## Keeps the player's grenades: arms it with `GRENADES` stuns and frags on top of everything it
## carries, and re-arms it the same way `RESTOCK_AFTER` s after the last of its grenades goes off,
## once none of them is live and no reload or throw is under way (`Character.inventory.set_loadout`,
## which restocks its guns and spare magazines with them: the range's whole restock).
class Restock extends Node:
	var _player: Node
	## Every slot it carries at the start, and both grenade slots.
	var _slots: Array = []
	## s since the last of its grenades went off; negative = nothing to top up.
	var _since := -1.0

	func _ready() -> void:
		_arm()
		EventBus.posted.connect(_on_posted)

	func _exit_tree() -> void:
		if EventBus.posted.is_connected(_on_posted):
			EventBus.posted.disconnect(_on_posted)

	func _physics_process(delta: float) -> void:
		if _since < 0.0 or not is_instance_valid(_player) or _player.is_dead:
			return
		_since += delta
		if _since < RESTOCK_AFTER or _busy():
			return
		_since = -1.0
		if (_player.inventory.item_count(ItemRegistry.STUN_SLOT) < GRENADES
				or _player.inventory.item_count(ItemRegistry.FRAG_SLOT) < GRENADES):
			_arm()

	## Keep `player`'s grenades: note every slot it carries now, and both grenade slots.
	func setup(player: Node) -> void:
		_player = player
		for slot in range(1, 10):
			if player.inventory.has_item(slot):
				_slots.append(slot)
		for slot in [ItemRegistry.STUN_SLOT, ItemRegistry.FRAG_SLOT]:
			if slot not in _slots:
				_slots.append(slot)

	## A burst of one of the player's grenades starts the clock to the re-arm.
	func _on_posted(topic: StringName, data: Dictionary) -> void:
		if topic == &"explosion" and data.get("attacker") == _player:
			_since = 0.0

	## Whether a grenade of the player's is still live, or a reload or a throw's wind-up is under
	## way: the re-arm waits for it.
	func _busy() -> bool:
		for g in get_tree().get_nodes_in_group(&"live_grenades"):
			if g.get(&"thrower") == _player:
				return true
		var item: Item = _player.inventory.current_item()
		return (_player.ammo.is_reloading()
				or (item != null and item.hand_stance(item.weapon_hand()) == &"throw"))

	## Arm the player with every slot it started with and `GRENADES` of each grenade, holding what
	## it holds.
	func _arm() -> void:
		var kit := CharacterKit.new()
		kit.slots = _slots
		kit.hold_slot = _player.inventory.current_slot()
		kit.spare_types = _player.ammo.spare_magazine_types
		kit.grenades = { ItemRegistry.STUN_SLOT: GRENADES, ItemRegistry.FRAG_SLOT: GRENADES }
		_player.inventory.set_loadout(kit)


## The cover spot's dummy: crouched against the couch, walked back to its spot once a blast has
## shoved it off, with a label on the floor beside it.
class CoverSpot extends Node2D:
	## px off its spot before the dummy walks back.
	const DRIFT := 8.0
	const TEXT := Color(0.92, 0.92, 0.86)

	var _dummy: Node2D
	var _puppet: Node

	func _ready() -> void:
		_puppet.set_posture(&"crouch")

	func _physics_process(_delta: float) -> void:
		if is_instance_valid(_dummy) and not _dummy.is_dead and _puppet.has_arrived() \
				and _dummy.global_position.distance_to(global_position) > DRIFT:
			_puppet.walk_to(global_position)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var at := Vector2(-90, -70)
		draw_string_outline(
			font,
			at,
			"Crouched behind a couch: cover",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			3,
			Color(0, 0, 0, 0.85),
		)
		draw_string(
			font,
			at,
			"Crouched behind a couch: cover",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			TEXT,
		)

	## Watch `dummy`, walked back to its spot through its `puppet`.
	func setup(dummy: Node2D, puppet: Node) -> void:
		_dummy = dummy
		_puppet = puppet
		z_index = -1  # on the floor, under the bodies


## A range-side door's floor label, drawn on the range just south of the doorway: the door's
## material, then its style and how it starts.
class DoorSign extends Node2D:
	const FONT_SIZE := 10
	## px south of the wall where the two lines' baselines are.
	const TOP := 40.0
	const LINE := 11.0
	const TEXT := Color(0.92, 0.92, 0.86)
	const MUTED := Color(0.72, 0.74, 0.70)

	var _lines: Array[String] = []

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for i in _lines.size():
			var at := Vector2(
				-font.get_string_size(_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x * 0.5,
				TOP + LINE * i,
			)
			draw_string_outline(
				font, at, _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3,
				Color(0, 0, 0, 0.85),
			)
			draw_string(
				font, at, _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
				TEXT if i == 0 else MUTED,
			)

	## Label the door `spec` (a `RANGE_DOORS` row).
	func setup(spec: Dictionary) -> void:
		_lines = [str(spec["title"]), str(spec["note"])]
		z_index = -1  # on the floor, under the bodies


## One lane's floor markings, drawn at its dummy's spot: the lane's mark on the firing line, and
## under the dummy its number and title, its outfit (`OutfitLines`, the debug panel's wording, the
## slots worn), its plate condition and its health, kept current. It also walks the dummy back to
## its spot once a hit has shoved it off.
class Station extends Node2D:
	const FONT_SIZE := 8
	## The text is rasterised this many times larger and drawn scaled down, so it stays crisp zoomed
	## in.
	const SHARP := 2.0
	## px between lines.
	const LINE := 10.0
	## px under the dummy's centre where the label starts.
	const TEXT_TOP := 26.0
	## px off its spot before a dummy walks back.
	const DRIFT := 8.0
	const TEXT := Color(0.92, 0.92, 0.86)
	const MUTED := Color(0.72, 0.74, 0.70)
	const MARK := Color(0.95, 0.80, 0.30)

	var _dummy: Node2D
	var _puppet: Node
	var _number := 0
	var _lane: Dictionary
	var _lines: Array[String] = []

	func _physics_process(_delta: float) -> void:
		if not is_instance_valid(_dummy):
			return
		var lines := _text()
		if lines != _lines:
			_lines = lines
			queue_redraw()
		if (not _dummy.is_dead
				and _puppet.has_arrived()
				and _dummy.global_position.distance_to(global_position) > DRIFT):
			_puppet.walk_to(global_position)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		# The lane's mark on the firing line, straight up the lane from the dummy.
		var mark := Vector2(0, FIRE_Y - global_position.y)
		draw_line(mark + Vector2(-14, 0), mark + Vector2(14, 0), MARK, 2.0)
		draw_line(mark + Vector2(0, -6), mark + Vector2(0, 6), MARK, 2.0)
		_say(font, mark + Vector2(0, -10), str(_number), MARK, FONT_SIZE + 4)
		for i in _lines.size():
			_say(
				font,
				Vector2(0, TEXT_TOP + LINE * i),
				_lines[i],
				TEXT if i == 0 or _lines[i].begins_with("Health") else MUTED,
				FONT_SIZE,
			)

	func setup(dummy: Node2D, puppet: Node, number: int, lane: Dictionary) -> void:
		_dummy = dummy
		_puppet = puppet
		_number = number
		_lane = lane
		# on the floor, under the bodies
		z_index = -1

	## The label's lines: the lane's number and title, its note, the outfit worn and the dummy's
	## health.
	func _text() -> Array[String]:
		var out: Array[String] = ["%d. %s" % [_number, _lane["title"]]]
		if _lane.has("note"):
			out.append("(%s)" % _lane["note"])
		for line in OutfitLines.of(_dummy.wardrobe.outfit.view()):
			if not line.ends_with(": —"):
				out.append(line)
		out.append("Dead"
				if _dummy.is_dead
				else "Health: %d / %d" % [ceili(_dummy.health), roundi(_dummy.max_health)])
		return out

	## Draw `text` centred across `at` (its baseline at `at.y`), outlined, rasterised `SHARP` times
	## larger and scaled down so it stays crisp zoomed in.
	func _say(font: Font, at: Vector2, text: String, color: Color, size: int) -> void:
		var big := roundi(size * SHARP)
		var left := at * SHARP - Vector2(
			font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x * 0.5,
			0,
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / SHARP)
		draw_string_outline(
			font,
			left,
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			big,
			roundi(3 * SHARP),
			Color(0, 0, 0, 0.85),
		)
		draw_string(font, left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, color)
		draw_set_transform(Vector2.ZERO)
