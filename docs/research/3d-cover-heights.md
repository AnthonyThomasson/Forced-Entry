# Research: real heights for cover, sight and grenade throws

## Sources and method

Primary texts read: TC 3-23.30 (22 Nov 2013), FM 23-30 (2000, "Grenades and Pyrotechnic Signals"), FM 3-06.11 (2002) ch.3 and ch.5, and the ANSUR II public CSVs (computed here). FM 3-21.8, FM 21-75 / TC 3-21.75 and ATTP 3-06.11 (2011) could not be fetched (globalsecurity.org and irp.fas.org answered 403 or empty), so they are cited from secondary summaries only. Each figure carries a tag: **[P]** read in a primary source; **[D]** derived or estimated from primary numbers (the method is stated); **[S]** a retail or design guide, approximate; **[U]** unverified, from memory or a search-engine summary. Postures other than standing, and every game default in section 6, are **[D]**, good to about +/- 0.05 m.

Grenade release heights (section 4, about 1.7 m standing, 1.3 m kneeling, 0.4 m alternate prone) are not used yet: they land with the grenade-arc job (`grenade3d`), which reads them as the release height of the throw's posture.

## 1. Human heights (metres)

### Measured (ANSUR II, 4,082 men / 1,986 women, mm, standing, computed from the public CSVs) [P]
Source: https://tools.openlab.psu.edu/publicData/ANSUR_II_MALE_Public.csv and `..._FEMALE_Public.csv` (landing page https://www.openlab.psu.edu/ansur2/; report: Gordon et al. 2015/2012, NATICK/TR-15/007, https://apps.dtic.mil/sti/pdfs/ADA611869.pdf). Columns used: stature, acromialheight, cervicaleheight, chestheight, waistheightomphalion, iliocristaleheight, sittingheight, eyeheightsitting.

| Dimension | Men mean (p5-p95) | Women mean (p5-p95) |
|---|---|---|
| Stature (top of head) | 1.756 (1.648-1.870) | 1.628 (1.525-1.740) |
| Shoulder (acromial) height | 1.441 (1.339-1.546) | 1.335 (1.242-1.434) |
| Neck base (cervicale) | 1.517 (1.416-1.623) | 1.396 (1.300-1.498) |
| Chest (nipple) height | 1.291 (1.200-1.387) | 1.172 (1.080-1.266) |
| Waist (navel) height | 1.056 (0.972-1.145) | 0.980 (0.900-1.064) |
| Iliac crest height | 1.062 | 0.996 |
| Sitting eye height (seat to eye) | 0.805 (0.750-0.860) | 0.748 (0.698-0.799) |
| Sitting height (seat to head top) | 0.918 | 0.857 |

ANSUR II has no standing eye height column (only `eyeheightsitting`). Pooled mean stature is about 1.72 m.

### Postures (muzzle/eye) [D]
Method: standing eye = stature minus ~0.12 m (vertex to eye outer corner; standard anthropometric approximation, not read from a table). Bore = eye minus ~0.065 m (M4-style sight-over-bore). Kneeling/crouch/prone are geometric estimates (hip drops ~0.4 m on one-knee kneeling; prone is body thickness plus raised head), not published values. Treat +/-0.05 m.

| Posture (male mean, 1.76 m) | Eye | Rifle bore / muzzle line | Head top | Notes |
|---|---|---|---|---|
| Standing | 1.64 | 1.55-1.58 | 1.76 | shoulder 1.44 |
| Crouch (high, hip/knee flexed) | ~1.35 | ~1.28 | ~1.45 | |
| Kneeling (one knee) | ~1.24 | ~1.17 | ~1.36 | torso upright |
| Low kneel / squat | ~1.0-1.1 | ~0.95 | ~1.2 | |
| Prone | ~0.25-0.35 | ~0.2-0.25 | ~0.3-0.4 | head raised behind rifle |

Scale women by about 0.93 (1.628/1.756).

### Target zones (standing man) [D from ANSUR landmarks]
- Head: about 1.52-1.76 m (neck base to vertex; ~0.23 m tall).
- Upper torso / centre mass (thoracic): about 1.05-1.50 m (waist to shoulder), chest centre ~1.29 m.
- Pelvis/abdomen: ~0.85-1.05 m. Legs: below ~0.90 m (crotch/trochanter height is 0.90 m men, 0.85 m women: `trochanterionheight`).
- Doctrinal framing: soldiers "firing over the top" of cover and "silhouetting" are the common errors, because standing exposes "the entire length of his body" (FM 3-06.11 3-7a and 3-42a, see section 2).

## 2. Cover vs concealment doctrine

- Definitions [S/U]. A study guide citing FM 3-21.8 (https://www.armystudyguide.com/content/SMCT_CTT_Tasks/Skill_Level_1/0713260502-sl1-move-under.shtml) says cover protects "from enemy direct or indirect fire" and concealment hides but "doesn't protect you from enemy direct or indirect fire." FM 3-21.8 itself was not read. Official wording is in ATP 3-21.8 / ATP 3-37.34 glossary [U].
- Urban cover materials [P]. FM 3-06.11 (2002) ch.3 Camouflage section (para 3-36a): "Thick masonry, stone, or brick walls offer excellent protection from direct fire and provide concealed routes." (https://www.theblackvault.com/documents/fm/fm30611/ch3.pdf). Ch.5 (defense): reinforce positions with "mattresses, furniture"; "Drawers and cabinets should be filled with earth or sand to provide cover"; fabric furniture and mattresses are flammable; vehicles (trucks/buses) can be placed over outside positions (https://www.theblackvault.com/documents/fm/fm30611/ch5.pdf, para on reinforcing positions). Implication: empty furniture is concealment (and only partial cover); filled/solid masonry is cover.
- Thin walls [P]. FM 3-06.11 3-14a(3): fragments can penetrate "Sheetrock or thin plywood" walls, soldiers should lie flat helmet toward the detonation or move away from any wall that might be penetrated. TC 3-23.30 (2013) 2-12/2-13 for fragments (section 4).
- Fire around, not over, cover [P]. FM 3-06.11 ch.3 para 3-7a: "The most common errors a soldier makes when firing from a position are firing over the top of his cover and silhouetting himself... The correct technique... is to fire around the side of the cover, which reduces exposure." Also 3-7b: fire from the shoulder that keeps the body behind the corner (right-handed shooters left corner problem). Walls (para on walls, Fig 3-43): "When firing from behind walls, the soldier must fire around cover and not over it." Corners: do not fire standing, "he exposes himself at the height the enemy would expect a target... risks exposing the entire length of his body."
- Windows [P]. FM 3-06.11 (window firing, Fig 3-44): do not stand in a window, it "exposes most of his body" and silhouettes against a lighter interior; fire kneeling, "well back into the room" so muzzle flash is hidden. Movement past windows: "exposing the head in a first-floor window" and forgetting basement windows are the common mistakes (para 3-3). Keep >=12 in (0.3 m) off a wall to avoid ricochets/"rabbit rounds" (para 3-2).
- Crossing a wall: "rolls over the wall quickly, keeping a low silhouette" (3-5).
- Kneeling vs low obstacles [P]. TC 3-23.30 2-47: kneeling is "used primarily from behind low-level ground cover". FM 23-30 (2000) 3-3: kneeling for "a low wall, a shallow ditch, or similar cover". Standing "should only be used when cover and concealment is readily available" (TC 3-23.30 2-43).
- Numeric cover height: no doctrinal figure found. Derived in section 6 from the posture table.
- Exposure when firing over cover [D]. If the bore must clear the cover top, the shooter exposes everything above bore line minus a few cm: about head, eyes and shoulders (~0.25-0.35 m of body standing over a ~1.2 m wall; ~0.25 m of head kneeling over ~0.95 m). Around a corner you expose ~one eye, one shoulder and the rifle, a strip about 0.2-0.3 m wide but full height if standing.

## 3. Furniture and building heights (metres) [S unless noted]

Retail/design guides, no ANSI/BIFMA figure found. Ranges, not standards.

| Item | Height | Source |
|---|---|---|
| Dining/table | 0.76 (30 in) | https://www.homenish.com/?p=12122 style guides; Kitchen/dining guides |
| Desk | 0.72-0.76 (28-30 in) | https://www.maxihome.com.sg/blogs/news/furniture-heights-tall-short-people |
| Kitchen counter | 0.85-0.92 (34-36 in); base cabinet 34.5 in = 0.88 | https://planner5d.com/blog/standard-kitchen-counter-height/ ; https://kitchencabinetkings.com/kitchen-cabinet-sizes |
| Sofa seat | 0.43-0.48 (17-19 in) | https://roomstogo.com/inspiration/how-to-measure-furniture |
| Sofa overall/back | 0.76-0.91 (30-36 in); up to 1.0 | https://www.interiorinsider.com/articles/sofa-dimensions-guide ; https://www.wayfair.ca/sca/ideas-and-advice/guides/sofa-dimensions-how-to-choose-the-right-size-sofa-for-your-home-T5610 |
| Bed (top of mattress) | ~0.55-0.65 [U], bed bench 18-20 in (0.46-0.51) suggests frame+mattress ~0.5-0.65 | https://www.wayfair.ca/sca/ideas-and-advice/guides/what-is-the-standard-bench-height-and-other-bench-dimensions-to-know-T5732 |
| Refrigerator | 1.70-1.78 (67-70 in) | https://itemfits.com/dimensions/appliances |
| Bookcase | ~1.83 (72 in) typical tall; low ones 0.9-1.2 | https://itemfits.com/reference/furniture-dimensions |
| Vertical filing cabinet | 2-drawer 0.74 (29 in); 4-drawer 1.32 (52 in); lateral 2-drawer 0.71, 4-drawer 1.27-1.35 | https://upgradedhome.com/file-cabinet-dimensions ; https://www.findofficefurniture.com/answers/storage-filing/filing-cabinet-dimensions-guide.html |
| Tall pantry cabinet | 2.13-2.44 (84-96 in) | https://kitchencabinetkings.com/kitchen-cabinet-sizes |
| Ceiling (residential min.) | 2.13 (7 ft) habitable rooms/halls, 2.03 (6 ft 8 in) bath/laundry; typical new build 2.44 | https://www.jaspector.com/codes/irc-2024/ch03-building-planning/ceiling-height-requirements-irc-2024/ |
| Door opening (clear) | >= 2.03 (80 in) per IBC/ADA; typical slab 2.03 | https://idighardware.com/2026/04/decoded-projections-into-the-clear-opening-height-of-doors/ |
| Window sill | 0.8-1.0 [U] | not sourced |

## 4. Hand grenades (M67 unless noted)

- Specs [P]: TC 3-23.30 Table 2-5 (para 2-12): body steel sphere, 6.5 oz Comp B, fuze M213, delay 4.0-5.5 s, weight 14 oz (0.40 kg), "Throwing Distance of Average Soldier 35 meters", casualty-producing radius 15 m, killing radius 5 m. Warning: "fragments can disperse as far as 230 meters." (Offensive MK3A2 concussion: casualty radius 2 m open, fragments/fuze bits to 200 m.) Older FM 23-30 (2000) 3-5: frag grenades engage enemy within a radius of 40 m and are "equally lethal to friendly and enemy soldiers". Live-fire pits are 25 m apart to sit outside the 15 m radius (TC 3-23.30 4-73). Mirrors: https://www.armywriter.com/board/references/TC3-23x30.pdf ; https://www.bulletpicker.com/pdf/FM-23-30-2000.pdf
- Technique [P]: TC 3-23.30 2-42 to 2-52. Throw "overhand so that the grenade arcs, landing on or near the target"; body sideways to the enemy; observe the target "no more than 3 seconds"; grenade held "4 to 6 inches behind the throwing ear" before release (release point is about head height, ~1.7-1.9 m standing with extended arm [D]); follow through. No launch angle is specified.
- Positions [P]: standing = most distance, "most desirable" (2-43) but needs cover available; prone-to-standing/kneeling for speed; kneeling "reduces the distance" and is for "low-level ground cover" (2-47); alternate prone (on back) "reduces both distance and accuracy", used when pinned down (2-51). Qualification stations use 20-35 m targets, kneeling at 20-25 m and alternate prone at 20 m (FM 23-30 / DA 3517-R).
- Cook-off [P]: TC 3-23.30 2-38/2-39 and Table 2-10: M67 may be cooked ~2 s in combat only ("one thousand one, one thousand two"), so it bursts above ground or shortly after impact and denies the enemy time to throw it back. Never for stun/short-delay grenades (M84 fuze 1.0-2.3 s, can fire at 0.7 s). FM 3-06.11 3-14: "Normally, the fragmentation grenade should be cooked off for two seconds."
- Airburst [P]: FM 23-30 3-4: bursting above a target in a trench/bunker is more effective; on slopes the grenade must burst near impact "to prevent its rolling away".
- Rooms, doors, windows, stairs [P]: FM 3-06.11 3-14: throw overhand or underhand, either hand; to throw into an upper-story opening stand close to the wall "using it for cover", only when the opening is free of glass or screen, cook ~2 s then step out and lob; plan where to run if it "falls back to the ground". After throwing: announce "frag out" and take cover since the grenade "may bounce back or be thrown back". FM 23-30 3-9: "Grenades tend to roll back down stairs and either nullify the desired effect(s) or cause friendly casualties." Stun grenade is designed to be thrown through an open door or a standard glass window (FM 23-30 1-10). Thrower "must consider the flight path... to make sure no obstacles... cause it to bounce back" (FM 23-30 App. B).
- Secondary summary of urban rebound/roll/glass behaviour [S]: https://www.inetres.com/gp/military/infantry/grenade/use.html (says frags often rebound off hard targets/window frames, a 1 m window at 20 m is a high miss chance; verify against the primary manual).
- Fragments vs obstacles and posture [P/D]: Thin partitions (Sheetrock, thin plywood) are penetrated; thrower lies flat, helmet toward the burst (FM 3-06.11 3-14a(3)). Thrower seeks cover or drops prone facing detonation (TC 3-23.30 2-44(8), FM 23-30 3-3). Confined-room overpressure adds to danger (FM 3-06.11). The Army documents give no fragment height envelope or low-wall protection percentages. [S] inetres: fragments do not penetrate a single sandbag layer, cinder block or brick, do perforate wood-frame/tin walls, floor blasts hit lower floors, furniture/mattresses/doors/books partly shield. [D] Fragments of a ground burst fly mostly in a low-angle ring plus upward cone, so prone and behind a solid obstacle with height above the body greatly cuts exposure; a low obstacle (below ~0.3 m) next to a prone body helps little unless it is between you and the burst point.

## 5. Out of scope
Hearing through walls/floors skipped as instructed.

## 6. Implications for a game (defaults to use)

Units: metres, floor z = 0. Add per-character +/-0.05 m variation if wanted.
- Character: stature 1.75, shoulder 1.44, standing eye 1.64, standing bore 1.55, kneel eye 1.24 / bore 1.17 / head top 1.36, crouch eye 1.35, prone eye 0.30 / bore 0.22 / head top 0.35. Hit zones: head 1.52-1.76, torso 1.05-1.50, legs 0-0.90 (kneeling: torso 0.7-1.15).
- Cover rule: a surface at height h blocks a ray if the ray is below h there. Full cover for a posture needs h >= head top (standing 1.76, crouch 1.45, kneel 1.36, prone 0.40). Fire-over rule: the shooter can fire over cover with h <= bore + ~0.05 (standing <= 1.55, kneel <= 1.17, prone <= 0.25) and then exposes head/shoulders, so doctrine prefers "around not over".
- Obstacle classes by top height: 0.4 (low wall, bed foot, coffee table) = prone cover only; 0.75 (table, desk, counter-ish) = kneel/crouch cover, fire over from standing; 0.9 (counter, low wall, sofa back) = kneel cover, standing fires over; 1.2 (high wall, 2-drawer to chest filing, tall counter) = crouch/kneel full cover, standing partly exposed; 1.7-1.8 (fridge, bookcase, 4-drawer cabinet at 1.32 is mid) = full cover for standing except tall heads; walls 2.4.
- Material rules: solid masonry/concrete/filled cabinets = bullet-stopping cover; wood/furniture = concealment plus partial (e.g. reduced damage); Sheetrock/thin plywood walls = concealment only, fragments and bullets pass through. Keep 0.3 m off walls for ricochet.
- Grenade (M67): mass 0.40 kg, release height ~1.7 standing / ~1.3 kneeling / ~0.4 alternate prone; max range 35 m standing (30 m average per older tables), ~70% kneeling and ~50% prone (estimates, doctrine only says "reduces"); fuze 4.5 s default (range 4.0-5.5), cook-off 2 s gives ~2.5 s remaining; casualty radius 15 m (50% casualties), kill radius 5 m, fragments hazardous to 230 m but treat as tail risk. Damage falloff by distance and by cover height; ground burst: prone behind a solid obstacle at least ~0.5 m high takes near zero; standing exposed full damage; thin walls do not block.
- Throws: need line-of-flight clearance; an arc peaking ~2-3 m for 10-20 m, clears a 1.5 m obstacle if released at 1.7 m; windows/doors rebound off frames, glass breaks; grenades roll back down stairs; floors blast lower rooms. Room entries: allow the 2 s cook, "frag out", 1-3 s thrower exposure, enemy can throw it back if not cooked.

## 7. The heights the game uses

The numbers `BodyHeights` (General) and `PieceHeights` / the `ObjectMesh*Config` holders (Objects) hold, from the
tables above. One scale: 1 3D unit = 1 px, a 1.75 m person = 74 px, so **1 m = 42.3 px**. The wall (96 px, 2.27 m) and
the door leaf (84 px, 1.99 m) are unchanged. A test (`tests/objects/piece_heights_test.gd`) pins every catalogue
kind's top inside the metres of section 3 and its mesh to it.

### Postures (metres, px = metres x 42.3)

| Posture | Head top | Eye | Muzzle (bore) | Shoulder | Hit-zone bands (m, feet up; above the last is the head) |
|---|---|---|---|---|---|
| Stand | 1.75 (74 px) | 1.64 (69.4) | 1.55 (65.5) | 1.44 | feet 0-0.10, legs to 0.90, torso to 1.52 |
| Duck | 0.85 (36 px) | 0.76 (32.1) | 0.70 (29.6) | 0.68 | feet 0-0.06, legs to 0.42, torso to 0.72 |
| Fire-over | 1.22 (51.6 px) | 1.10 (46.5) | 1.02 (43.1) | 0.96 | feet 0-0.08, legs to 0.55, torso to 1.00 |

Stand is section 1 and 6 (stature, eye = stature - 0.12, bore = eye - 0.065; torso from the crotch, ANSUR
`trochanterionheight` 0.90, to the neck base 1.52). Duck is the "low kneel / squat" row dropped to a head top of
0.85 m, so a piece of at least that top hides the whole body (section 6: full cover needs `h >= head top`). Fire-over is
the pose a ducked body rises to when its muzzle line is blocked: its bore (1.02) clears 0.9 m cover with the head and
shoulders (0.96 and up) showing above it, the "over, not around" exposure of section 2. All three are estimates (+/- 0.05 m),
tunable in `BodyHeights.postures`.

### Furniture tops (metres; the real range, then the game's, px in brackets)

Low cover (about 0.9 m: a kitchen counter 0.90 body with a 0.14 backsplash, a sofa back 0.90, a dresser, a bar counter
0.95, a sandbag barricade 0.95) hides a duck; a bench 0.45 (19) and a coffee table 0.43 (18) do not; table height is 0.73 (31), side table 0.52 (22), desk 0.73, bed
mattress 0.52 with a 0.80 headboard, sofa seat 0.43 / arm 0.66 / back 0.90, chair seat 0.43 / back 0.90, fridge 1.75 (74),
bookshelf 1.82 (77), wardrobe 1.84 (78), filing cabinet 1.32 (56), nightstand 0.61 (26), floor lamp 1.47 (62), coat rack
1.70 (72), shower glass 1.89 (80), vending machine 1.84 (78), drinks fridge 1.89 (80), awning edge 1.89 (80) and a hanging
sign 1.84 (78), both over a standing head. The full list is the `REAL` table in the test and each holder
(`ObjectMeshKitchenConfig`, `ObjectMeshStorageConfig`, `ObjectMeshSeatConfig`, ...).

### The rise to fire

A ducked body rises only as far as it must (`BodyHeights.lowest_clearing(top)`): the lowest posture whose muzzle clears the cover. Cover under the duck's own muzzle (0.70 m) needs no rise; cover up to the fire-over muzzle (1.02 m) is fired over from `FIRE_OVER`; taller cover up to a standing muzzle (1.55 m) from `STAND`; above that nothing clears it and the body fires around it (section 2: "fire around, not over"). Cover is built to hide a duck by a real margin: every piece meant as cover is at least 0.04 m over the duck's head (the sandbag barricade is 0.95 m, a crate stack 0.95 m), and no solid piece is within 0.04 m of it.
