class_name ShopStock
extends RefCounted
## Objects domain, what a shop's fridge, snack machine and shelf aisle hold (`docs/stacked-items.md`
## SI16, decision D21): the bottles of the drinks fridge, the snack packs of the machine and the
## goods on an aisle's boards that `shop_mesh.gd` used to build in, as rows for loose items to
## stand where they stood (`PieceCarries`; the pattern is `shelf_loose.gd`). A row is `{ key, at,
## size, lift, height, color, spines }`: the item's catalogue key (`bottles`, `snacks`), its centre
## from the piece's centre in the canonical frame (x across, the front toward +y), its footprint,
## the board's top it stands on, how tall it is, and its `spines` (`[[x from the run's left, width,
## height, colour]]`) the mesh draws, so one run of up to `RUN ` is one body, not a dozen. The
## colours are seeded from the piece's look, so every piece of one look holds the same.

const ShopMesh = preload("res://scenes/objects/art/shop_mesh.gd")
## The most bottles or packs in one run, and the gap left between two runs (px).
const RUN := 4
const GAP := 3.0
## How wide a bottle and a pack stand (px), and the gap between two in a run.
const WIDTHS := { "bottles": 5.0, "snacks": 5.0 }
const SPACE := 0.6
## A bottle's and a pack's height as a share of the room above its board.
const SHARE := { "bottles": 0.85, "snacks": 0.75 }


## The rows of the shop piece `spec` (`ShopHollow.has`); `[]` for any other.
static func rows(spec: FurnitureSpec) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not ShopHollow.has(spec):
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([spec.size, ShopMesh.kind_of(spec)])
	for bay: Dictionary in ShopHollow.bays(spec):
		for top: float in bay["tops"]:
			_board(spec, bay, top, rng, out)
	return out


## The runs along one board of `bay`.
static func _board(
	spec: FurnitureSpec,
	bay: Dictionary,
	top: float,
	rng: RandomNumberGenerator,
	out: Array[Dictionary],
) -> void:
	var key: String = bay["key"]
	var area: Rect2 = bay["area"]
	var run_width: float = RUN * (WIDTHS[key] + SPACE) - SPACE
	var runs := maxi(1, int((area.size.x + GAP) / (run_width + GAP)))
	var slack: float = area.size.x - runs * run_width - (runs - 1) * GAP
	var high := roundf(float(bay["room"]) * SHARE[key])
	for run in runs:
		var left: float = area.position.x + slack * 0.5 + run * (run_width + GAP)
		var spines := _spines(key, high, rng)
		var centre := Vector2(left + run_width * 0.5, area.position.y + area.size.y * 0.5)
		out.append({
			"key": key,
			"at": centre - spec.size * 0.5,
			"size": Vector2(roundf(run_width), float(bay["depth"])),
			"lift": top,
			"height": high,
			"color": spines[0][3],
			"spines": spines,
		})


## The `RUN` bottles or packs of one run: `[[x from the left, width, height, colour]]`, each a
## colour of the shop's palette and a little shorter than the room, by `rng`.
static func _spines(key: String, high: float, rng: RandomNumberGenerator) -> Array:
	var palette: Array[Color] = ObjectArtShopConfig.shop_packs
	var spines: Array = []
	for k in RUN:
		var tall := high - float(rng.randi_range(0, 2))
		var colour := palette[rng.randi() % palette.size()]
		spines.append([k * (WIDTHS[key] + SPACE), WIDTHS[key], tall, colour])
	return spines
