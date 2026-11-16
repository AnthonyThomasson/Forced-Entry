# Lighting

Every match and test world is lit at **dusk** with real lights and shadows: no light is baked into any art. The game is drawn in 3D
(the lights of it are the first section, "The 3D lighting"); the 2D render's lights, the second, go with the 2D render. Behaviours L1 to
L10 are the spec; each has its tests named under it, following the convention of `docs/grenades.md`. The tests are in
`tests/lighting/` (`tools/run_tests.sh --domain=lighting`, 10 tests), through `tests/_lighting/lighting_probe.gd`, which keeps the
plan's numbers as its own consts (the ambient, 15 lights an item, 12 a floor) and reads the game only through the published names
below, so a test checks this file and not the code. The code is the Lighting domain (`scenes/lighting/`, skill `domain-lighting`);
the masks are General's `LightMasks` (`architecture` interface 11), the lights and shadows of the world's things are their own
domains' (interface 20).

All distances are px and times seconds. The numbers are the Lighting holders' (`LightingConfig`, `LightingFixtureConfig`, `LightingTextureConfig`, in `scenes/lighting/`) and, for what
each piece gives, `ObjectArtLightConfig.specs`.

## The 3D lighting

The game is drawn in 3D (`architecture` interface 27, #193): a near top-down orthographic camera over meshes that wear the
2D painters' flat art, shaded by Art's toon light (`toon_common.gdshaderinc`). The Lighting domain's 3D side is
`WorldLighting3D` (`scenes/lighting/world_lighting_3d.gd`), which Main builds under the 3D view's own world after it mirrors the
match (`Main._view3d.light_world`): it reads the 2D world the sim runs in, duck-typed as `WorldLighting` does (Objects' floors
(`is_street()`, `size`), a piece's `get_lights()`, the rooms), and builds the lights of the 3D world. It reads no 2D canvas state
(no `light_mask`, no light layer), so the 2D render and its masks can go without it. Its numbers are `Lighting3DConfig` (the sun, the
heights, the pools) and `LightingCostConfig` (the cost caps), over the dusk's colours and energies in `LightingConfig`. The
2D lights, the occluders and the 2D behaviours L1 to L10 below it stay until the 2D render is removed; the 3D ones are these.

**How a pixel is lit.** There is no baked light in any art. Each pixel is its painted colour times the **dusk ambient**
(`LightingConfig.ambient_color`, a toon global, `ToonLight`) plus every light that reaches it: each light's amount (the angle
of the face to it, times its fall-off, times its shadow) is stepped into bands and tinted by the light's colour and energy: the
sun's into `PixelPostConfig.bands` (3: none, a little, the light whole; `ToonLightConfig.levels`), a lamp's pool into
`ToonLightConfig.pool_levels` (eight, from a trace, 0.08, to the light whole, times `pool_strength` 1.4: 2D adds its light in sRGB,
where it reads stronger than the same light in the 3D render's linear one), so a pool is a few soft rings that end in a faint tail,
not on a hard rim, and a shadow one hard edge. The sum is held to `ToonLightConfig.cap` (1.7) of the painted colour by its brightest channel, so a pixel under three
lamps is the art lit warm and not blown out, and the hue stays. A world that sets no ambient is lit by
`ToonLightConfig.default_ambient` (a grey), not black.

**L1-3D. Dusk.** The ambient is the 2D dusk's, **(0.40, 0.37, 0.55)**. One `DirectionalLight3D`, the sky, in `sky_color`
**(1.0, 0.5, 0.42)** at `sky_energy` 0.42, travels toward +x and -y of the 2D world (from the south-west, `sky_from`) at
`sun_elevation` **68** degrees, with hard shadows, so a wall of 96 throws a shadow of 39 px and a person of 74 one of 30: short
like the 2D drop shadow, not the streak of a low sun. It reaches only the street's floors: a texture of the world (`ToonLight`'s
sky mask) is white on every street floor and black under every house and tower floor and the walls round them
(`floor_reach`), so a tower is lit from within as in 2D (a house or the arena, with no street floor, gets no sky), and the
tower's shadow on the street is the wall's, short and hard. A street floor is one that says `is_street()` (Objects' `Floor`). With `lighting.enabled` off no light is built: the ambient is
white and the one sun too dim to show, so the art is as painted.
Tests: `lighting/light_3d_dusk_and_sky` (the ambient, the sun's colour, energy, direction, elevation and shadows, a wall's shadow
short, the sky on every point of street ground out of a tower and in none), `lighting/light_3d_look_windowed` (windowed: the
street warm and bright, the house the art times the ambient, the wall's shadow dark behind it and gone past its reach),
`general/render_light_top_in_base_band` (the sun puts a flat top in the top band; the camera is near top-down),
`lighting/light_3d_switch_off`.

**L2-3D. A light per light-giving piece.** Every light a piece declares (`get_lights()`: `offset`, `colour`, `energy`,
`radius`, `rhythm`, `room_light`, `street`, `height`) becomes an `OmniLight3D` at the piece's place, in its colour at its
energy, hung at the height of its kind (`overhead_height` 60: a lamp's bulb, a fixture; `street_height` 70: a street lamp's head
or sign; `low_height` 22: a screen, a tube, LEDs, trim) and reaching the pool's `radius` times `range_scale` 1.3 on the floor
(its range is the distance to that rim: the pool reaches a little past the 2D one, so the 3D rings bring the light of the 2D
smooth tail). An **overhead or street** light pools flat to half its radius and quickly at the rim (`overhead_slope` 2, the 2D
pool's profile); a **low** one is a glow fading from its middle (`low_slope` 1): the toon light's two shapes of one linear
fall-off. The nodes are `OmniLight3D`s under the `WorldLighting3D` named `Light<n>_<piece>`, with the metas `piece`, `index` (into
`get_lights()`) and `room`, kept in step with the piece: a shoved lamp carries its light (`process_priority` 20, after the
bodies), and a freed piece's light is freed with it.

**A pool never crosses a wall, and costs no shadow.** Every light knows the room it stands in (the room map,
`ToonLight.set_rooms`: a texture of the rooms' rects, an id each; the light's id and whether it is a street light ride in its
`light_specular`, with the slope: the toon has no specular), and the toon light, which knows the room of each spot, lets a light
reach only the spots of its own room, plus the walls and pieces above the floor that are in no room (so a wall is lit from both
sides). A street light reaches the spots in no room (the street, a tower's outside) and never a room's inside, as in 2D (where
the light layers did it). With no rooms (an arena) nothing is clipped.
Tests: `lighting/light_3d_per_piece` (seed 1: each declared light placed, over its piece's light, at its kind's height, in its
colour and its radius, in its room, at most its energy; every fixture overhead at its room's centre),
`lighting/light_3d_follows_and_flickers` (a shoved lamp's light follows it; a freed piece's light is freed),
`lighting/light_3d_look_windowed` (a lamp's pool warm, bright at its middle, stepped, gone past its radius, and gone at the line
of its room: the next room, a few px over it, is the ambient's).

**L3-3D. Room fixtures.** A room no `room_light` stands in gets an overhead light at its centre, as in 2D (the same colour,
energy and reach, `LightingFixtureConfig`) and the glyph's 3D twin, a **bulb**: a small emissive sphere (`bulb_radius` 3, the light's
colour lightened) hung `bulb_height` (104) up, over the walls' tops as the 2D glyph is drawn over everything, casting no shadow, dimming
with its light's rhythm. The fixture is the one light that may cast a shadow, and the shadow is part dark
(`Lighting3DConfig.fixture_shadow_opacity` 0.6, `OmniLight3D.shadow_opacity`), so the floor under a table or a chair is the pool's colour
a step down and not the cold ambient alone (the 2D render has no such blob). Tests: `lighting/light_3d_per_piece`,
`lighting/light_3d_fixture_look` (a bulb per fixture over the walls, glowing, uncast; the shadow part dark).

**A doorway is lit.** Rooms meet at the walls' centre lines, so the room map gives every spot of an opening between two rooms to
one of them (half across the wall to each side): a light of either lights its half and the two halves meet, so there is no dark
strip in a doorway. An exterior door's inside is its room's; the half beyond it is no room, the street's. Light does not spill out
of a door onto the street as the 2D wedge does. Test: `lighting/light_3d_doorway_in_rooms` (the room map along every opening).

**L4-3D. The cost.** There is no per-floor budget in 3D: that limit (12 lights a floor) was Godot 2D's 15 point lights to a
canvas item, and the 3D renderer clusters its lights; what costs is how many are on and how many cast. So every declared light
is placed and the cost is capped, chosen from where the view looks (the `focus` the view gives, the 2D camera's centre, and the
camera's reach, which follows the zoom): at most `LightingCostConfig.max_lights` (48) lights are on, the ones whose pools come
nearest the view (ranked by the distance to the focus less the pool's radius), each fading in or out over `fade_time` 0.2 s and
not switching at once; and at most `shadow_lights` (6) cast a shadow, the nearest **ceiling fixtures**. A lamp, a tube, a screen
and a street lamp cast none: a piece's own body would shadow a light standing in it, and the room cull above is what keeps a
pool in its room. A caster keeps its shadow while it is within `1 / keep_margin` (1.33) times the cutoff (the last caster's
distance), a nearer rival taking it only past that; the other slots go to the nearest. The choice is made again every `refresh`
0.3 s, when the focus moved `refocus` 48 px or the zoom changed. A light off costs nothing (no rhythm, no write); with no focus
every light is on and none casts. Counted in the district (the street and bedroom shots), the lights that reach the view: 95 and
98 at zoom 0.5, 30 and 35 at zoom 1, 6 and 19 at zoom 2 (of 122 and 143 built), so 48 keeps every one at zoom 1 and the
nearest at 0.5. Tests: `lighting/light_3d_cost` (the caps; the fade; only fixtures cast; hysteresis; a cap of none),
`lighting/light_3d_dusk_and_sky` (the globals belong to the last lighting standing).

**L7-3D. Light sources glow.** What gives light is a glowing part of the piece's mesh (Objects' `FurnitureRig.add_glow`, the
toon's `emissive`, a colour whatever the light), so a lamp's bulb, a screen, a neon tube is its colour in the dusk, apart from its
light; the Lighting domain dims it with its light's rhythm (`glow_changed`, Main wires it to `FurnitureRig.set_glow_level`).

**L8-3D. Rhythms, seeded per light.** As in 2D (`light_rhythm.gd`): the energy of a light changes in the rhythm its declaration
allows, seeded from the world's seed and the piece, so the same world flickers the same. Test:
`lighting/light_3d_follows_and_flickers` (one room lit twice from one seed: every light's energy equal to its twin's in every frame).

**L9-3D. Flashes.** A `shot` lights a muzzle flash and an `explosion` a blast's (a frag's orange, a stun's white), driven by the same
looks as 2D (`LightingConfig.flashes`: colour, energy, `reach` the pool's diameter, `reach_per_radius`, `hold`, `life`): a pooled
`OmniLight3D` at hand height (`Lighting3DConfig.flash_height` 30) lit at the event's point, its pool `reach / 2` times `range_scale`
out on the floor, flat to its middle (the overhead slope), held at full energy for its `hold` then falling off to dark over its `life`
as `energy x left^2` (a shot's 0.07, a frag's 0.5, the stun's 0.08 held + 0.7). The pool is the light budget of a firefight:
`Lighting3DConfig.flash_lights` (4), a new flash taking a dark light and else the **oldest** (so a dozen shots in a frame light the last four),
a flash whose pool the view cannot reach (the focus and the camera's reach) lights nothing and takes no slot. A flash casts **no shadow**
and takes no shadow slot (the room map is its wall: it lights the room it stands in, or a room it is within `flash_room_slack` 8 px
outside of (a muzzle in a doorway), and else, on the street, the spots in no room, as a street light does). Nothing is lit outside the
vision cone: a flash is dimmed where the player does not see (the vision mask's `vision_unseen`, `docs/player-vision.md`: the toon light
scales every light's amount by it, so a flash outside the cone, in a remembered or a never-seen spot, shows as little as a lamp there does). There is no light for a bullet's impact spark (2D lights none).
**Wash:** the toon light caps what a surface adds up to at 1.7 of its painted colour, which would hold a blast to a warm tint, so a row's
`wash` lifts the cap (`ToonLight.set_cap`) while its flash is lit, by `wash x (the flash's energy now / its energy)`: a shot 1, a frag 3
(the floor reads orange as in 2D), the stun 12: with energy 8 the floor round a stun is white, the full flash 2D shows (the burst's
own dithered disc, Physics, is the smoke). A lamp's pool, near the cap already, hardly shows the lift. Tests:
`lighting/light_3d_flashes_on_shot_and_explosion` (a flash within 3 frames at the muzzle and the burst, in its colour, uncast, at hand
height, dark within 0.25 s and 1.5 s), `lighting/light_3d_stun_flash` (white, a peak of 4.8 or more, held, still lit at 0.45 s, dark
within 1.1 s, the cap lifted while lit and restored), `lighting/light_3d_flash_pool` (the cap of the pool, the oldest dropped, a
flash out of the view takes none), `lighting/light_3d_flash_room` (a flash of its room, a doorway's, the street's),
`lighting/light_3d_flash_look_windowed` (windowed: the floor warm round a muzzle and the ambient's past its reach and after it, the
stun washing it white and the cap restored).

*(L5, L6, L10 in 3D: a light is placed at its piece and follows it, L5; who shadows whom is the real geometry, L6: the sky's
shadows by every mesh, a ceiling fixture's by theirs, a wall's included, and a pool is kept in its room by the room cull, not by a shadow;
the switch is above, and with it off no flash is built.)*

## The 2D render

Everything below describes the 2D render, which is removed with it (#193).

## What is built

`WorldLighting.light(root, seed_value, rooms)` (the match builder's world stage, `MatchBuilder.stage`, after the nav bake, for Main's match and the Testing world alike) adds one `WorldLighting`
node under the world root, in the group `world_lighting`, with the reads `lights()` (every piece and fixture PointLight2D),
`fixtures()` (`{ room, light }`), `flashes()` (the pooled flash lights) and `budget()` (`{ per_floor, dropped }`, `dropped` holding
`{ piece, index }` per declared light left without a PointLight2D). The world's own things carry the rest:

- a light-giving piece declares its lights with `get_lights()` (Objects, plain dicts in the piece's frame: `offset`, `turn`,
  `colour`, `energy`, `radius`, `shape`, `rhythm`, `room_light`, `street`, `height`, `glow`);
- every wall run, every solid piece and every living character builds its own `LightOccluder2D`, like its collider, on the bit
  `LightMasks` gives its kind;
- the street's floors, and the long shadow each tower throws across them, are on the street light layer (`LightMasks.STREET`);
  everything else on the house's (`HOUSE`, Godot's default).

In a **district** `rooms` is `WorldGen.district_rooms`: the rooms of all nine towers, a neighbour's keyed `<block>:<key>` so no two
clash, each lit as a house's rooms are (a fixture or a piece's own light). The shells are no rooms and have no fixtures. The street
floors are cut to `tile_max` (360 px) on a side so the lamps of a block still reach each within the budget (L4). Nothing is drawn
overhead: a tower's rooms are open to the camera and lit by the ambient, their fixtures and pieces, with no roof above them.

## Behaviours

**L1. Dusk.** One CanvasModulate tints the world `ambient_color` **(0.40, 0.37, 0.55)**, a cool blue-violet. One
DirectionalLight2D, `Sky`, in `sky_color` **(1.0, 0.5, 0.42)** comes low from the south-west (`sky_from` (−0.38, 1.0), so it shines
toward +x, −y; the front of a lone house is south; a district's towers face any street) at energy 0.42 and lights only the street's layer, **unshadowed** (a directional
shadow runs to the edge of the view, so a body out there would throw one across the whole street). **The house and every tower are lit from within:** no sky
reaches their rooms, which are lit by the ambient, their fixtures and their pieces (a sky let in by the doorways would throw a band
of light the length of the room, a 2D light having no height).
Tests: `lighting/dusk_ambient_and_sky` (seed 4: the configured ambient; one CanvasModulate in it; every sky light in the sky
colour, from the south-west; the one reaching the street's floors unshadowed; none reaching the rooms' floors).

**L2. A light per light-giving piece.** Every piece that gives light declares it (`get_lights()`): a lamp's bulb (a room light), a
screen (a TV, a desk's monitor, the den's monitor wall: a wide spill across its front, shimmering), a neon tube (a tube-shaped pool
along it, in its tone), a server rack's LEDs, the rig's halo, a cart's display, the scanner's beam, the hot ring, the surgeon's
lamp (a room light), a street lamp's lens or sign (it lights the street too) and a piece's neon trim. Its colour is what the
painter draws glowing. Each light has a **height**: `overhead` (a lamp's bulb, the surgeon's lamp, a street lamp's head or sign:
above the heads) or `low` (every other: screens, tubes, LEDs, the hot ring, trim). The Lighting domain gives each declared light a
shadowed PointLight2D (hard shadows, a texture `round`, `wide` 2:1 or `tube` 3:1) **as a child of the piece**, unless the budget
drops it (L4). Every pool **fades smoothly**, without rings. A low light glows from its middle, fading to its rim (`glow_offsets`);
an **overhead light pools downward**: its cone meets the floor, so its pool is nearly flat out to half its radius (`pool_offsets`)
and fades quickly at the rim. A street lamp's and a sign's pool is tight under its head (**130** px in radius, centred on the
head); a standing lamp's is 160.
Tests: `lighting/house_lights_per_piece` (seed 1: every lamp, screen, neon tube and streetlight declares its light; for every piece
declared = placed under it + dropped; every light has a texture and casts shadows; every light is a piece's or a fixture's),
`lighting/overhead_lights_pool_downward` (a lamp, a street lamp and a sign declare `overhead`, a TV `low`; every overhead pool, a
fixture's too, still ≥ 0.9 of its centre at half its radius, the TV's under 0.7; every pool, the TV's too, with no jump over 0.08
of its centre between 64 samples from its centre to its rim; a street lamp's and a sign's pool ≤ 140 px in radius and within 4 px
of the middle of its `Overhang`).

**L3. Room fixtures.** A room that no kept `room_light` stands in gets a ceiling fixture at its centre: a bare bulb glyph drawn
unshaded over everything (`DrawLayers.OVERHEAD`) and its light (`LightingFixtureConfig.color` (1.0, 0.62, 0.22), energy 0.8, a pool the room's
longer side × 1.1 + 60 across, clamped 300..900): an overhead light, **shadowed by the walls only** and pooling downward (L2, L6).
Tests: `lighting/house_lights_per_piece` (each fixture a PointLight2D inside its room; every room lit by a kept room light or a
fixture), `lighting/overhead_lights_pool_downward` (a fixture's pool is flat).

**L4. At most 12 lights a floor.** Godot 4.4 lights a canvas item with at most **15** point lights (the renderer stops gathering at
`MAX_LIGHTS_PER_ITEM − 1`; directional lights are apart) and drops the rest; **3** are kept for the flashes, so no floor (a room's,
the arena's or a piece of the street, counted with its walls and wear out to `floor_reach` 8 px past its rect) is reached by more
than **12** piece and fixture lights. A light reaches a floor when its pool's box (its texture × `texture_scale`, turned) meets the
floor and its item mask meets the floor's light layers: the house's lights never reach the street, only the street lamps (and the
flashes) do. The fixtures of rooms no piece lights are counted first; then the declared lights, **strongest first** (declared
`energy`), so a room over budget **drops its weakest**; a room whose room lights were all dropped then gets its fixture where its
floors have room. Each room's walls and wear are their own items over its floor's rect, so they take its floor's count. The
batched decal layers (blood, scorch, debris) are drawn in 128 px chunks, smaller than any room: a chunk is reached by the lights of
the floor it lies on, one straddling a wall by those of both rooms (not budgeted on its own). A debris chunk draws in pages
(`DebrisLayer.PAGE` chips, each its own item) and a body's parts are kept meshes placed by their own bounds, so each is reached by
the lights of what it covers: only where more than 15 reach (a chunk or a body straddling two rooms while flashes go off) can a page
or a mesh keep a light the one draw dropped, and light what that draw left unlit (#78).
Tests: `lighting/house_lights_per_piece` (`per_floor` ≤ 12; every floor, rooms and street, reached by ≤ 12, ≤ 15 with the flashes),
`lighting/floor_budget_drops_weakest` (ten lamps and six neon tubes in one room: the floor reached by exactly 12; declared = placed
+ dropped; something dropped; no dropped light brighter than a kept one).

**L5. Lights move with their piece.** A light is a child of its piece, so a shoved lamp carries its light at the same place in its
own frame, while it slides and at rest, and it stays one of the lighting's lights.
Tests: `lighting/shoved_lamp_light_follows` (a lamp shoved with `apply_impulse((900, 120))`: each light within 0.5 px of its place
in the lamp's frame every 2 frames and at rest; the lamp moved ≥ 40 px).

**L6. Shadows by height: walls, tall pieces and the living; never the dead.** Each wall run casts a shadow (an occluder over its
collider's rect, `LightMasks.WALL`); each solid piece over its footprint, a child so it follows a shove (`EMITTER` for a piece that
gives light: its own light sits inside it; `TALL` for one as tall as **75** `coverage` or more, taller than a standing person's 60:
a wardrobe, a fridge, shelving, lockers, a shower; `FURNITURE` for the rest); walk-over decor (a rug, a tube, litter) none; each
living character an oval over its body, `0.72 r` deep along its facing by `1.05 r` across the shoulders, turned with its facing
(`CHARACTER`), freed when it dies. Each occluder is wound so the shape itself stays lit and only what lies behind it falls dark. A
2D occluder has no height, and its shadow runs to the rim of the light's pool as if the light stood on the floor, so who shadows
whom is chosen by the light's height: an **overhead** light (a fixture, a lamp, the surgeon's lamp, a street lamp or sign) by the
**walls only** (they hang over the furniture and the characters); a **low** light (a screen, a tube, LEDs, the hot ring, trim) by
the walls and the **tall** pieces; a flash (at hand height, and brief) by everything. The pieces and the characters keep their
drawn drop shadows. A flash whose centre a living character stands within **1.3** of its radius leaves the characters out of its
shadows that frame (a body would black out the light it stands in: a blast at its feet).
Tests: `lighting/occluders_walls_pieces_characters` (every wall run covered at ¼, ½, ¾; the armchair, the wardrobe, the lamp and
the TV each carry their own occluder, the rug none; a living puppet stands in an occluder, before and after a walk, and so does a
second one; once it dies none under it nor over where it lies; the lamp's light shadowed by the wall's occluder mask and not the
wardrobe's, the armchair's or the walker's; the TV's by the wall's and the wardrobe's and not the armchair's or the walker's),
`lighting/flashes_on_shot_and_explosion` (every flash by a wall, the wardrobe, a chair and the gunner).

**L7. Light sources draw unshaded.** What gives light is drawn by each visuals node's `Emissive` overlay (Objects' `emissive_layer()`),
which draws through an unshaded CanvasItemMaterial: neither the dusk nor any light changes a light source, while the art under it is
lit like everything else. Nothing glows around a source but its real light.
Tests: `lighting/emissive_overlays_unshaded` (seed 4: every overlay unshaded, the visuals under it not).

**L8. Rhythms, seeded per light.** A light flickers in one of the rhythms its piece allows (`steady`, `buzz`, `failing`, `blink`,
`shimmer`, `pulse`: screens shimmer, signs blink, tubes and bulbs now and then fail or buzz), picked and seeded from the world's seed
and the piece (its place and the light's index), so the same world lit with the same seed flickers the same, and two pieces never in
step. The light's energy and its piece's light-source overlay dim together.
Tests: `lighting/rhythms_seeded_per_piece` (one room built twice in worlds of their own and lit with the same seed: every light's
energy equal to its twin's in every frame over 240 frames; within one copy no two changing lights alike).

**L9. Flashes.** A pool of **3** lights (shadowed by everything, L6, lighting the house and the street): a `shot` lights one at
the muzzle, warm (1.0, 0.82, 0.55), 340 across, falling off to dark over **0.07**; an `explosion` one at the burst, a frag orange
(1.0, 0.62, 0.3) over **0.5**, at least 600 across (4 × the event's `radius`). The next flash takes the pool's next light in turn.
*(Amended by issue #56.)* A stun's flash is its burst's whole look (Physics draws no disc for it, only its thin smoke,
`docs/grenades.md` G14): white (0.92, 0.95, 1.0) at energy **8** (a frag's is 2.6, a shot's 1.6), at least 700 across (3.5 × the
event's `radius`), held at that energy for **0.08** s (`hold`), then falling off to dark over **0.7** (its `life`), shadowed and
cleared of the characters as every flash. A row's `hold` (s, none when absent) and `life` are in `LightingConfig.flashes`; the shot
and the frag hold none. Tests: `lighting/flashes_on_shot_and_explosion` (within 3 frames of the `shot` a flash lit within 24 px of
the muzzle, all dark within 0.25; the same at the frag's burst, dark within 1.5), `lighting/stun_flash_light` (within 3 frames of the
stun's burst a white flash lit within 24 px of it, shadowed by the walls and the furniture, peaking at 4.8 or more (well over a frag's 2.6), held at 95 % of
its peak for 3 frames or more, still lit 0.45 s on and dark within 1.1).

**L10. The switch.** `lighting.enabled` (default on; `LightingConfig.enabled` and General's `LightMasks.shadows`) off builds none of it:
no WorldLighting, ambient, sky, point light or occluder anywhere, the characters' included.
Tests: `lighting/lighting_switch_off` (after a shot, none of those node types under the world).

**A tower's shadow.** Each tower of a district casts a long, hard shadow onto the street (`DecalFactory.shadow`, interface 2): its
footprint dragged `WorldGenTowerConfig.shadow_length` away from the art light, the footprint itself left clear, lit by the street's
lights only. It is a baked decal at `DrawLayers.RUG`, so characters and pieces stand over it, and it casts no occluder of its own.
Tests: `worldgen/district_tall_read` (a shadow per tower reaching past it, clear on its footprint, on the street layer, under the characters), `general/district_match_staged`
(every room of every tower has a light, no two rooms share a key).

## Measured cost

These figures were measured before shadows by height (L6): every piece light was then shadowed by the furniture and the
characters too, and a shadowed sky lit the house. The lighting now builds fewer shadow casters per light and no sky in the house,
so they are an upper bound until it is measured again. They were taken on one house and street; a district (nine towers, more lights in view at
once) was **not** measured, and no GPU figure for it is recorded. The hand check in the editor stays to do.

The perf tests run headless and see only the CPU side, so the GPU cost is measured by hand. On 2026-10-15 a 10v10 match in
`garage_home` was measured, set up as `perf/match_10v10_stress` sets it up (seed 7, scripted Von). It ran windowed on Vulkan
(`--rendering-driver vulkan`, Apple M2 Max) with `--fixed-fps 60`, so each frame is one physics step, and with vsync off. Each run
was timed over 1200 frames after a 10 s warm-up. GPU ms is the root viewport's measured render time
(`RenderingServer.viewport_get_measured_render_time_gpu`). The baseline is the same match, measured the same way, on the commit
this lighting builds on (2ea038d, which has no lighting), run in turn with this code's unlit runs. The machine was shared: its load
average was 3.8 to 4.6 (12 cores) for every run. A row with two figures is two runs.

| Window | Lighting | Frame ms avg / p95 / max | GPU ms avg / p95 / max |
|---|---|---|---|
| 1152×648 | on | 20.7 / 27.2 / 37.4 and 25.9 / 36.7 / 47.6 | 2.44 / 3.31 / 4.32 and 2.42 / 3.63 / 4.60 |
| 1152×648 | off | 21.3 / 30.4 / 38.8 and 23.7 / 33.4 / 46.2 | 0.94 / 1.30 / 2.33 and 1.20 / 1.95 / 3.19 |
| 1152×648 | off | 22.4 / 32.0 / 39.1 and 27.0 / 36.2 / 48.5 | 1.18 / 1.80 / 2.96 and 1.00 / 1.36 / 2.87 |
| 1152×648 | baseline (2ea038d) | 29.8 / 39.9 / 54.3 and 22.6 / 41.6 / 53.4 | 1.41 / 2.28 / 3.91 and 1.14 / 1.49 / 2.70 |
| 2560×1440 | on | 41.0 / 53.0 / 66.8 | 7.82 / 10.51 / 12.14 |
| 2560×1440 | off | 38.1 / 49.3 / 61.5 | 5.10 / 6.10 / 7.29 |

The lighting costs the GPU about 1.4 ms a frame at 1152×648 and about 2.7 ms (4.4 ms at p95) at 2560×1440. Both are within the
3.7 ms planned for the biggest house. The windowed 10v10 does not hold 60 fps with the lighting on or off, and the baseline does not
either: its frames are as long, so the miss does not come from the lighting or the restyle. The frame is CPU-bound: the same match
takes 11.5 ms a frame headless, and windowed the GPU accounts for 1 to 8 ms of it. So cheapening the lighting (a cheaper shadow
filter, merged wall occluders) would not bring that match to 60 fps.
