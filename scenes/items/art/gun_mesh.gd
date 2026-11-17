class_name GunMesh
extends RefCounted
## Items domain, a gun's 3D mesh and its art (`domain-art/meshes.md`): the 2D gun, stood up.
## The mesh is the silhouette of the painter's flat render (`PixelArt.render_flat`, the pixels it
## drew) lifted to a height per part (`ItemSolid`), its barrel round, and the very same flat art is
## projected straight down onto it (`MeshNodes.textured`, rect from `held_rect` / `lying_rect`), so
## seen from above the held gun is the 2D gun, at the size of the 2D gun. One mesh and one texture
## per gun and look, shared by every character holding it (`MeshCache`, `PixelArt`'s cache); the
## character's body places it (`GunArt.held_mesh`, `domain-character`).
##
## Held, the frame is the one the 2D art is drawn in, turned to 3D: the origin is the weapon hand's
## grip and the muzzle leads along +z (2D "ahead"), the butt `grip_back` behind the origin, up is
## +y, the gun centred about the hand's height (`ItemMeshConfig.held_base`). Lying, it is the side
## profile (`opts.flat` of the painter) lifted as thick as the gun is wide, centred on the origin,
## muzzle along +z, its underside on y = 0.

const WeaponArt = preload("res://scenes/items/art/weapon_art.gd")
## How many flat faces round the barrel (a vertex up and one to each side, so its width is the
## art's).
const BARREL_FACETS := 8


## The mesh of `gun` (a `GunConfig` row id) held, drawn in `look` (`GunConfig.look`, `handle` its
## `PixelArt.handle`), cached by the row's size, the look and the tuning. Null for an unknown gun.
static func held(gun: StringName, look: Dictionary, handle: int) -> Mesh:
	var row := GunConfig.row(gun)
	if row.is_empty() or look.is_empty():
		return null
	var art: Vector2 = row["art_size"]
	var key := MeshCache.key("held_gun", art, look["body"], _opts(look, {
		"grip": float(row["grip_back"]), "thickness": ItemMeshConfig.thickness,
		"base": ItemMeshConfig.held_base, "facets": BARREL_FACETS,
	}))
	return MeshCache.fetch(key, _make_held.bind(gun, look, handle))


## The mesh of `gun` lying on its side (`flip`: the side up), in `look`: its profile's silhouette,
## as thick as the gun is wide.
static func lying(gun: StringName, look: Dictionary, handle: int, flip: bool) -> Mesh:
	var row := GunConfig.row(gun)
	if row.is_empty() or look.is_empty():
		return null
	var key := MeshCache.key("lying_gun", row["flat_size"], look["body"], _opts(look, {
		"width": float((row["art_size"] as Vector2).x), "thickness": ItemMeshConfig.thickness,
		"shares": [
			ItemMeshConfig.lying_stock,
			ItemMeshConfig.lying_guard,
			ItemMeshConfig.lying_barrel,
		],
		"flip": flip,
	}))
	return MeshCache.fetch(key, _make_lying.bind(gun, look, handle, flip))


## The flat art of `gun` held (the painter's unlit render, muzzle toward +y), the texture of
## `held`'s mesh; null for an unknown gun.
static func held_texture(gun: StringName, look: Dictionary, handle: int) -> Texture2D:
	var row := GunConfig.row(gun)
	if row.is_empty() or look.is_empty():
		return null
	return PixelArt.render_flat(
		look["painter"], row["art_size"], look["body"],
		{ "gun": gun, "look": handle, "material": look["finish"] },
	)


## The flat art of `gun` lying on its side (`flip`: the side up), the texture of `lying`'s mesh.
static func lying_texture(gun: StringName, look: Dictionary, handle: int, flip: bool) -> Texture2D:
	var row := GunConfig.row(gun)
	if row.is_empty() or look.is_empty():
		return null
	return PixelArt.render_flat(
		look["painter"], row["flat_size"], look["body"],
		{ "gun": gun, "look": handle, "flat": true, "flip": flip, "material": look["finish"] },
	)


## Where the held art lies in the held mesh's frame (px): the art's footprint, its butt `grip_back`
## behind the origin; the `rect` `MeshNodes.textured` is given.
static func held_rect(gun: StringName) -> Rect2:
	var row := GunConfig.row(gun)
	var art: Vector2 = row.get("art_size", Vector2.ZERO)
	return Rect2(Vector2(-art.x * 0.5, -float(row.get("grip_back", 0.0))), art)


## Where the flat art lies in the lying mesh's frame (px): its footprint about the origin.
static func lying_rect(gun: StringName) -> Rect2:
	var flat: Vector2 = GunConfig.row(gun).get("flat_size", Vector2.ZERO)
	return Rect2(-flat * 0.5, flat)


## The held gun: its silhouette lifted part by part, the barrel round.
static func _make_held(gun: StringName, look: Dictionary, handle: int) -> Mesh:
	var kit := MeshKit.new()
	kit.sides = BARREL_FACETS
	var image := held_texture(gun, look, handle).get_image()
	var solid := ItemSolid.of(image, held_rect(gun))
	var parts := _parts(gun, look, image.get_size())
	var barrel_from := solid.runs.size()
	if parts.has("barrel"):
		barrel_from = (parts["barrel"] as Rect2i).position.y + 1
	var height := func(row: int) -> float:
		return _part_height(parts, row) * ItemMeshConfig.thickness
	solid.slab(kit, ItemMeshConfig.held_base, height, 0, barrel_from)
	solid.bar(kit, ItemMeshConfig.held_base, barrel_from)
	return kit.build()


## The gun lying on its side: the profile's silhouette, a slab as thick as the gun is wide.
static func _make_lying(gun: StringName, look: Dictionary, handle: int, flip: bool) -> Mesh:
	var kit := MeshKit.new()
	var image := lying_texture(gun, look, handle, flip).get_image()
	var thick: float = (GunConfig.row(gun)["art_size"] as Vector2).x * ItemMeshConfig.thickness
	var profile := _profile(gun, look, image.get_size())
	var height := func(row: int) -> float: return thick * _lying_share(profile, row)
	ItemSolid.of(image, lying_rect(gun)).slab(kit, 0.0, height)
	return kit.build()


## The side profile's measures on a picture of `size` px (`WeaponArt.flat_profile`).
static func _profile(gun: StringName, look: Dictionary, size: Vector2i) -> Dictionary:
	var canvas := PixelCanvas.new(size.x, size.y, 0, Vector2.ZERO)
	return WeaponArt.flat_profile(canvas, gun, _crude(look))


## How much of the gun's full thickness a lying gun has at picture row `row`: the stock, the
## receiver, the hand guard and the barrel post each their own (`ItemMeshConfig.lying_*`).
static func _lying_share(profile: Dictionary, row: int) -> float:
	if row > int(profile["guard_end"]):
		return ItemMeshConfig.lying_barrel
	if row > int(profile["body_end"]):
		return ItemMeshConfig.lying_guard
	if row < int(profile["stock_end"]):
		return ItemMeshConfig.lying_stock
	return 1.0


## Whether the look's painter draws the crude (pipe) silhouette (its `SILHOUETTE` constant).
static func _crude(look: Dictionary) -> bool:
	var painter: Script = look["painter"]
	var silhouette: Dictionary = painter.get_script_constant_map().get("SILHOUETTE", {})
	return silhouette.get("crude", false)


## The rects of the held gun's parts on a picture of `size` px (`WeaponArt.held_parts`).
static func _parts(gun: StringName, look: Dictionary, size: Vector2i) -> Dictionary:
	var canvas := PixelCanvas.new(size.x, size.y, 0, Vector2.ZERO)
	return WeaponArt.held_parts(canvas, gun, _crude(look))


## How tall (px) the held gun stands at picture row `row`: the tallest part that covers it
## (`WeaponArt.HELD_PARTS` heights, the ones the 2D art casts its shadows by).
static func _part_height(parts: Dictionary, row: int) -> float:
	var tallest := 0
	for part: String in parts:
		var rect: Rect2i = parts[part]
		if row >= rect.position.y and row < rect.end.y:
			tallest = maxi(tallest, WeaponArt.HELD_PARTS[part])
	return float(tallest)


## `extra` with every colour `look` names added (the mesh key's options).
static func _opts(look: Dictionary, extra: Dictionary) -> Dictionary:
	var opts := extra.duplicate()
	opts["painter"] = (look["painter"] as Script).resource_path
	for name: String in look:
		if look[name] is Color:
			opts[name] = (look[name] as Color).to_html()
	return opts
