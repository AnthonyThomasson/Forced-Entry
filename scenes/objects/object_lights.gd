extends RefCounted
## Objects domain (private): the lights a piece gives, its `get_lights()` declaration (read
## duck-typed by the Lighting domain, which gives each one a PointLight2D under the piece). What
## gives light is what the piece's painter draws glowing: a lamp's bulb, a screen's face (a TV, a
## desk's monitor, the den's monitor wall, the rig's halo, a cart's display), a neon tube, a server
## rack's LEDs, the scanner's beam, the hot ring, the surgeon's lamp, a street lamp's lens or sign,
## and a piece's neon trim. Each light is plain data, in the piece's own frame:
##   `offset` (Vector2) and `turn` (rad, the pool's long axis from +x), `colour`, `energy`, `radius`
##   (px, out along the long axis), `shape` (`round` / `wide` / `tube`), `rhythm`
##   (`[[mode, weight], ...]`, the rhythms it may be drawn with), `room_light` (it lights its room),
##   `street` (it lights the street too: a street lamp), `height` (`overhead`: it hangs or stands
##   above the heads, a lamp's bulb, a street lamp's head; `low`: a screen, a tube, LEDs; which
##   shadows it, and whether it pools downward, is the Lighting domain's) and `glow` (the piece's
##   `Emissive` overlay that shows the source, dimming with the light; null when it has none).
## Tuning: ObjectArtConfig.light_specs (the per-kind numbers) and the painters' colours.

const Decay = preload("res://scenes/objects/art/decay.gd")


## The lights `piece` (an EnvironmentObject in the tree, its visuals ready) gives; [] for a piece
## that gives none.
static func of(piece: Node2D) -> Array:
	var kind := _kind(piece)
	if kind == "":
		return []
	var spec: Dictionary = ObjectArtConfig.light_specs.get(kind, {})
	if spec.is_empty():
		return []
	var ahead: Vector2 = (piece.facing as Vector2).normalized()
	if ahead == Vector2.ZERO:
		ahead = Vector2.DOWN
	var neon := Decay.neon(piece.art_opts)
	var light := {
		"offset": _front_offset(piece.size, ahead, spec),
		"turn": 0.0,
		"colour": neon if neon.a > 0.0 else ObjectArtConfig.decay_screen_color,
		"energy": float(spec["energy"]),
		"radius": float(spec.get("radius", 0.0)),
		"shape": spec.get("shape", &"round"),
		"rhythm": spec.get("rhythm", []),
		"room_light": spec.get("room_light", false),
		"street": false,
		"height": spec.get("height", &"low"),
		"glow": _overlay(piece.get_node_or_null("EnvironmentObjectVisuals")),
	}
	_by_kind(light, kind, piece, ahead, spec)
	return [light]


## Where a light of `spec` sits in a piece of footprint `size` facing `ahead`: its row's `ahead` px
## out from the front edge, or the centre for a row without one.
static func _front_offset(size: Vector2, ahead: Vector2, spec: Dictionary) -> Vector2:
	if not spec.has("ahead"):
		return Vector2.ZERO
	return ahead * (absf(size.dot(ahead)) * 0.5 + float(spec["ahead"]))


## Set what `kind` changes of `light` (a row `of` filled with a screen's defaults, the piece's
## `spec`): its colour, the turn of its pool, its reach, and a street lamp's head.
static func _by_kind(
	light: Dictionary,
	kind: String,
	piece: Node2D,
	ahead: Vector2,
	spec: Dictionary,
) -> void:
	var opts: Dictionary = piece.art_opts
	var size: Vector2 = piece.size
	var neon := Decay.neon(opts)
	var spill := ahead.angle() + PI * 0.5  # A screen's pool lies across its front.
	match kind:
		"lamp":
			light["colour"] = neon if neon.a > 0.0 else ObjectArtConfig.lamp_glow_color
		"tv", "desk":
			light["turn"] = spill
		"monitor_wall":
			light["turn"] = spill
			light["radius"] = maxf(absf(size.dot(ahead.orthogonal())) * 0.85, light["radius"])
		"server_rack":
			light["colour"] = neon if neon.a > 0.0 else ObjectArtConfig.tech_led_colors[-1]
		"surgical":
			light["colour"] = ObjectArtConfig.recliner_lamp_color
		"scanner":
			light["turn"] = ahead.angle()  # The beam runs out along the post's face.
			light["colour"] = ObjectArtConfig.security_beam_color
		"hotplate":
			light["colour"] = ObjectArtConfig.hotplate_ring_color
		"neon_tube":
			light["colour"] = Decay.neon({ "neon": opts.get("tone", "cyan") })
			light["turn"] = 0.0 if size.x >= size.y else PI * 0.5  # Along the tube.
			light["radius"] = maxf(size.x, size.y) * float(spec["tube_reach"])
		"cobra", "sign":
			_street_head(light, kind, piece, neon)
		"trim":
			light["colour"] = neon
			light["radius"] += maxf(size.x, size.y) * 0.5


## A street lamp's `light`: at its `Overhang`'s centre, that overlay its glow, the cobra's lens
## colour or the sign's `neon` (magenta without one), lighting the street.
static func _street_head(light: Dictionary, kind: String, piece: Node2D, neon: Color) -> void:
	var overhang := piece.get_node_or_null("Overhang")
	if overhang != null:
		light["offset"] = (overhang.get_rect() as Rect2).get_center()
		light["glow"] = _overlay(overhang)
	light["colour"] = ObjectArtConfig.streetlight_lens_color if kind == "cobra" \
		else (neon if neon.a > 0.0 else ObjectArtConfig.neon_magenta)
	light["street"] = true


## Which row of ObjectArtConfig.light_specs `piece` gives light by ("" for none): by its painter and
## options, or, for a piece with a neon option and no light of its own, its trim.
static func _kind(piece: Node2D) -> String:
	var art: String = piece.art
	var opts: Dictionary = piece.art_opts
	match art:
		"lamp", "hotplate":
			return art
		"tech":
			return String(opts.get("kind", "monitor_wall"))
		"recliner":
			return String(opts.get("kind", "rig"))
		"streetlight":
			return String(opts.get("head", ObjectArtConfig.streetlight_head))
		"decor":
			return "neon_tube" if String(opts.get("kind", "")) == "neon_tube" else ""
	var own := _variant_kind(art, opts)
	return own if own != "" or Decay.neon(opts).a <= 0.0 else "trim"


## The light row of a piece whose painter gives light only in some of its variants (a TV among the
## appliances, a desk with a monitor, the tool cart, the scanner post); "" for any other.
static func _variant_kind(art: String, opts: Dictionary) -> String:
	var kind := String(opts.get("kind", ""))
	match art:
		"appliance":
			return "tv" if String(opts.get("panel", "")) == "tv" else ""
		"table":
			var is_monitor := func(p: Variant) -> bool:
				return p is Dictionary and p.get("kind", "") == "monitor"
			return "desk" if (opts.get("props", []) as Array).any(is_monitor) else ""
		"clinic":
			return "tool_cart" if kind == "tool_cart" else ""
		"security":
			return "scanner" if kind == "scanner" else ""
	return ""


## The `Emissive` overlay of visuals node `visuals` (null without one).
static func _overlay(visuals: Node) -> CanvasItem:
	if visuals == null or not visuals.has_method(&"emissive_layer"):
		return null
	return visuals.call(&"emissive_layer") as CanvasItem
