extends GameTest
## R3 (ticket #61, weapon style follows the wielder): a gun or grenade is shown in its weapon style
## (`ItemArt.style`: `police` issue, taped `scrap` or `pipe`), and an item never given one is shown
## as `police`. For each gun (pistol, SMG, rifle) and grenade (frag, stun), one item per style and
## one never given a style, each read through the art the 3D render shows (the mesh and the flat
## texture its `art` hands out, `tests/_items/weapon_style_probe.gd`):
## - two `police` items of a kind look alike (the comparison's premise: the same look gives the
##   same mesh and texture);
## - held (`held_mesh`, `held_texture`) and lying with either side up (`dropped_mesh`,
##   `dropped_texture`, as a dropped gun lies and a grenade flies and rests), each style looks
##   different from every other style;
## - the item never given a style has the style `police` and looks as the `police` one, held and
##   lying.

const StyleProbe := preload("res://tests/_items/weapon_style_probe.gd")
## The looks compared for each item: held, and lying with each side up.
const VIEWS := [&"held", &"lying", &"lying_flipped"]


func describe() -> Dictionary:
	return {
		"name": "A weapon style changes how a gun or grenade looks",
		"description": "Each gun and grenade looks different in police, scrap and pipe, held and "
			+ "lying either side up; an item with no style looks as police.",
		"tags": ["style", "item", "gun", "grenade", "art"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var kinds := {}  # name -> slot
	kinds.merge(StyleProbe.GUNS)
	kinds.merge(StyleProbe.GRENADES)
	var styles: Array = StyleProbe.STYLES + [&"", &"twin"]
	for kind: StringName in kinds:
		var seen := {}  # style -> view -> set
		for style: StringName in styles:
			seen[style] = _looks(t, kind, kinds[kind], style)
			for view: StringName in VIEWS:
				t.check(
					not seen[style][view].is_empty(),
					"the %s (%s) shows something %s" % [kind, _name(style), view],
				)
		for view: StringName in VIEWS:
			_check_view(t, kind, view, seen)


## What one `kind` item (inventory `slot`) in `style` (`&"twin"` = a second police item) shows, view
## -> set of instance ids: held, and lying either side up.
func _looks(t: TestContext, kind: StringName, slot: int, style: StringName) -> Dictionary:
	var as_style := StyleProbe.DEFAULT_STYLE if style == &"twin" else style
	var item := StyleProbe.make(slot, as_style)
	if style == &"":
		t.expect_eq(
			item.art.style,
			StyleProbe.DEFAULT_STYLE,
			"a %s never given a style has the style police (ItemArt.style)" % kind,
		)
	return {
		&"held": StyleProbe.held(item),
		&"lying": StyleProbe.lying(item, false),
		&"lying_flipped": StyleProbe.lying(item, true),
	}


## Check `kind`'s looks (`drawn`, style -> view -> set) in `view`: two police items alike (the
## premise), every style apart from every other, the one never given a style as police.
func _check_view(t: TestContext, kind: StringName, view: StringName, drawn: Dictionary) -> void:
	if not t.check(drawn[&"twin"][view] == drawn[&"police"][view],
			"two police %ss look alike %s (the comparison's premise)" % [kind, view]):
		return
	for i in StyleProbe.STYLES.size():
		for j in range(i + 1, StyleProbe.STYLES.size()):
			var a := StyleProbe.STYLES[i]
			var b := StyleProbe.STYLES[j]
			t.check(
				drawn[a][view] != drawn[b][view],
				"%s, a %s %s and a %s %s look different" % [view, a, kind, b, kind],
			)
	t.check(
		drawn[&""][view] == drawn[&"police"][view],
		"%s, a %s never given a style looks like a police one" % [view, kind],
	)


## How a style is named in a message.
func _name(style: StringName) -> String:
	match style:
		&"":
			return "no style"
		&"twin":
			return "a second police"
	return String(style)
