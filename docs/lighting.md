# Lighting

Every match and test world is lit at **dusk** with real lights and shadows: no light is baked into any art. The game is drawn in 3D
and these are its lights. Behaviours L1 to L11 are the spec, each with its tests named under it, following the convention of
`docs/grenades.md`. (The "2D" this file compares with is the look of the earlier 2D render, which the 3D one matches.) The tests are
in `tests/lighting/` (`tools/run_tests.sh --domain=lighting`), through `tests/_lighting/lighting_3d_probe.gd` and the data reads of
`tests/_lighting/lighting_probe.gd`, which keep the plan's numbers as their own consts and read the game only through the published
names below, so a test checks this file and not the code. The code is the Lighting domain (`scenes/lighting/`, skill
`domain-lighting`); the lights and shadows of the world's things are their own domains' (interface 20).

All distances are px and times seconds. The numbers are the Lighting holders' (`LightingConfig`, `LightingFixtureConfig`,
`Lighting3DConfig`, `LightingCostConfig`, in `scenes/lighting/`) and, for what each piece gives, `ObjectArtLightConfig.specs`.

## The 3D lighting

The game is drawn in 3D (`architecture` interface 27, #193): a near top-down orthographic camera over meshes that wear the
2D painters' flat art, shaded by Art's toon light (`toon_common.gdshaderinc`). The Lighting domain's 3D side is
`WorldLighting3D` (`scenes/lighting/world_lighting_3d.gd`), which Main builds under the 3D view's own world after it mirrors the
match (`Main._view3d.light_world`): it reads the 2D world the sim runs in, duck-typed (Objects' floors
(`is_street()`, `size`), a piece's `get_lights()`, the rooms), and builds the lights of the 3D world. Its numbers are
`Lighting3DConfig` (the sun, the heights, the pools) and `LightingCostConfig` (the cost caps), over the dusk's colours and energies
in `LightingConfig`.

**How a pixel is lit.** There is no baked light in any art. Each pixel is its painted colour times the **dusk ambient**
(`LightingConfig.ambient_color`, a toon global, `ToonLight`) plus every light that reaches it: each light's amount (the angle
of the face to it, times its fall-off, times its shadow) is tinted by the light's colour and energy: the
sun's is stepped into `PixelPostConfig.bands` (3: none, a little, the light whole; `ToonLightConfig.levels`), a lamp's pool is a **smooth**
fall-off through `ToonLightConfig.pool_levels` (eight, from a trace, 0.08, to the light whole, each at the middle of its band, times
`pool_strength` 1.9: 2D adds its light in sRGB, where it reads stronger than the same light in the 3D render's linear one), so a pool
fades out to a faint tail with no ring where a band ends (the 2D pool texture's curve: 1 to .75 at .65 of the radius, .4 at .8, .12 at
.92), and a shadow is one hard edge. Test: `lighting/light_3d_pool_smooth_windowed` (windowed: a fixture's, a lamp's and a street lamp's
pool read along a radius have no step between neighbouring pixels over a small share of the pool and no plateau of 4 pixels). The sum is held to `ToonLightConfig.cap` (1.7) of the painted colour by its brightest channel, so a pixel under three
lamps is the art lit warm and not blown out, and the hue stays. A world that sets no ambient is lit by
`ToonLightConfig.default_ambient` (a grey, as the shader multiplies it: no sRGB conversion or gain, so it is as bright as before), not black.

**L1-3D. Dusk.** The ambient is the 2D dusk's, **(0.40, 0.37, 0.55)**, which 2D multiplies the art by in sRGB: the toon light is linear, so
the shader's ambient is that colour taken to linear (`ToonLight.shader_ambient`) times `ToonLightConfig.ambient_gain` 1.8, which keeps
the rooms' hue within a few degrees of 2D's (the kitchen's like-for-like boxes: 21 degrees off with the colour added as it was, 3 now) and
their brightness near it (0.83 of 2D's). One `DirectionalLight3D`, the sky, in `sky_color`
**(1.0, 0.5, 0.42)** at `sky_energy` 0.42, travels toward +x and -y of the 2D world (from the south-west, `sky_from`) at
`sun_elevation` **76** degrees, with hard shadows, so a wall of 96 throws a shadow of 24 px and a person of 74 one of 18: short
like the 2D drop shadow, not the streak of a low sun (a character casts none of it: **L11-3D**). It reaches only the street's floors: a texture of the world (`ToonLight`'s
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
energy, hung where the glowing part of the piece is: the declaration's `lift` (px above the floor, `ObjectArtLightConfig.specs`, one row per kind:
a lamp's bulb at its shade 50, a TV's face 16, a desk monitor's and a monitor wall's 39, a rack's LEDs 72, a rig's and a surgical lamp's 70,
a tool cart's 34, a scanner's 60, a fridge's glass 42, a menu board's 63, a hotplate's 15, a neon tube's 3, a neon trim's 14, a street
lamp's head and a sign at the top of its pole 124), else its kind's `height` (`overhead_height` 60, `street_height` 70, `low_height` 22),
over the declared place on the floor (the piece's own centre, a lamp's and a street lamp's included: it stands on its pole), and
reaching the pool's `radius` times `range_scale` 1.3 on the floor
(its range is the distance to that rim: the pool reaches a little past the 2D one, so the 3D fall-off brings the light of the 2D
smooth tail). An **overhead or street** light pools flat to half its radius and quickly at the rim (`overhead_slope` 2, the 2D
pool's profile); a **low** one is a glow fading from its middle (`low_slope` 1): the toon light's two shapes of one linear
fall-off. **A pool is the same size and look whatever the height of its light**: a light's fall-off follows its distance in 3D, so
a high light would pool smaller; the toon light takes the pool's shape from the ground distance instead (`ToonLight.specular` packs,
in `light_specular`, the light's height over its rim and its height class beside the slope, the room and the kind; the shader
subtracts the fragment's own height from the light's), so a pool is the 2D one however high its light hangs, and a thing above the floor is lit by the pool at its own ground point. A pool is
thinner on what stands taller than a person: from `ToonLightConfig.high_from` 78 px to `high_to` 94 its strength falls to `high_scale` 0.4,
so a wall's top and upper face read dark grey-brown as in 2D (where a lamp's pool lies on the floor and a wall is only its colour, dimly
lit) and not as bright as a crate's top under the same lamp; furniture and bodies, under 78, are lit in full. The nodes are `OmniLight3D`s under the `WorldLighting3D` named `Light<n>_<piece>`, with the metas `piece`, `index` (into
`get_lights()`) and `room`, kept in step with the piece: a shoved lamp carries its light (`process_priority` 20, after the
bodies), and a freed piece's light is freed with it.

**A pool never crosses a wall, and costs no shadow.** Every light knows the room it stands in (the room map,
`ToonLight.set_rooms`: a texture of the rooms' rects, an id each; the light's id and whether it is a street light ride in its
`light_specular`, with the slope: the toon has no specular), and the toon light, which knows the room of each spot, lets a light
reach only the spots of its own room, plus the walls and pieces above the floor that are in no room (so a wall is lit from both
sides). A street light reaches the spots in no room (the street, a tower's outside) and never a room's inside, as in 2D (where
the light layers did it). With no rooms (an arena) nothing is clipped.
Tests: `lighting/light_3d_per_piece` (seed 1: each declared light placed, over its piece's light, at its kind's height, in its
colour and its radius, in its room, at most its energy; every fixture over its room's centre; the fixture's pool and the others' decode to the right height and room),
`lighting/light_3d_light_heights` (a piece of every kind of light: its light over its declared place at its declared `lift`, inside the
height range of its mesh), `lighting/light_3d_pool_packing` (the height and room coded in `light_specular`),
`lighting/light_3d_follows_and_flickers` (a shoved lamp's light follows it; a freed piece's light is freed),
`lighting/light_3d_look_windowed` (a lamp's pool warm, bright at its middle, fading, gone past its radius, and gone at the line
of its room: the next room, a few px over it, is the ambient's).

**L3-3D. Room fixtures.** A room no `room_light` stands in gets an overhead light at its centre, as in 2D (the same colour,
energy and reach, `LightingFixtureConfig`) and the glyph's 3D twin, a **bulb**: a small emissive sphere (`bulb_radius` 3, the light's
colour lightened) hung `bulb_height` (104) up, over the walls' tops as the 2D glyph is drawn over everything, casting no shadow, dimming
with its light's rhythm and fade (its glow is `bulb_glow` times the light's level, a fixture the cost cap has faded off shows no bulb). The fixture is the one light that may cast a shadow, and it casts it from `LightingFixtureConfig.shadow_height_for` up (400, more in a bigger room, at most 600: a wall of 96 at half the room's length throws about 30 px, `shadow_far`), not from the bulb (104): a light that low in a small room throws a
70 tall wardrobe 100 px away across 230 px, where 2D's drop shadow is a few px under the piece (a wardrobe at 400: 21 px, a person 74 tall 200 px from the
fixture 45, a wall of 96 beside it 30, a wall 250 px away in a big room 48; the pool on the floor is the same, as above, and the bulb stays at the ceiling). The shadow is part dark
(`LightingFixtureConfig.shadow_opacity` 0.6, `OmniLight3D.shadow_opacity`), so the floor under a table or a chair is the pool's colour
a step down and not the cold ambient alone (the 2D render has no such blob). Tests: `lighting/light_3d_per_piece`,
`lighting/light_3d_fixture_look` (a bulb per fixture over the walls, glowing, uncast; the shadow part dark),
`lighting/light_3d_shadow_length_windowed` (windowed: a 70 tall box and a 96 tall wall in a fixture's room: each shadow is as long as `edge * height / (light - height)`, `light` the fixture's shadow height, a wall 200 px away in a 600 px room too,
and not the metre of a light at the ceiling).

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

**L11-3D. A character's shadow is short and under it.** A shadow a light casts of a 74 tall body is as long as the light is low (the sun
at 76 degrees 18 px, a fixture 400 up 200 px away 45, a lamp lower: more), where 2D's body casts a drop shadow of a few px. So no part of a
living or fallen body casts a shadow from any light (the sun, a fixture, a lamp, a flash), and its shadow is a drop shadow: a flat patch on the
floor (`MeshNodes.shade`, `shade.gdshader`, unlit, uncast), `CharacterShadowConfig.shade_radius` 1.25 body radii across, shifted `shade_shift`
0.45 radii away from the art's light, `ArtCanvasConfig.drop_shadow_alpha` (0.28) dark, whichever light is near. A body that lies (a fallen one,
a lying one: its head more than `shade_lies` radii from its feet, flat) has the patch stretched along it from head to feet, `shade_width`
radii across; it follows the ragdoll as it settles. The patch is drawn after the outline pass
(`ToonMaterial.SHADE_PRIORITY`: the outline quad copies the screen before the transparent pass, so a patch drawn before it is erased); the
player's view hides it with the body and dims it where the ground is unseen. Tests: `character/character_drop_shadow` (the patch, its size
and place, a disc under a standing body and stretched along a fallen one, no part casts), `lighting/character_shadow_windowed` (windowed: the
floor round the body is darker with the patch than without; and with the character and hidden, what differs lies within 64 px of it, at a
fixture, far from it, in the street's sun and beside a street lamp; before, a fixture's shadow of a body reached 113 px; `CHARSHADOW_DIR=<dir>`
saves the pictures).

**L7-3D. Light sources glow.** What gives light is a glowing part of the piece's mesh (Objects' `FurnitureRig.add_glow`, the
toon's `emissive`, a colour whatever the light), so a lamp's bulb, a screen, a neon tube is its colour in the dusk, apart from its
light; the Lighting domain dims it with its light's rhythm (`glow_changed`, Main wires it to `FurnitureRig.set_glow_level`).

**L8-3D. Rhythms, seeded per light.** As in 2D (`light_rhythm.gd`): the energy of a light changes in the rhythm its declaration
allows, seeded from the world's seed and the piece, so the same world flickers the same. Test:
`lighting/light_3d_follows_and_flickers` (one room lit twice from one seed: every light's energy equal to its twin's in every frame).

**L9-3D. Flashes.** A `shot` lights a muzzle flash and an `explosion` a blast's (a frag's orange, a stun's white), driven by the same
looks as 2D (`LightingConfig.flashes`: colour, energy, `reach` the pool's diameter, `reach_per_radius`, `hold`, `life`): a pooled
`OmniLight3D` at hand height (`Lighting3DConfig.flash_height` 30) lit at the event's point, its pool `reach / 2` times `range_scale`
out on the floor, flat to its middle (every flash's pool uses the `overhead_slope`, as a ceiling light's), held at full energy for its `hold` then falling off to dark over its `life`
as `energy x left^2` (a shot's 0.07, a frag's 0.5, the stun's 0.08 held + 0.7). The pool is the light budget of a firefight:
`Lighting3DConfig.flash_lights` (4), a new flash taking a dark light and else the one with the **least left to run** (the oldest among equals: a dozen shots in a frame light
the last four, and a stun's long white-out is never stolen by a shot),
a flash whose pool the view cannot reach (the focus and the camera's reach) lights nothing and takes no slot. A flash casts **no shadow**
and takes no shadow slot (the room map is its wall: it lights the room it stands in, or a room it is within `flash_room_slack` 8 px
outside of (a muzzle in a doorway), and else, on the street, the spots in no room, as a street light does). Nothing is lit outside the
vision cone: a flash is dimmed where the player does not see (the vision mask's `vision_unseen`, `docs/player-vision.md`: the toon light
scales every light's amount by it, so a flash outside the cone, in a remembered or a never-seen spot, shows as little as a lamp there does). There is no light for a bullet's impact spark (the lights are the world's fixtures, pieces and flashes).
**A flash is coded for the toon light, not lifted over it.** Its `light_specular` says it is a flash (`slope + kind / 4 + 4 x code`, kind 1 a
tint, 2 a white-out), and the toon light adds it to the specular accumulator, apart from the dusk's capped sum: no global is written
while a flash fades, so a lamp's pools far from a blast keep their colour. A **tinted** flash (a shot, a frag) is the surface's own
colour times the flash's colour and energy in the pool's bands, held to `FLASH_MAX` 4 (the floor reads orange as in 2D); a row with
`wash` (the stun) is an **additive white** whole over the pool and fading smoothly out over its last 0.2, with walls
too, so what it reaches is flat white as in 2D, planks, rings and all, and fades with the flash's energy (8, times `left^2`). Both are
masked by the vision mask and the room like any light. Tests:
`lighting/light_3d_flashes_on_shot_and_explosion` (a flash within 3 frames at the muzzle and the burst, in its colour, uncast, at hand
height, dark within 0.25 s and 1.5 s), `lighting/stun_flash_in_match` (a real Main match in 3D: the stun's own burst, near and on the far side of the view, at zoom 1 and 0.5 with shots firing, lights a white-out flash and, windowed, whitens the picture; a burst several screens away takes none), `lighting/light_3d_stun_flash` (white, a white-out for the toon light, a peak of 4.8 or more,
held, still lit at 0.45 s, dark within 1.1 s), `lighting/light_3d_flash_pool` (the cap of the pool, the flash with the least left to
run dropped (oldest among equals), a stun keeps its light through any number of shots, a flash out of the view takes none),
`lighting/light_3d_flash_room` (a flash of its room, a doorway's, the street's), `lighting/light_3d_flash_look_windowed` (windowed:
the floor warm round a muzzle and the ambient's past its reach and after it; the stripes of a plank floor gone, flat white over a whole
region, under a stun, two overlapping lamp pools and the ambient far from it unchanged, a stun in an unseen spot changing no pixel).

*(L5, L6, L10 in 3D: a light is placed at its piece and follows it, L5; who shadows whom is the real geometry, L6: the sky's
shadows by every mesh, a ceiling fixture's by theirs, a wall's included, and a pool is kept in its room by the room cull, not by a shadow;
the switch is above, and with it off no flash is built.)*

## A tower's shadow

The sun casts it: the 3D walls shadow the street. There is no baked shadow decal.
Tests: `general/district_match_staged` (every room of every tower has a light, no two rooms share a key).
