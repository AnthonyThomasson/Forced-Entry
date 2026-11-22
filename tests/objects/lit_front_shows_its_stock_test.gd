extends GameTest
## A fridge's and a snack machine's lit front has a window for each bottle or pack (#194 unbake-c,
## D21 "the old look kept", `docs/stacked-items.md` SI16): the stock stands against the glass, and
## the pane it stands behind is cut away where each item is, so the free stock shows against the
## glow and not behind a blank pane. The front's area is its rectangle less its windows; a window
## is where a bottle or pack of a row stands.

const ShopMesh := preload("res://scenes/objects/art/shop_mesh.gd")
const PIECES := [["fridge", "drinks_fridge", 24], ["snack", "snack_machine", 8]]


func describe() -> Dictionary:
	return {
		"name": "A lit shop front has a window for each of its stock",
		"description": "The glowing front of the drinks fridge and of the snack machine is its "
			+ "pane less a window at each bottle or pack, and the stock stands against the "
			+ "glass, so a player sees the bottles and packs, not a blank pane.",
		"tags": ["furniture", "3d", "items", "art", "unbake"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 200))
	for i in PIECES.size():
		s.object(StringName(PIECES[i][0]), PIECES[i][1], Vector2(100.0 + 150.0 * i, 100.0))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	for entry: Array in PIECES:
		var piece: Node2D = t.object(StringName(entry[0]))
		var spec := FurnitureSpec.of(piece)
		var windows := ShopStock.windows(spec)
		t.check(
			windows.size() == entry[2],
			"%s: a window for each of its %d items (%d)" % [entry[0], entry[2], windows.size()],
		)
		_stands_at_the_glass(t, entry[0], spec)
		_front_is_cut(t, entry[0], piece, windows)


## Every row of the stock stands in the last few px before the glass.
func _stands_at_the_glass(t: TestContext, name_: String, spec: FurnitureSpec) -> void:
	var bay: Dictionary = ShopHollow.bays(spec)[0]
	var area: Rect2 = bay["area"]
	for row: Dictionary in ShopStock.rows(spec):
		var back: float = row["at"].y + spec.size.y * 0.5 + row["size"].y * 0.5
		if absf(back - area.end.y) > ShopStock.FRONT_GAP + 0.01:
			t.fail("%s: a row of stock stands %.1f px from the glass" % [name_, area.end.y - back])
			return
	t.check(true, "%s: the stock stands at the glass" % name_)


## The area (px squared) of the lit pane of `spec` before its windows: the bay's width by the
## height of the glass.
func _pane(name_: String, spec: FurnitureSpec) -> float:
	var width: float = (ShopHollow.bays(spec)[0]["area"] as Rect2).size.x
	if name_ == "snack":
		return width * ShopHollow.SNACK_WINDOW
	return width * (ShopMesh.height_of(spec) - ShopHollow.FRAME - ShopHollow.KICK)


## The lit pane's front-facing area is its rectangle less the windows (3D units squared).
func _front_is_cut(t: TestContext, name_: String, piece: Node2D, windows: Array[Rect2]) -> void:
	var rig := ShopMesh.build(piece)
	var faces := (rig.glows[0] as MeshInstance3D).mesh.get_faces()
	var area := 0.0
	for k in range(0, faces.size(), 3):
		var normal := (faces[k + 1] - faces[k]).cross(faces[k + 2] - faces[k])
		if normal.normalized().z > 0.9:
			area += normal.length() * 0.5
	var cut := 0.0
	for window in windows:
		cut += window.size.x * window.size.y
	var expected := (_pane(name_, FurnitureSpec.of(piece)) - cut) * pow(RenderConfig.unit, 2.0)
	t.check(
		absf(area - expected) < 0.5,
		"%s: the lit front is its pane less the windows (%.1f against %.1f)"
		% [name_, area, expected],
	)
	rig.free()
