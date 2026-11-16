extends GameTest
## The character painters' lit renders, pinned (#193 phase 2b, Character): the 3D body reads the
## painters flat (`StyleArt.flat`, `body-textures.md`) and the guards that make them skip a ring or
## a rim must never be taken by a lit canvas, which is what the 2D draws. A few lit renders of each
## painter, in different looks and facings, are hashed here and must stay what they were before the
## flat read existed (the hashes were taken on the ticket's branch without it).
## To refresh them after a deliberate change to a painter, run the test with
## `GOLDEN_OUT=<file>`: it writes the table (`GOLDEN`'s lines) there.

const BodyPainter := preload("res://scenes/character/body/art/body_painter.gd")
const HeadPainter := preload("res://scenes/character/body/art/head_painter.gd")
const HandPainter := preload("res://scenes/character/body/art/hand_painter.gd")
const LimbPainter := preload("res://scenes/character/body/art/limb_painter.gd")
const VestFacePainter := preload("res://tests/character/vest_face_painter.gd")
const SKIN := Color(0.80, 0.62, 0.48)
const SHIRT := Color(0.30, 0.38, 0.52)
const SHOE := Color(0.45, 0.30, 0.18)
const GREEN := Color(0.15, 0.62, 0.22)
## The hash of each render (`_renders`), by name.
const GOLDEN := {
	"head plain down": 3_636_489_038,
	"shoulders plain down": 4_183_449_823,
	"foot plain down": 1_428_209_968,
	"shaft plain down": 1_736_377_033,
	"upper plain down": 2_923_454_351,
	"fore plain down": 2_923_454_351,
	"thigh plain down": 2_923_454_351,
	"knee plain down": 2_923_454_351,
	"shin plain down": 2_928_336_657,
	"vest front plain down": 4_157_658_769,
	"vest side plain down": 4_157_658_769,
	"head police down": 3_636_489_038,
	"shoulders police down": 4_183_449_823,
	"foot police down": 758_107_810,
	"shaft police down": 1_736_377_033,
	"upper police down": 2_923_454_351,
	"fore police down": 2_923_454_351,
	"thigh police down": 2_572_600_158,
	"knee police down": 2_572_600_158,
	"shin police down": 2_572_600_158,
	"vest front police down": 4_157_658_769,
	"vest side police down": 4_157_658_769,
	"head merc down": 3_636_489_038,
	"shoulders merc down": 2_987_141_988,
	"foot merc down": 1_992_497_171,
	"shaft merc down": 1_736_377_033,
	"upper merc down": 1_589_780_075,
	"fore merc down": 2_766_233_809,
	"thigh merc down": 3_673_429_157,
	"knee merc down": 3_112_540_017,
	"shin merc down": 2_928_336_657,
	"vest front merc down": 2_407_797_558,
	"vest side merc down": 2_927_091_146,
	"head carrier down": 3_218_433_868,
	"shoulders carrier down": 4_246_576_021,
	"foot carrier down": 1_428_209_968,
	"shaft carrier down": 1_736_377_033,
	"upper carrier down": 2_923_454_351,
	"fore carrier down": 2_923_454_351,
	"thigh carrier down": 2_923_454_351,
	"knee carrier down": 2_923_454_351,
	"shin carrier down": 2_928_336_657,
	"vest front carrier down": 2_928_395_647,
	"vest side carrier down": 4_021_455_344,
	"head cap down": 3_583_995_942,
	"shoulders cap down": 4_183_449_823,
	"foot cap down": 3_453_395_949,
	"shaft cap down": 1_736_377_033,
	"upper cap down": 2_923_454_351,
	"fore cap down": 2_923_454_351,
	"thigh cap down": 2_923_454_351,
	"knee cap down": 2_923_454_351,
	"shin cap down": 2_928_336_657,
	"vest front cap down": 4_157_658_769,
	"vest side cap down": 4_157_658_769,
	"hand down": 1_066_423_625,
	"hand side down": 3_398_931_273,
	"head plain right": 3_055_622_249,
	"shoulders plain right": 3_011_958_210,
	"foot plain right": 3_484_037_146,
	"shaft plain right": 3_298_463_021,
	"upper plain right": 2_717_268_126,
	"fore plain right": 2_717_268_126,
	"thigh plain right": 2_717_268_126,
	"knee plain right": 2_717_268_126,
	"shin plain right": 1_792_825_867,
	"vest front plain right": 4_157_658_769,
	"vest side plain right": 4_157_658_769,
	"head police right": 3_055_622_249,
	"shoulders police right": 3_011_958_210,
	"foot police right": 4_253_862_269,
	"shaft police right": 3_298_463_021,
	"upper police right": 2_717_268_126,
	"fore police right": 2_717_268_126,
	"thigh police right": 1_435_399_441,
	"knee police right": 1_435_399_441,
	"shin police right": 1_435_399_441,
	"vest front police right": 4_157_658_769,
	"vest side police right": 4_157_658_769,
	"head merc right": 3_055_622_249,
	"shoulders merc right": 2_730_458_218,
	"foot merc right": 4_026_607_627,
	"shaft merc right": 3_298_463_021,
	"upper merc right": 2_159_393_033,
	"fore merc right": 405_188_426,
	"thigh merc right": 10_162_022,
	"knee merc right": 3_112_540_017,
	"shin merc right": 1_792_825_867,
	"vest front merc right": 82_673_417,
	"vest side merc right": 2_190_410_679,
	"head carrier right": 3_754_366_558,
	"shoulders carrier right": 2_673_897_756,
	"foot carrier right": 3_484_037_146,
	"shaft carrier right": 3_298_463_021,
	"upper carrier right": 2_717_268_126,
	"fore carrier right": 2_717_268_126,
	"thigh carrier right": 2_717_268_126,
	"knee carrier right": 2_717_268_126,
	"shin carrier right": 1_792_825_867,
	"vest front carrier right": 1_891_903_117,
	"vest side carrier right": 20_382_551,
	"head cap right": 1_786_594_904,
	"shoulders cap right": 3_011_958_210,
	"foot cap right": 2_164_598_504,
	"shaft cap right": 3_298_463_021,
	"upper cap right": 2_717_268_126,
	"fore cap right": 2_717_268_126,
	"thigh cap right": 2_717_268_126,
	"knee cap right": 2_717_268_126,
	"shin cap right": 1_792_825_867,
	"vest front cap right": 4_157_658_769,
	"vest side cap right": 4_157_658_769,
	"hand right": 1_587_359_054,
	"hand side right": 1_871_945_428,
}


func describe() -> Dictionary:
	return {
		"name": "The character painters' lit renders are unchanged",
		"description": "A few lit renders of the head, the shoulders and vest, the fist and the "
			+ "limb and shoe strips hash to what they did before the flat read.",
		"tags": ["art", "character", "scripted", "golden"],
		"timeout": 20.0,
	}


func run(t: TestContext) -> void:
	var got := {}
	for spec: Array in _renders():
		var image := PixelArt.render(spec[1], spec[2], spec[3], spec[5], spec[4]).get_image()
		got[spec[0]] = hash(image.get_data())
	var out := OS.get_environment("GOLDEN_OUT")
	if out != "":
		var lines := PackedStringArray()
		for name: String in got:
			lines.append("\t\"%s\": %d," % [name, got[name]])
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string("\n".join(lines) + "\n")
	var wrong := []
	for name: String in got:
		if not GOLDEN.has(name) or GOLDEN[name] != got[name]:
			wrong.append("\"%s\": %d," % [name, got[name]])
	t.check(
		wrong.is_empty(),
		"every lit render is what it was; now:\n%s" % "\n".join(wrong),
	)


## The renders: `[name, painter, size, colour, opts, facing]`.
func _renders() -> Array:
	var looks := _looks()
	var out := []
	for facing: Vector2 in [Vector2.DOWN, Vector2.RIGHT]:
		var f := "down" if facing == Vector2.DOWN else "right"
		for look: String in looks:
			out.append_array(_in_look(look, looks[look], f, facing))
		var glove := Color(0.55, 0.45, 0.38)
		out.append(["hand %s" % f, HandPainter, Vector2(10, 10), glove, {}, facing])
		var left := { "side": -1 }
		out.append(["hand side %s" % f, HandPainter, Vector2(10, 10), glove, left, facing])
	return out


## The renders of every painter in the look `name` (`look`) facing `facing` (`f`).
func _in_look(name: String, look: Dictionary, f: String, facing: Vector2) -> Array:
	var opts := { "look": PixelArt.handle(look) }
	var out := [
		["head %s %s" % [name, f], HeadPainter, Vector2(30, 30), SKIN, opts, facing],
		["shoulders %s %s" % [name, f], BodyPainter, Vector2(28, 28), SHIRT, opts, facing],
	]
	for part in ["foot", "shaft", "upper", "fore", "thigh", "knee", "shin"]:
		var limb := opts.duplicate()
		limb["part"] = part
		var size := Vector2(9, 16) if part == "foot" else Vector2(8, 14)
		out.append(["%s %s %s" % [part, name, f], LimbPainter, size, SHOE, limb, facing])
	for face in ["front", "side"]:
		var vest := opts.duplicate()
		vest["face"] = face
		var size := Vector2(20, 24)
		out.append(["vest %s %s %s" % [face, name, f], VestFacePainter, size, SHIRT, vest, facing])
	return out


## The looks the renders are made in.
func _looks() -> Dictionary:
	return {
		"plain": { "style": "plain" },
		"police": { "style": "plain", "police": true, "feet": "boots" },
		"merc": { "style": "merc", "feet": "boots", "vest": "vest", "vest_col": GREEN, "pack": true,
			"pack_col": Color(0.3, 0.3, 0.2) },
		"carrier": { "style": "plain", "vest": "carrier", "vest_col": GREEN, "front_cover": GREEN,
			"back_cover": GREEN, "shirt": SHIRT, "head": "helmet", "helm": Color(0.3, 0.32, 0.3) },
		"cap": { "style": "plain", "head": "cap", "helm": Color(0.6, 0.2, 0.2),
			"hair": Color(0.2, 0.1, 0.05), "hair_style": "long", "chrome": Color(0.7, 0.7, 0.75) },
	}
