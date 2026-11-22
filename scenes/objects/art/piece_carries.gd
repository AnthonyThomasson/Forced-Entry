class_name PieceCarries
extends RefCounted
## Objects domain, what an emptied piece carries (`docs/stacked-items.md` SI13, decision D21): a
## piece whose look would build loose things in (a shelf's books, a crate stack's crates, a
## pallet's wrapped boxes, a hotplate's plate and pan) draws and builds none of them; the
## things are items (rule 9: free bodies) set where the piece's row names. This is the read of those
## places, as rows `{ key, at, rotated, size, lift, on_top, patch }` a placer sets items by
## (`ObjectFactory.spawn_on` with `rest_at`; World-Gen's `RoomItems.carry`): `key` the item's
## catalogue key, `at` its centre as a plan point (in the space the piece's `position` is in,
## turned the way the piece faces), `size` its footprint in the piece's canonical frame, `lift` the
## height (px above the floor) it stands on and `patch` what differs from the catalogue row (size,
## height, colour, weight, spines).
## A piece says what it carries in its catalogue row's `carries` (`[{ key, at, size, lift, height,
## color, palette, weight, maybe, on_top, plain }]`): `at` from the piece's centre in the canonical
## frame, x across and the front toward +y; `lift` from the floor; `plain` draws the item in its own
## colour, not the run-down grade; `palette` (a list of `ObjectArtDecorConfig.prop_colors`) picks
## its colour by where the piece stands; a `maybe` row is there for about half the
## pieces, by where the piece stands, so a seed's layout says which (a crate stack's third crate);
## an `on_top` row has no `lift`: the item rests on the piece's top under it (a counter's slab, not
## its backsplash) on what is already there, as a home top's desk and counter carry theirs, and
## takes the catalogue item's own `size`. A shelf with `art_opts.loose` says it by `ShelfLoose`, a
## shop's fridge, snack machine or aisle by `ShopStock`, a cyberware shelf by `CyberwareShelf`.

const ShelfLoose = preload("res://scenes/objects/art/shelf_loose.gd")


## Whether the piece a catalogue `definition` says carries things (its mesh and art leave them
## out): it has `carries`, or its `art_opts.loose` says so (a shelf, a shop's aisle, fridge or snack
## machine, the cyberware shelf: `loose` is that gate only; that a piece is hollow is by its kind).
static func carries(definition: Dictionary) -> bool:
	if definition.has("carries"):
		return true
	var opts: Variant = definition.get("art_opts", {})
	return opts is Dictionary and bool((opts as Dictionary).get("loose", false))


## The carrying rows of the piece `definition` says, in the canonical frame of `spec` (its
## footprint, either way round): its own `carries`, else what a loose shelf holds.
static func canonical(definition: Dictionary, spec: FurnitureSpec) -> Array:
	var own: Array = definition.get("carries", [])
	if own.is_empty() and spec.art == "shelf":
		return ShelfLoose.rows(spec)
	if own.is_empty() and spec.art == "shop":
		return ShopStock.rows(spec)
	if own.is_empty() and spec.art == "clinic":
		return CyberwareShelf.rows(spec)
	return own


## The rows of `base` (a furniture node) from its catalogue `definition`; none for a piece that
## carries nothing.
static func rows(definition: Dictionary, base: Node2D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not carries(definition):
		return out
	var spec := FurnitureSpec.of(base)
	for row: Dictionary in canonical(definition, spec):
		if row.get("maybe", false) and hash([base.position, row["key"], row["lift"]]) % 2 != 0:
			continue
		var patch := patch_of(row)
		if row.has("palette"):  # A colour of a prop palette, picked by where the piece stands.
			patch["color"] = _palette_pick(row["palette"], hash([base.position, row["key"]]))
		out.append({
			"key": row["key"],
			"at": base.position + (row["at"] as Vector2).rotated(spec.turns * PI * 0.5),
			"rotated": spec.turns % 2 == 1,
			"size": row.get("size", Vector2.ZERO),
			"lift": float(row.get("lift", 0.0)),
			"on_top": bool(row.get("on_top", false)),
			"patch": patch,
		})
	return out


## The colour of `ObjectArtDecorConfig.prop_colors[list]` that `roll` picks.
static func _palette_pick(list: String, roll: int) -> Color:
	var colours: Array = ObjectArtDecorConfig.prop_colors[list]
	return colours[absi(roll) % colours.size()]


## What a carrying `row` changes in its item's catalogue row (`patched`): its footprint, colour,
## weight, height, spines and `well` (the colour of what fills a bowl), and `plain` for a home top's
## item and for a row that says `plain` (a sandbag, the hat): it keeps the old prop's own colour,
## not the run-down grade a catalogue colour is drawn in.
static func patch_of(row: Dictionary) -> Dictionary:
	var patch := {}
	for field: String in ["size", "color", "weight", "height", "spines", "well"]:
		if row.has(field):
			patch[field] = row[field]
	if row.get("on_top", false) or row.get("plain", false):
		patch["plain"] = true
	return patch


## `item` (a catalogue row) with a carrying row's `patch` applied: its footprint, its colour, its
## weight, its height and `plain` (in its `art_opts`, where the mesh reads them).
static func patched(item: Dictionary, patch: Dictionary) -> Dictionary:
	var out := item.duplicate(true)
	for field: String in ["size", "color", "weight"]:
		if patch.has(field):
			out[field] = patch[field]
	var opts: Dictionary = out.get("art_opts", {})
	for field: String in ["height", "spines", "plain", "well"]:
		if patch.has(field):
			opts[field] = patch[field]
	out["art_opts"] = opts
	return out
