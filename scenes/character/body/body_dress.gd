class_name BodyDress extends RefCounted
## What each part of the body is drawn in (`character_visuals.gd`'s `dress`): the character's style
## (`Character.style`, `look_seed`, `rank`; `docs/outfits.md`, styles) and what it wears drawn in
## that style (`Outfit.look(style)`), resolved through `character_style.gd` and registered for the
## painters (`PixelArt.handle`: they get its handle). Resolved again (`refresh`) only when the
## outfit (`Outfit.revision`) or the style changes, so the per-frame cost is two ints compared. The
## visuals draw the shoulders, the head and the fists in it, the limbs and the trunk their parts.

const CharacterStyle = preload("res://scenes/character/body/character_style.gd")
const VestPainter = preload("res://scenes/character/body/art/vest_painter.gd")

## The shoulders, the trunk and a sleeve.
var shirt := Color.WHITE
## The thighs and shins.
var pants := Color.WHITE
## The shoes, and a boot's shaft.
var shoes := Color.WHITE
## Boots: a laced shaft up the shin over the shoe.
var boots := false
## The neck, the head's skin and bare arms.
var skin := Color.WHITE
## BodyPainter's options (the look's handle, the plates and their wear).
var shoulder_opts := {}
## TorsoPainter's options by face ("front" / "back" / "side").
var torso_opts := {}
## HeadPainter's options.
var head_opts := {}
## Per side: each arm segment ("upper", "fore") as `{ color, material, opts }`: a sleeve, bare skin
## or chrome.
var arm_parts: Array[Dictionary] = []
## Per side: LimbPainter's options by leg part ("thigh", "knee", "shin", "shaft", "foot"), and
## `chrome`: whether the shin is chrome.
var leg_opts: Array[Dictionary] = []
## Per hand: the fist's `color` and painter `opts`.
var hand_parts: Array[Dictionary] = []
## A hash of the resolved look: joins the visuals' redraw key, and repaints a settled fallen body
## when it changes.
var look_key := 0
## A chrome limb.
var _chrome := Color.WHITE
## The outfit revision the look was last resolved for.
var _worn_revision := -1
## The character's look revision (its style, seed and rank) it was last resolved for.
var _style_revision := -1


## Resolve the look of `character` again if its outfit or its style changed since the last time:
## the shirt, pants and shoes (boots: a laced shaft up the shin), the skin, each arm's sleeve, bare
## skin or chrome, a chrome shin, each fist (gloves, skin or chrome), and the plates' colours and
## wear, rounded to `VestPainter.WEAR_STEPS`. Returns whether the resolved look changed.
func refresh(character: Node) -> bool:
	var outfit: Outfit = character.outfit()
	if outfit.revision == _worn_revision and character._look_revision == _style_revision:
		return false
	_worn_revision = outfit.revision
	_style_revision = character._look_revision
	var style: StringName = character.style
	var worn := outfit.look(style)
	var look := CharacterStyle.resolve(style, character.look_seed, character.rank, worn)
	var id := PixelArt.handle(look)
	shirt = _colour(look["shirt"])
	pants = _colour(look["pants_col"])
	shoes = _colour(look["feet_col"])
	boots = look["feet"] == "boots"
	skin = look["skin"]
	_chrome = look["chrome"]
	shoulder_opts = _dress_plates(worn, id)
	torso_opts = {}
	for face in ["front", "back", "side"]:
		torso_opts[face] = { "face": face, "pants": pants }.merged(shoulder_opts)
	head_opts = { "look": id }
	_dress_sides(look, id)
	var key := hash([
		shirt, pants, shoes, boots, skin, arm_parts, shoulder_opts, head_opts, leg_opts, hand_parts,
	])
	if key == look_key:
		return false
	look_key = key
	return true


## Side `i`'s shin colour: chrome on a chrome leg, else the trousers.
func shin_colour(i: int) -> Color:
	return _chrome if leg_opts[i]["chrome"] else pants


## The shoulders' painter options for the look's handle `id`: the plates `worn` and their wear,
## rounded to `VestPainter.WEAR_STEPS`, painted in fabric (`PixelArt`'s `material` option). The
## torso's options take them too.
static func _dress_plates(worn: Dictionary, id: int) -> Dictionary:
	var dress := { "look": id }
	for side in ["front", "back"]:
		var plate: Dictionary = worn.get(side + "_plate", {})
		if not plate.is_empty():
			dress[side + "_plate"] = plate.get("color", Color.GRAY)
			dress[side + "_wear"] = ceili((1.0
					- clampf(float(plate.get("condition", 1.0)), 0.0, 1.0))
					* VestPainter.WEAR_STEPS)
	dress["material"] = "fabric"
	return dress


## What each side is drawn in, from `look` (handle `id`): each arm segment, each leg part's options
## and a chrome shin, and each fist's colour (gloves, skin or chrome) and options.
func _dress_sides(look: Dictionary, id: int) -> void:
	arm_parts = []
	leg_opts = []
	hand_parts = []
	var glove: Color = look["glove"]
	for i in 2:
		arm_parts.append({
			"upper": _arm_part(look, id, i, "upper"),
			"fore": _arm_part(look, id, i, "fore"),
		})
		leg_opts.append(_leg_parts(look, id, i))
		var chrome: bool = look["chrome_arm"][i]
		var hand := { "look": id, "side": -1 if i == 0 else 1 }
		if chrome:
			hand["chrome"] = true
		hand_parts.append({ "color": _chrome if chrome else glove, "opts": hand })


## Side `i`'s LimbPainter options by leg part in `look` (handle `id`), and whether its shin is
## chrome (`chrome`). Each part's `material` (`PixelArt`'s option): the trousers fabric, a chrome
## shin metal, the boot's shaft and the shoe none.
func _leg_parts(look: Dictionary, id: int, i: int) -> Dictionary:
	var parts := {}
	for part in ["thigh", "knee", "shin", "shaft", "foot"]:
		parts[part] = { "look": id, "part": part, "side": i }
	var chrome: bool = look["chrome_leg"][i]
	parts["chrome"] = chrome
	if chrome:
		parts["shin"]["chrome"] = true
	for part in ["thigh", "knee", "shin"]:
		parts[part]["material"] = "metal" if part == "shin" and chrome else "fabric"
	return parts


## Side `side`'s arm segment `part` ("upper" to the elbow, "fore" to the fist) in `look` (handle
## `id`): chrome, a sleeve (a long one down to its cuff at the wrist) or bare skin, its painter
## options carrying its `material` (`PixelArt`'s option: metal, fabric, none for skin).
func _arm_part(look: Dictionary, id: int, side: int, part: String) -> Dictionary:
	var opts := { "look": id, "part": part, "side": side }
	if look["chrome_arm"][side]:
		opts["chrome"] = true
		opts["material"] = "metal"
		return { "color": _chrome, "opts": opts }
	var sleeve: Variant = look["sleeves"][side]
	if sleeve != null and (part == "upper" or look["body"] == "long_sleeves"):
		opts["cuff"] = part == "fore"
		opts["material"] = "fabric"
		return { "color": sleeve, "opts": opts }
	opts["skin"] = true
	return { "color": skin, "opts": opts }


## `value` if it is a colour, else a neutral grey (a part its style names no colour for).
static func _colour(value: Variant) -> Color:
	return value if value is Color else Color.GRAY
