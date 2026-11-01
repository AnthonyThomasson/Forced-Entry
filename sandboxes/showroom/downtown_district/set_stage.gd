extends Node2D
## The showroom's stage: owns the twelve sets, the picker and what a set spawns. A set is a row of
## exhibits (today's version where one exists, then variants A / B / C), each on its own plot with a
## floor caption, built by the set's module (`Building`, `Street`, `Interior`). A pick removes the
## current set and spawns the next. Run headless with `--showroom-cycle=<s>` it presses Next every
## `s` sim seconds through every set and back to the first, then quits.

const Kit := preload("res://sandboxes/showroom/downtown_district/stage_kit.gd")
const Picker := preload("res://sandboxes/showroom/downtown_district/set_picker.gd")
const Building := preload("res://sandboxes/showroom/downtown_district/sets_building.gd")
const Street := preload("res://sandboxes/showroom/downtown_district/sets_street.gd")
const Interior := preload("res://sandboxes/showroom/downtown_district/sets_interior.gd")
## The sets, in picker order: the title and one line the picker shows, the module and `kind` that
## build it, and each exhibit's name and note under its floor caption (`today` first when the set
## has one).
const SETS := [
	{
		"title": "Lobby floor stencil", "module": &"building", "kind": &"lobby",
		"line": "WIP ELEVATOR LOBBY on an empty 240 x 200 room, on a real concrete and a real tile "
			+ "floor, in the house wall style.",
		"exhibits": [
			[
				"A  Worn boxed stencil",
				"Letters inside a painted rectangle, worn through (The Ascent).",
			],
			["B  Faded room name", "Big faded letters, no box (Prison Architect)."],
			["C  Hazard border", "Yellow and black stripes round the floor, stencil letters."],
		],
	},
	{
		"title": "Tower shadow", "module": &"building", "kind": &"shadow", "today": true,
		"line": "The shadow of a tall tower on the real sidewalk and road, falling away from "
			+ "the art light (down and right).",
		"exhibits": [
			["Today  No shadow", "The tower's ground floor beside the street, nothing cast."],
			["A  Short hard shadow", "A hard offset shadow, mostly on the sidewalk."],
			["B  Long hard shadow", "A long hard shadow across the sidewalk into the road."],
			["C  Long soft shadow", "A long shadow that falls off softly with distance."],
		],
	},
	{
		"title": "Podium / facade band", "module": &"building", "kind": &"podium", "today": true,
		"line": "The band along the outside of a tower's exterior wall, beside the real house wall "
			+ "and sidewalk.",
		"exhibits": [
			["Today  Plain house wall", "The wall as it is, straight onto the sidewalk."],
			["A  Concrete and pillars", "A thick concrete band with pillars along its edge."],
			["B  Dark glass strips", "The band with dark glass window strips set in it."],
			["C  Neon trim", "A dark band with a neon trim strip along its edge."],
		],
	},
	{
		"title": "Awnings and signs", "module": &"building", "kind": &"awning", "today": true,
		"line": "What hangs over the sidewalk at a storefront door (a real glass door), drawn "
			+ "above whoever walks under it.",
		"exhibits": [
			["Today  Nothing", "The door straight onto the sidewalk."],
			["A  Striped awning", "A striped fabric awning with a scalloped edge."],
			["B  Neon box sign", "A projecting neon box sign, BAR in vertical letters."],
			[
				"C  Awning and glyph sign",
				"A dark awning with a neon edge and a hanging vertical glyph sign.",
			],
		],
	},
	{
		"title": "Upper-floor overhang", "module": &"building", "kind": &"overhang", "today": true,
		"line": "The tower's upper floors drawn overhead; each fades out while you stand inside "
			+ "its ground floor.",
		"exhibits": [
			["Today  Nothing", "The ground floor open to the sky."],
			["A  Dark slab", "A semi-transparent dark slab over the footprint."],
			["B  Parapet outline", "Only the parapet edge, the middle left open."],
			["C  Slab with windows", "The slab with a grid of windows, a few lit."],
		],
	},
	{
		"title": "Shell roof", "module": &"building", "kind": &"roof",
		"line": "A closed tower past the district's edge, seen from above: a solid roof beside the "
			+ "real sidewalk and road.",
		"exhibits": [
			[
				"A  Slab, parapet, AC boxes",
				"A dark slab with a parapet and air-conditioning boxes (Glitchpunk).",
			],
			["B  Tank and vents", "Also a water tank and roof vents."],
			["C  Neon billboard", "Also a rooftop neon billboard."],
		],
	},
	{
		"title": "Crosswalk and junction", "module": &"street", "kind": &"crossing", "today": true,
		"line": "A four-way crossing on real asphalt and sidewalk; today has the lane dashes and "
			+ "no crossing.",
		"exhibits": [
			["Today  Lane dashes only", "The street as it is: dashes down the road, no crossing."],
			["A  Clean zebra", "Clean white zebra bars and stop lines on every arm."],
			["B  Worn zebra", "The same, faded, with the tyre tracks rubbed through."],
			["C  Ladder and box junction", "Ladder crossings and a yellow hatched box junction."],
		],
	},
	{
		"title": "Road glyphs", "module": &"street", "kind": &"glyphs",
		"line": "Paint on the road over real asphalt: characters, lane numbers and arrows.",
		"exhibits": [
			["A  Painted characters", "Large painted Chinese characters on the road (Ruiner)."],
			["B  Numbers and arrows", "Lane numbers and arrows."],
			["C  Both, faded", "Characters, numbers and arrows, worn faint."],
		],
	},
	{
		"title": "Sidewalk clutter", "module": &"street", "kind": &"clutter",
		"line": "A vending machine, bench, bin, drain grate and litter on a real sidewalk beside a "
			+ "real streetlight, in three style families.",
		"exhibits": [
			["A  Grimy steel", "Dull steel and rust, wooden slats, nothing lit."],
			["B  Neon-lit", "Dark bodies with cyan and magenta neon, lit windows."],
			["C  Painted municipal", "Bright council green and cream paint, kept up."],
		],
	},
	{
		"title": "Shop pieces", "module": &"interior", "kind": &"shop", "today": true,
		"line": "The bodega: a counter with till, a double-sided shelf aisle, a glass drinks "
			+ "fridge and a snack machine.",
		"exhibits": [
			["Today  Closest pieces", "A kitchen counter, garage shelving and the kitchen fridge."],
			["A  Grimy steel", "Dull steel and rust, a dim glass front."],
			["B  Neon-lit", "Dark bodies with neon trim and lit glass."],
			["C  Painted municipal", "Council green and cream paint, bright packs."],
		],
	},
	{
		"title": "Noodle bar pieces", "module": &"interior", "kind": &"noodle", "today": true,
		"line": "The noodle bar: a long bar counter, bar stools, a booth and a neon menu board.",
		"exhibits": [
			["Today  Closest pieces", "A kitchen counter and stove, chairs for stools, a table."],
			["A  Grimy steel", "A steel-topped bar, worn stools, a dim menu board."],
			["B  Neon-lit", "Dark wood with neon under-glow and a bright menu."],
			["C  Painted municipal", "Painted bar, stools and booth, a plain menu."],
		],
	},
	{
		"title": "Stockroom pieces", "module": &"interior", "kind": &"stock", "today": true,
		"line": "The back office: stacked crates, a pallet of wrapped boxes and a wall safe.",
		"exhibits": [
			["Today  Closest pieces", "Garage shelving and loose cardboard."],
			["A  Grimy steel", "Weathered wooden crates, a grey-wrapped pallet, a rusty safe."],
			["B  Neon-lit", "Dark plastic crates with LED labels, a neon keypad safe."],
			["C  Painted municipal", "Olive painted crates, a blue pallet, a green safe."],
		],
	},
]
## Plots: the x of the middle of the row, the step between exhibits, where plots start and where
## their captions sit.
const CENTRE_X := 780.0
const SLOT_STEP := 320.0
const PLOT_TOP := 60.0
const LABEL_Y := 510.0
const CYCLE_ARG := "--showroom-cycle="

## The player, so a set can watch where it stands (the overhang that fades).
var player: Node2D
var _kit: Kit
var _picker: CanvasLayer
var _index := 0
var _cycle := 0.0
var _clock := 0.0
var _visits := 0


func _ready() -> void:
	_kit = Kit.new(get_parent())
	_picker = Picker.new()
	var headings: Array = []
	var lines: Array = []
	for entry: Dictionary in SETS:
		headings.append(entry["title"])
		lines.append(entry["line"])
	_picker.setup(SETS.size(), headings, lines)
	_picker.picked.connect(_stage)
	add_child(_picker)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(CYCLE_ARG):
			_cycle = float(arg.trim_prefix(CYCLE_ARG))
	_stage(0)


func _physics_process(delta: float) -> void:
	if _cycle <= 0.0:
		return
	_clock += delta
	if _clock < _cycle:
		return
	_clock = 0.0
	_visits += 1
	if _visits > SETS.size():
		get_tree().quit()
		return
	_stage(posmod(_index + 1, SETS.size()))


## Remove the current set and spawn set `index` once the last one is gone (a frame later).
func _stage(index: int) -> void:
	_kit.clear()
	_index = index
	_picker.show_index(index)
	await get_tree().process_frame
	if index != _index:
		return
	var entry: Dictionary = SETS[index]
	var exhibits: Array = entry["exhibits"]
	var variants: Array[String] = _variants(entry)
	for i in variants.size():
		var origin := Vector2(
			CENTRE_X + (i - (variants.size() - 1) * 0.5) * SLOT_STEP - Kit.PLOT_W * 0.5,
			PLOT_TOP,
		)
		var slot := { "origin": origin, "variant": variants[i], "player": player }
		_build(entry, slot)
		var caption: Array = exhibits[i]
		_kit.label(Vector2(origin.x, LABEL_Y), caption[0], caption[1])


## The variant of each exhibit of `entry`, in row order: `today` (when the set shows it) then a, b,
## c.
func _variants(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if entry.get("today", false):
		out.append("today")
	out.append_array(["a", "b", "c"])
	return out


func _build(entry: Dictionary, slot: Dictionary) -> void:
	match entry["module"]:
		&"building":
			Building.build(_kit, entry["kind"], slot)
		&"street":
			Street.build(_kit, entry["kind"], slot)
		&"interior":
			Interior.build(_kit, entry["kind"], slot)
