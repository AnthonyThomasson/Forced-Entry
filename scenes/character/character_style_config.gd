class_name CharacterStyleConfig
## The character styles (`docs/outfits.md` O15; scenes/character/): the style rows (side, police,
## weapons, palettes, looks) and the default style. A `class_name` holder of `static var`s, read as
## `CharacterStyleConfig.<name>`; there is no instance and no autoload.

## What the defenders' crew styles (`merc`, `borg`) draw where nothing is worn (a row's `bare`).
const CREW_BARE := { "body": "top", "pants": "cargo", "feet": "boots" }
## The crew styles' skin tones (a row's `skin`).
const CREW_SKIN := [
	Color(0.96, 0.80, 0.66), Color(0.88, 0.68, 0.52), Color(0.74, 0.54, 0.38),
	Color(0.56, 0.38, 0.26), Color(0.38, 0.26, 0.18), Color(0.82, 0.76, 0.70),
	Color(0.66, 0.62, 0.55),
]

## The style of a character never given one (a test's puppet, a dummy, the gun range): the invaders'
## Zenitex.
static var default_style: StringName = &"zenitex"
## One row per style. What a garment looks like in a style is its `OutfitConfig` row's `looks`; a
## row here is the rest of the look, and each character's own variety within it, drawn from its
## `look_seed`:
##   side         the faction a match styles in it (`MatchBuilder.style`): `invader` (the police
##   units) or `household`. police       a uniformed police unit (its rank marks, its livery's
##   marks) rather than a criminal's gear. weapons      the weapon styles (`ItemArt.style`) a
##   character in it is armed with, one drawn per character. palettes     name -> colours, one drawn
##   per character and palette (a garment look's `palette`; a police unit's are single). bare
##   garment slot -> the palette of what is drawn where nothing is worn there (`body`, `pants`,
##                `feet`). skin, hair   the skin tones and hair colours drawn from; `hair_styles`
##                style -> weight (`short`, `long`, `buzz`, `bald`, `mohawk`).
##   glove        the gloves' colour, worn with chance `gloves` (else the fists are bare skin).
##   pack         the chance of a pack on the back (its colour the `pack` palette's), `pack_kind`
##   (`medic`: a cross on it). trim         the livery's mark colour (stripes, stencil, crosses);
##                `edge` its edge sheen (alpha 0 = none); `visor` a helmet's visor; `led` a status
##                lamp; `pad` the knee pads.
##   chrome       a chrome limb's colour; `chrome_arms` [chance of one, chance of both] arms in
##                chrome; `chrome_leg` the chance of a chrome shin.
##   optics       [[weight, eyes, face], ...]: the eyes (`glow`, `multi` lenses, "") and face
##                (`respirator`, `plate`, `goggles`, "") drawn together; `glows` the eyes' colours.
##   tattoo, inlays, headset, spine, cables, patchwork   chances of inked skin, black plates set in
##                the skin, a headset, a spine rig, cables over the shoulder, a sleeve patched in
##                another colour; `inks` the tattoo colours.
static var styles: Dictionary = {
	&"zenitex": {
		"side": &"invader", "police": true, "weapons": [&"police"],
		"palettes": {
			"pack": [Color(0.19, 0.20, 0.23)], "bare_top": [Color(0.18, 0.19, 0.22)],
			"bare_pants": [Color(0.16, 0.17, 0.20)], "bare_shoes": [Color(0.10, 0.10, 0.12)],
		},
		"bare": { "body": "bare_top", "pants": "bare_pants", "feet": "bare_shoes" },
		"skin": [Color(0.80, 0.62, 0.48)], "hair": [Color(0.08, 0.07, 0.07)],
		"hair_styles": { "buzz": 1 }, "glove": Color(0.14, 0.15, 0.17), "gloves": 1.0, "pack": 1.0,
		"pack_kind": "", "trim": Color(0.96, 0.97, 1.0), "edge": Color(0.56, 0.60, 0.66),
		"visor": Color(0.20, 0.25, 0.32), "led": Color(1.0, 0.22, 0.2),
		"pad": Color(0.25, 0.26, 0.30), "chrome": Color(0.70, 0.74, 0.78),
		"chrome_arms": [0.0, 0.0], "chrome_leg": 0.0, "optics": [[1, "", ""]],
		"glows": [Color(1.0, 0.16, 0.10)], "inks": [Color(0.08, 0.08, 0.09)], "tattoo": 0.0,
		"inlays": 0.0, "headset": 0.0, "spine": 0.0, "cables": 0.0, "patchwork": 0.0,
	},
	&"trauma": {
		"side": &"invader", "police": true, "weapons": [&"police"],
		"palettes": {
			"pack": [Color(0.88, 0.88, 0.85)], "bare_top": [Color(0.18, 0.40, 0.32)],
			"bare_pants": [Color(0.16, 0.36, 0.29)], "bare_shoes": [Color(0.20, 0.30, 0.26)],
		},
		"bare": { "body": "bare_top", "pants": "bare_pants", "feet": "bare_shoes" },
		"skin": [Color(0.74, 0.55, 0.40)], "hair": [Color(0.18, 0.12, 0.08)],
		"hair_styles": { "buzz": 1 }, "glove": Color(0.76, 0.14, 0.12), "gloves": 1.0, "pack": 1.0,
		"pack_kind": "medic", "trim": Color(0.80, 0.13, 0.11), "edge": Color(0, 0, 0, 0),
		"visor": Color(0.07, 0.09, 0.11), "led": Color(0.45, 0.92, 1.0),
		"pad": Color(0.30, 0.32, 0.33), "chrome": Color(0.70, 0.74, 0.78),
		"chrome_arms": [0.0, 0.0], "chrome_leg": 0.0, "optics": [[1, "", ""]],
		"glows": [Color(1.0, 0.16, 0.10)], "inks": [Color(0.08, 0.08, 0.09)], "tattoo": 0.0,
		"inlays": 0.0, "headset": 0.0, "spine": 0.0, "cables": 0.0, "patchwork": 0.0,
	},
	&"merc": {
		"side": &"household", "police": false, "weapons": [&"scrap", &"pipe"],
		"palettes": {
			"top": [
				Color(0.35, 0.37, 0.24), Color(0.58, 0.51, 0.37), Color(0.42, 0.43, 0.42),
				Color(0.38, 0.28, 0.18), Color(0.24, 0.24, 0.22),
			],
			"jacket": [
				Color(0.33, 0.35, 0.23),
				Color(0.52, 0.46, 0.33),
				Color(0.30, 0.31, 0.31),
				Color(0.40, 0.30, 0.20),
			],
			"jeans": [Color(0.32, 0.36, 0.42), Color(0.40, 0.40, 0.38)],
			"cargo": [Color(0.34, 0.36, 0.24), Color(0.50, 0.45, 0.33), Color(0.30, 0.30, 0.28)],
			"rig": [Color(0.36, 0.38, 0.22), Color(0.30, 0.32, 0.20)],
			"cover_front": [
				Color(0.36, 0.38, 0.22),
				Color(0.30, 0.32, 0.20),
				Color(0.35, 0.37, 0.24),
				Color(0.58, 0.51, 0.37),
			],
			"cover_back": [
				Color(0.42, 0.43, 0.42),
				Color(0.38, 0.28, 0.18),
				Color(0.24, 0.24, 0.22),
				Color(0.36, 0.38, 0.22),
			],
			"shoes": [Color(0.30, 0.24, 0.18), Color(0.40, 0.38, 0.34)],
			"boots": [Color(0.48, 0.40, 0.28), Color(0.25, 0.22, 0.18)],
			"helm": [Color(0.33, 0.36, 0.22), Color(0.55, 0.49, 0.35)],
			"cap": [
				Color(0.35, 0.37, 0.24),
				Color(0.58, 0.51, 0.37),
				Color(0.24, 0.24, 0.22),
				Color(0.20, 0.90, 0.95),
			],
			"patch": [
				Color(0.35, 0.37, 0.24),
				Color(0.58, 0.51, 0.37),
				Color(0.42, 0.43, 0.42),
				Color(0.38, 0.28, 0.18),
			],
			"pack": [Color(0.33, 0.35, 0.23), Color(0.52, 0.46, 0.33), Color(0.40, 0.30, 0.20)],
		},
		"bare": CREW_BARE,
		"skin": CREW_SKIN,
		"hair": [
			Color(0.08, 0.07, 0.07),
			Color(0.33, 0.22, 0.13),
			Color(0.55, 0.42, 0.25),
			Color(0.20, 0.16, 0.13),
		],
		"hair_styles": { "buzz": 3, "short": 2, "bald": 1, "long": 1 },
		"glove": Color(0.15, 0.15, 0.14), "gloves": 0.5, "pack": 0.55, "pack_kind": "",
		"trim": Color(0.75, 0.75, 0.72), "edge": Color(0, 0, 0, 0),
		"visor": Color(0.08, 0.08, 0.09), "led": Color(1.0, 0.2, 0.2), "pad": Color(0.2, 0.2, 0.2),
		"chrome": Color(0.60, 0.63, 0.66), "chrome_arms": [0.25, 0.0], "chrome_leg": 0.0,
		"optics": [[45, "multi", ""], [40, "", "goggles"], [8, "", "respirator"], [7, "", ""]],
		"glows": [Color(1.0, 0.16, 0.10)],
		"inks": [Color(0.13, 0.25, 0.22), Color(0.10, 0.12, 0.25), Color(0.08, 0.08, 0.09)],
		"tattoo": 0.3, "inlays": 0.0, "headset": 0.6, "spine": 0.15, "cables": 0.0,
		"patchwork": 0.8,
	},
	&"borg": {
		"side": &"household", "police": false, "weapons": [&"scrap", &"pipe"],
		"palettes": {
			"top": [
				Color(0.18, 0.18, 0.19),
				Color(0.42, 0.22, 0.13),
				Color(0.32, 0.09, 0.09),
				Color(0.27, 0.29, 0.20),
			],
			"jacket": [Color(0.20, 0.20, 0.21), Color(0.36, 0.20, 0.12), Color(0.28, 0.10, 0.10)],
			"jeans": [Color(0.17, 0.20, 0.28), Color(0.22, 0.22, 0.24)],
			"cargo": [Color(0.14, 0.14, 0.15), Color(0.26, 0.27, 0.20)],
			"rig": [Color(0.46, 0.40, 0.36), Color(0.52, 0.32, 0.20)],
			"cover_front": [
				Color(0.46, 0.40, 0.36),
				Color(0.52, 0.32, 0.20),
				Color(0.18, 0.18, 0.19),
				Color(0.42, 0.22, 0.13),
			],
			"cover_back": [
				Color(0.32, 0.09, 0.09),
				Color(0.27, 0.29, 0.20),
				Color(0.46, 0.40, 0.36),
				Color(0.52, 0.32, 0.20),
			],
			"shoes": [Color(0.20, 0.17, 0.14), Color(0.12, 0.12, 0.12)],
			"boots": [Color(0.14, 0.13, 0.12), Color(0.24, 0.20, 0.16)],
			"helm": [Color(0.55, 0.57, 0.60), Color(0.42, 0.36, 0.30)],
			"cap": [
				Color(0.18, 0.18, 0.19),
				Color(0.42, 0.22, 0.13),
				Color(1.0, 0.25, 0.65),
				Color(0.62, 0.32, 0.95),
			],
			"patch": [Color(0.18, 0.18, 0.19), Color(0.42, 0.22, 0.13), Color(0.27, 0.29, 0.20)],
			"pack": [Color(0.20, 0.20, 0.21), Color(0.36, 0.20, 0.12), Color(0.28, 0.10, 0.10)],
		},
		"bare": CREW_BARE,
		"skin": CREW_SKIN,
		"hair": [
			Color(0.08, 0.07, 0.07), Color(0.33, 0.22, 0.13), Color(1.0, 0.25, 0.65),
			Color(0.20, 0.90, 0.95), Color(0.85, 0.15, 0.12), Color(0.62, 0.32, 0.95),
		],
		"hair_styles": { "bald": 4, "buzz": 2, "mohawk": 1 }, "glove": Color(0.15, 0.15, 0.14),
		"gloves": 0.0, "pack": 0.25, "pack_kind": "", "trim": Color(0.75, 0.75, 0.72),
		"edge": Color(0, 0, 0, 0), "visor": Color(0.08, 0.08, 0.09), "led": Color(1.0, 0.2, 0.2),
		"pad": Color(0.2, 0.2, 0.2), "chrome": Color(0.70, 0.74, 0.78), "chrome_arms": [0.45, 0.45],
		"chrome_leg": 0.35,
		"optics": [[54, "glow", "plate"], [36, "glow", ""], [6, "", "plate"], [4, "", ""]],
		"glows": [
			Color(1.0, 0.16, 0.10), Color(0.22, 0.95, 1.0), Color(0.45, 1.0, 0.32),
			Color(1.0, 0.70, 0.15), Color(1.0, 0.22, 0.85),
		],
		"inks": [
			Color(0.13, 0.25, 0.22),
			Color(0.10, 0.12, 0.25),
			Color(0.08, 0.08, 0.09),
			Color(0.35, 0.10, 0.12),
		],
		"tattoo": 0.25, "inlays": 0.5, "headset": 0.0, "spine": 0.6, "cables": 0.8,
		"patchwork": 0.0,
	},
}
