extends GameTest
## DR13: a door comes in four materials, each in its styles, drawn in the run-down look with its
## material's hit points and resistance to being shot through. Every one spawns in a doorway from
## its definition, draws its art (each style its own), reports the HP and the penetration the
## spec gives, stands as full cover (a door is struck at every height) and is told by the group
## `doors`. The numbers are the brief's (`docs/doors.md` DR13), kept here.

const WEST := Rect2(0, 0, 400, 800)
const EAST := Rect2(400, 0, 400, 800)
const WIDTH := 52.0
## The walls are 12 px thick and their ends reach 6 px into the gap, so the doorway is free between
## jambs 40 px apart; the hinge sits on one of them.
const JAMB := 20.0
## material, style, hit points, penetration.
const DOORS := [
	[&"hollow", &"flush", 80.0, 10.0],
	[&"hollow", &"panelled", 80.0, 10.0],
	[&"solid", &"panelled", 250.0, 45.0],
	[&"solid", &"plank", 250.0, 45.0],
	[&"steel", &"riveted", 1200.0, 90.0],
	[&"steel", &"peephole", 1200.0, 90.0],
	[&"glass", &"panes", 80.0, 5.0],
]


func describe() -> Dictionary:
	return {
		"name": "Doors come in four materials and their styles",
		"description": "Each material and style of door spawns in a doorway, draws its art (each "
			+ "style differently) and reports its material's HP and penetration.",
		"tags": ["door", "objects", "art"],
		"timeout": 5.0,
	}


func _id(row: Array) -> StringName:
	return StringName("%s_%s" % [row[0], row[1]])


func configure(s: TestSetup) -> void:
	var doorways: Array = []
	for i in DOORS.size():
		var y := 60.0 + 110.0 * i
		doorways.append({
			"pos": Vector2(400, y), "width": WIDTH,
			"door": {
				"name": _id(DOORS[i]), "material": DOORS[i][0], "style": DOORS[i][1],
				"hinge": Vector2(400, y - JAMB), "swing_into": Vector2.RIGHT,
			},
		})
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "bedroom", "rect": EAST },
	], doorways)


func run(t: TestContext) -> void:
	await t.seconds(0.2)
	var pixels := {}
	for row: Array in DOORS:
		var id := _id(row)
		var door = t.object(id)
		if not t.require(door != null, "the %s door spawns" % id):
			return
		t.check(door.is_in_group(&"doors"), "the %s door is in the group doors" % id)
		t.expect_eq(door.damage.hp, row[2], "the %s door has its material's HP" % id)
		var surface: Dictionary = door.get_surface()
		t.expect_eq(surface["penetration"], row[3], "the %s door's penetration" % id)
		t.expect_eq(surface["coverage"], 100.0, "the %s door is struck at every height" % id)
		var art: Texture2D = door.visuals.texture()
		if not t.require(art != null, "the %s door draws its art" % id):
			return
		pixels[id] = art.get_image().get_data()
	for pair in [[&"hollow_flush", &"hollow_panelled"], [&"solid_panelled", &"solid_plank"],
			[&"steel_riveted", &"steel_peephole"]]:
		t.check(
			pixels[pair[0]] != pixels[pair[1]],
			"%s and %s are drawn differently" % [pair[0], pair[1]],
		)
	t.check(
		pixels[&"hollow_panelled"] != pixels[&"solid_panelled"],
		"a hollow and a solid panelled door are drawn in their own materials",
	)
