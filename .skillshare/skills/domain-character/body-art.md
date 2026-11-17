# Body: pixel art and the resolved look

Specs: `docs/outfits.md` O12 (every garment shown standing, crouched, fallen) and O15 (styles). Tests: `tests/character/outfit_art_test.gd`, `style_look_test.gd`. The Art domain's engine is `domain-art`.

## Painters (`body/art/`)

Six private painters, each its own part, all drawing from the character's resolved look, which they get as an int handle (`opts.look`, `PixelArt.handle`, read back with `PixelArt.look_of`): the look is some fifty entries and `PixelArt` hashes the options on every call, so the handle keeps the options a few scalars. `style_art.gd` holds the styles' shared marks (chrome, tattoo ink, skin inlays, the edge sheen, stripes, crosses, a stencil, tape).

- `body_painter.gd`: the shoulders in the shirt, the neck ring, the ends where the arms leave (sleeve, skin, chrome), the style's uniform or gear marks, the vest, spine rig, cables and the pack.
- `head_painter.gd`: skin, ears and nose toward the front, hair, cap or helmet, then the face, on its own canvas (`radius_for(width)`, `canvas_for(r)`).
- `hand_painter.gd`: a fist, knuckles to the front and the thumb on the inner side (`side`); `limb_painter.gd`: the shaded strip of one arm, leg or shoe segment (`part`, `side`, `cuff`, `skin`, `chrome`).
- `vest_painter.gd`: called by the body painter (`paint_top`, seen from above) and the torso painter (`paint_face`, no caller now the 2D trunk is gone): a soft vest or a plate carrier. A plate's wear is `WEAR_STEPS` steps of `_MARKS_PER_STEP` marks from one fixed sequence per side (a crack, then a scuff), so each step adds to the last. `torso_painter.gd` paints the trunk's chest, back and flank faces (left for the sweep: nothing calls it).

The 3D body wears each painter's flat render (`PixelArt.render_flat`, `body-textures.md`); the painters keep their lit branches while lit art feeds other textures.

## The look

The character's style (`wardrobe`: `style`, `look_seed`, `rank`) and what it wears decide everything: The body's `dress` (`body_dress.gd`, `BodyDress`, made and refreshed by `BodyMesh`; `look_worn()` reads it) resolves it:

- `refresh(wardrobe)` asks `wardrobe.outfit.look(style)` (each garment's `kind` and a `color` or a palette name) and `character_style.gd`'s `resolve(style, seed, rank, worn)` for the whole look: the style's row (`CharacterStyleConfig.styles`: livery marks, palettes, `bare` = what is drawn where nothing is worn) and the character's own variety drawn from its look seed **in a fixed order**, so a seed's look is stable. A garment's colour is its own, or drawn from the style palette it names by the seed and the palette's name, so a colour stays put as the clothes change.
- It registers the look with `PixelArt.handle` and builds, once per change, the painters' options: the plates' colours and wear step `ceil((1 − condition) × WEAR_STEPS)`, each arm segment's colour, finish and options (`_arm_part`), each leg part's options and chrome shin, each fist's colour and options. A boot is the shin's lower part from `BodyTextures.BOOT_TOP` down, `BOOT_GROW` wider.
- **`refresh` resolves only when `Outfit.revision` or `wardrobe.revision` moves** (two int compares a frame). When the resolved look's hash `look_key` changes it returns true: `BodyMesh` dresses its parts again.
