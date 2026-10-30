---
name: architecture
description: The architecture map for this Godot project (Forced-Entry) — the sixteen isolated domains, the cross-cutting conventions, the whole sanctioned cross-domain interface surface (an index; each interface's text in a file of its own), and the dependency graph. Load this BEFORE planning any change or exploring the codebase, and whenever you need to know where something lives or how two domains are allowed to talk. Points to each domain's `domain-<name>` skill for that domain's deep implementation detail.
---

# Forced-Entry architecture

A small top-down Godot 4.4 demo: a pixel-art character you walk with WASD (run on **Shift**, crouch on **C**) around a
procedurally furnished house, aiming at the mouse, with a punch on **F**, a kick on **V**, a gun (pistol, SMG or assault rifle)
that fires on left-click and reloads on **R**, stun and frag grenades thrown on left-click, items picked on **1**–**9**, object
interactions on **Space** (sit, lie, …) and, in the sandbox, a car or van to get into on **E**. The code is
organized into **sixteen isolated domains** so each can be changed on its own. The world is lit at dusk with real 2D
lights and shadows (the Lighting domain).

This skill is the **map**: the domains, the sanctioned cross-domain surface (the vital
interfaces), and the dependency graph. Keep changes inside a domain, and cross a boundary only
through the interfaces listed here. **When working *inside* a domain, also load its
`domain-<name>` skill** — that is where the deep implementation detail lives. A domain that has been split into
sub-domains keeps a short overview skill and one `domain-<domain>-<sub>` skill per sub-domain (listed in the table below); the
composition root is `domain-main`.

## The sixteen domains (one folder each under `scenes/`)

| Domain | Folder | Skill | Owns |
|---|---|---|---|
| **World Generation** | `worldgen/` | `domain-worldgen` | Picking a logical floorplan (front door, exits, hallways) and building/furnishing a house, and placing its run-down dressing (clutter, neon, where wear gathers) and the street round it with its street lamps. |
| **Objects** | `objects/` | `domain-objects` | The world's objects (furniture, walls, floors, the street), their wear and decals: their data, how they're hit/pushed, and their painters (what each piece looks like, in the run-down style). |
| **Items** | `items/` | `domain-items` | The things the character holds and the actions they perform, and what it wears (outfits: garments, armour plates). |
| **Character** | `character/` | `domain-character` (+ `domain-character-body` for `character/body/`) | The player character (built so other character types can exist). |
| **Interaction** | `interaction/` | `domain-interaction` | Object interactions: finding a reachable object and running one of its actions (sit, lie, …). |
| **Projectile System** | `projectile/` | `domain-projectile` | Shooting: penetration (the target's and the bullet's own power), a character's armour stopping a round, damage, cover, ricochet; and a grenade's burst (`Explosion`: the frag's blast and fragments, the stun's flash and bang). |
| **Physics System** | `physics/` | `domain-physics` (+ `domain-physics-blood` for `physics/blood/`) | Physical reactions: forces, knockback, deformation, debris and hit particles, a grenade burst's look (flash, fireball, smoke, scorch: `Physics.spawn_explosion`), ragdoll, and blood (its own sub-folder, `physics/blood/`). |
| **Art** | `art/` | `domain-art` | The procedural pixel-art engine every painter draws through: the canvas, the cached renderer, the shared light/tone/surface tuning. |
| **Audio** | `audio/` | `domain-audio` | The procedural sound system: every sound is synthesized in code, picked by event (gunshots per gun, bullet impacts per surface / outcome / round weight, footsteps per floor and gait, reloads, a grenade's throw, bounce, burst, a vehicle's ignition, doors, crashes, engine and skid loops) and played by the `Sound` autoload through a capped pool of positional voices; a deafened `Sound.focus` (the human) gets a muffle and a tinnitus whine. |
| **Lighting** | `lighting/` | `domain-lighting` | The world's dusk lighting, a leaf like Audio (`docs/lighting.md`): the ambient and the sky, a light per light-giving piece (declared by the piece) and per room fixture within a per-floor budget, their seeded rhythms, the shot and explosion flashes, and who stands in a light. |
| **Navigation** | `navigation/` | `domain-navigation` | Baking the house into a walkable nav map so characters can path around walls. |
| **General** | `general/` | `domain-general` | Infrastructure: input (Keybinds), saved settings (`Settings`), the event bus (`EventBus`), the log (`GameLog`), the pausable game clock (`GameClock`), despawner, camera, dev command server, shared physics-layer ids (`PhysicsLayers`), the draw-order ladder (`DrawLayers`), the light masks (`LightMasks`), the batched plain-colour drawing (`FillBatch`), the shared weighted roll (`WeightedPick`) and the match verdict (`MatchVerdict`). |
| **UI** | `ui/` | `domain-ui` (+ `domain-ui-menus`, `-hud`, `-command`, `-overlays`, `-testing` for `ui/<folder>/`) | All HUDs and menus, one sub-domain per folder: menus (pre-game setup window, settings page), hud (debug player panel, match HUD, spectator inspector and its contact markers, stun screen, stack markers), command (the human leader's command menu and order markers), overlays (overlay registry, toggle bar, performance overlay, the squad-leaders overlay) and testing (test browser window, test result banner). |
| **AI** | `ai/` | `domain-ai` (+ `domain-ai-perception`, `-snapshot`, `-decision`, `-behavior`, `-combat`, `-coverage`, `-watch`, `-entry`, `-debug`, `-team`) | Non-player brains: one generic controller that drives every NPC, split into four sub-domains (perception, decision, behaviour, debug) around a thin orchestrator, plus `ai/team/` (the human's stack, interface 17; each side's squad, interface 21). The sub-domain map, the doorway stack's seam and the doorway views are `domain-ai`'s. |
| **Vehicles** | `vehicle/` | `domain-vehicle` | Drivable vehicles (a car and a van, only in the sandbox): the rigid body and its driving model, doors and seats, getting in and out (the character's `CharacterVehicleUse` component and the ride), collisions and the harm to a character struck, the dents, the vehicle art and its events. |
| **Testing** | `testing/` | `domain-testing` | Game tests: a second composition root that builds a declared world (arena, hand-laid room layout or generated house) with chosen behaviour switches, runs a test's script against it and asserts what happened; the in-game test browser + runner, and the gdUnit4 suites the headless CLI runner (`tools/run_tests.sh`) and the editor's GdUnit panel run. Test cases live in `tests/<domain>/*_test.gd`, or one folder deeper by topic (`tests/ai/entry/`), each played through its folder's wrapper suite (`*_suite.gd`); pure-logic native suites (`tests/<domain>/<name>_suite.gd`) only add to them; sandboxes to play by hand (`GameTest` scripts with no assertions) live outside `scenes/` in `sandboxes/*_sandbox.gd`. |

`scenes/main.gd` (`main.tscn`) is the **composition root** — with the Testing domain's runner
(interface 13), the only code that knows every domain. It keeps the UI flow: the setup window, the settings page, the endless run, the HUDs
and the overlay bar; the setup window's **Tests** button sends it to the test browser instead. A match itself is built by the root's
match-assembly module, **`MatchBuilder`** (`scenes/match_builder.gd`, interface 23), with its placement helper `scenes/match_spawner.gd`:
a match spec goes in (`Main.start_match(spec)` is Main's one way into a match), a match handle comes out. It asks World-Gen for a house,
bakes the nav map and lights it (`WorldLighting.light`, interface 20) right after the bake, waits until the navigation maps answer with the
new house, places the NPCs, arms and styles every character for its side (its loadout; the match's police unit or a defender's crew style
and weapon style, read off `CharacterStyleConfig.styles`), ranks the unit and builds the squads. The Testing domain's world stages its own
worlds and binds its NPCs through the same module, and builds a declared match or declared squads with it, so a test measures the match Main
plays. Match lifecycle (Start / Watch / Endless, teardown, the Von-server wait), the placement rules, Main's `run` (`MainRun`, an
exported `Resource`) and its endless exports are the **`domain-main`** skill. `project.godot` autoloads only five: `Keybinds`, `Despawner`, `EventBus` and `GameClock` (all
General) and `Sound` (Audio).

## The vital interfaces (this is the whole cross-domain surface)

Everything not listed here is private to its domain. The signatures live only in this skill's `interfaces/` files, one
per interface: a domain's skill names the interfaces it takes part in (by number) and describes how they're implemented.

1. **Main → World Generation** (through `MatchBuilder`) — Main, World-Gen. Read to generate a house (`WorldGen.generate`) or use its catalogue lookups and street: `interfaces/01-main-to-world-generation.md`
2. **World Generation → Objects** — World-Gen, Objects. Read to spawn a piece, wall, floor or wear (`ObjectFactory`, `WallFactory`, `FloorFactory`, `WearFactory`): `interfaces/02-world-generation-to-objects.md`
3. **The "hittable" contract** — Objects, Character, Vehicles and their strikers (Projectile, Items, Physics). Read to hit something or make something hittable (`take_hit`, `HitInfo`, cover): `interfaces/03-hittable-contract.md`
4. **Objects / Character / Vehicles → Physics** — Physics and the domains that compose it. Read for knockback, deformation, debris, hit particles, ragdoll, blood or an explosion's look: `interfaces/04-physics.md`
5. **The "pushable" contract** — Objects, Vehicles, Character. Read to shove a body (`apply_impulse`, `get_mass`): `interfaces/05-pushable-contract.md`
6. **Items ↔ Character** — Items, Character, Projectile. Read for an item's API, guns and ammo, grenades, the loadout, outfits: `interfaces/06-items-and-character.md`
7. **Character ↔ Controller** — Character, AI, General (input). Read to drive a character (the controller child, `movement`, the components' public API): `interfaces/07-character-and-controller.md`
8. **Interaction ↔ Character & Objects** — Interaction, Character, Objects. Read for object interactions (sit, lie, …): `interfaces/08-interaction.md`
9. **Main / Testing / AI → Navigation** — Navigation and its users. Read to bake, query or path the nav map (`NavBuilder`): `interfaces/09-navigation.md`
10. **Any domain ↔ General (EventBus)** — every domain. Read to post or listen to an event, and for every topic's payload: `interfaces/10-eventbus.md`
11. **General → every domain: shared ids and rules** — General, every domain. Read for `PhysicsLayers`, `DrawLayers`, `LightMasks`, `GameClock`, `FillBatch`, `WeightedPick`, `MatchVerdict`: `interfaces/11-general-shared-ids-and-rules.md`
12. **Objects / Character / Items / Vehicles → Art** — Art and its painters' domains. Read to render pixel art (`PixelArt`, `PixelCanvas`, `PixelShape`): `interfaces/12-art.md`
13. **Testing → every domain** — Testing, every domain. Read for what a test world may build and call: `interfaces/13-testing.md`
14. **Main → General settings, UI settings page** — Main, General, UI. Read for saved settings and key rebinding: `interfaces/14-settings.md`
15. **Any domain → General (`GameLog`)** — every domain. Read to print to the game's log: `interfaces/15-gamelog.md`
16. **Objects → Audio: `SoundSurface`** — Objects, Audio. Read for what a floor tells Audio: `interfaces/16-soundsurface.md`
17. **Main / Testing → AI team: the human's place in a stack** — Main, Testing, AI team, UI. Read for `PlayerStack` and the human on the entry radio: `interfaces/17-player-stack.md`
18. **Main → Audio: `Sound.focus`** — Main, Audio. Read for whose ears the player has: `interfaces/18-sound-focus.md`
19. **Character ↔ Vehicle: the drivable contract** — Character, Vehicles. Read for getting in, driving, and a vehicle striking a character: `interfaces/19-drivable-contract.md`
20. **Main / Testing → Lighting, and the world's lights and shadows** — Lighting, Objects, Character, General. Read to light the world, add a light or an occluder: `interfaces/20-lighting.md`
21. **Main / Testing → AI team: the squads, their leaders and their orders** — Main, Testing, AI team, UI. Read for `Squad`, leaders, orders and following: `interfaces/21-squads.md`
22. **Main → UI: setup window, match HUD, spectator inspector, overlay bar** — Main, UI. Read for how Main wires a HUD or the overlay bar: `interfaces/22-main-to-ui.md`
23. **Main / Testing → MatchBuilder: building a match** — Main, Testing, MatchBuilder. Read to build a match or a test world (`MatchBuilder`): `interfaces/23-match-builder.md`

### Dependency graph (arrows = "calls / knows"; no cycles)

```
main ──(start_match: build; spec_from_setup / random_spec; set_overlay)──▶ MatchBuilder (the root's match module) ─▶ match_spawner (placement: the NPC scenes; bound through the `bind` Callable it is handed, so it never calls back)
TestWorld (Testing) ──(stage / bind_npc / entry_point_for / populate / squads_over / set_overlay)──▶ MatchBuilder
MatchBuilder ─▶ WorldGen ─▶ ObjectFactory / WallFactory / FloorFactory / WearFactory ─▶ Objects ─▶ Physics
MatchBuilder ─▶ NavBuilder (build, ready, steering_map; match_spawner furniture_holes) ──(parses static colliders)──▶ NavigationServer2D;  MatchBuilder ─▶ NavDebug / NavUpdater (Navigation, overlay + re-bake)
main ─▶ Character ◀─ PlayerController ─▶ Keybinds
MatchBuilder (arm) ─▶ LoadoutConfig ─▶ GunConfig / MagazineConfig / OutfitConfig / ItemRegistry (random_gun_slot / loadout_for / spares_for) ─▶ Character.inventory.set_loadout / wardrobe.outfit.set_ids / wardrobe.set_style;  main ─▶ LoadoutConfig (the setup window's rows, normalize)
MatchBuilder ──(the styles' side / weapons)──▶ CharacterStyleConfig.styles
main ─▶ Settings ─▶ Keybinds   /   main ─▶ SettingsMenu (UI; signals only, no dependency on Settings)
main ─▶ SetupMenu / MatchHUD / SpectatorInspector / OverlayToggles / PerformanceOverlay / OverlayRegistry (UI; plain dicts in, signals out);  MatchBuilder ─▶ LeaderOverlay / OverlayRegistry (UI: build_leader_overlay, set_overlay)
main ──(is_resolved / resolved: the Von wait)──▶ DecisionServerLauncher (AI)
Character ─▶ Item ─▶ ProjectileSpawner ──(get_surface / take_hit)──▶ Objects;  Projectile ──(get_surface_at / take_hit)──▶ Character ─▶ Outfit (Items)
Character ─▶ Interaction ──(get_interactions)──▶ Objects
Character ─▶ CharacterVehicleUse (Vehicles) ─▶ Vehicle   (the ride and a strike call back only the character API of interface 19, as an Item calls its user's)
Character ─▶ Deformable / Deformation / BloodWound / BloodFootprints / Ragdoll / HitInfo / Physics.impact_impulse / spawn_debris / bleed_out (Physics)
Vehicle ─▶ Deformable / Deformation (draw_marks) / Physics.impact_impulse / Physics.spawn_debris (Physics);  Vehicle ─▶ PhysicsLayers (General)
Objects / Character / Item / Vehicle ──(painters)──▶ PixelArt / PixelCanvas / PixelShape / ArtCanvasConfig / ArtSurfaceConfig   (Art, a leaf)
AIController ─▶ NavigationAgent2D ─▶ NavigationServer2D   (writes Character.movement.move_input; tactics query the nav map)
AI (perception / behaviour / team / debug) ─▶ NavBuilder (ready / snap / route / path_length, avoid_map, planning_region, steering_map)
AIController ─▶ ItemRegistry slot ids (Items: FISTS_SLOT, STUN_SLOT, FRAG_SLOT)
Physics debris / hit particles / blood / explosion fx, Projectile casings ─▶ Despawner
Projectile / Explosion / Character ──(&"hit" events)──▶ EventBus ──(posted)──▶ AIController
AIController ──(&"callout" events)──▶ EventBus ──(posted)──▶ allied AIControllers
PlayerStack (human) ◀──(&"callout" entry steps)── EventBus ──(&"callout": the human's claim)──▶ allied AIControllers;  StackMarkers (UI) ──(view())──▶ PlayerStack
AI behaviour (entry.gd and its parts entry/entry_*.gd, behavior_orders.gd, behavior_entries.gd) / orchestrator (npc_comms.gd) / team (PlayerStack, Squad) ──(StackClaim / ClaimLedger / DoorStack / StackLayout, preloaded; AgentPerception.entry.stack)──▶ AI perception's stack/ (the stack seam)
AI team (Squad, SquadFollow, PlayerStack and its step_up) ──(AgentEntry, the doorway geometry built with no NPC; AgentVision.wall_hit; HouseRooms; preloaded)──▶ AI perception
AIController (npc_reflexes.gd) / behaviour (follow) ──(follows / leader / follow_spot, SquadFollowConfig)──▶ Squad (AI team)
AI behaviour's locomotion (locomotion/loco_doors.gd) ──(perception_views.gd, preloaded to type doors.views, handed perception.views by Behavior.setup; walk_route)──▶ AI perception's views part
MatchBuilder ──(build_squads: Squad.setup, bind_squad; bind_player: PlayerStack.attach)──▶ Squad / PlayerStack (AI team);  Squad ──(&"order")──▶ EventBus ──(posted)──▶ AIControllers;  Squad ◀──(&"callout" order_step, entry claims)── EventBus;  MatchBuilder.bind_squad ──(squad)──▶ PlayerStack;  StackMarkers (UI) ──(view(): stacks)──▶ Squad
CommandMenu (UI) ──(order_requested)──▶ main ──(issue)──▶ Squad;  CommandMenu / OrderMarkers / LeaderOverlay (UI) ──(view())──▶ Squad;  CommandMenu ──(resolve())──▶ Squad;  CommandMenu ─▶ Keybinds.COMMAND;  CommandMenu ─▶ ItemRegistry.STUN_SLOT / FRAG_SLOT (Items, via inventory.item_count)
AI perception ──(Explosion.shields / first_stop: the blast's cover rule)──▶ Explosion (Projectile)
ThrownGrenade (Items) ──(Explosion.frag / .stun)──▶ Explosion (Projectile) ──(take_hit / blast_push / take_stun, ProjectileSpawner fragments, Physics.spawn_explosion)──▶ Objects / Character / Physics
Item (&"shot") / GrenadeItem (&"throw") / ThrownGrenade (&"grenade") / Projectile (&"hit") / Character (&"hit", &"footfall", &"reload") ──(events)──▶ EventBus ──(posted)──▶ Sound (Audio) ─▶ SoundBank (and its families) ─▶ SoundSynth
Character (&"footfall") ──▶ EventBus ──(posted)──▶ AIController (footsteps heard)
Objects Floor ──(SoundSurface.register)──▶ SoundSurface ◀── Sound   (Audio, a leaf: imports nothing but EventBus)
main ──(Sound.focus = the human)──▶ Sound   /   Character (&"stun") ──▶ EventBus ──▶ Sound (tinnitus + muffle for the focus), StunScreen (UI)
Explosion (&"explosion") ──▶ EventBus ──▶ Sound (the burst) / Camera (shake) / AIController
ThrownGrenade (&"grenade") ──▶ EventBus ──▶ AIController (a grenade heard coming down)
Vehicle (&"vehicle", &"engine", &"skid") ──▶ EventBus ──▶ Sound ──(engine_state / slip / speed, duck-typed)──▶ the vehicle's loops
Camera ──(target.use.vehicle().view_zoom_out(), duck-typed)──▶ Vehicle
UI (DebugUI / MatchHUD / SpectatorInspector) / Camera ──(exported path + signals)──▶ Character  (the inspector debug_zones / known_contacts_for_display / debug_focus on the AI controller; DebugUI and the inspector wardrobe.outfit.view())
DebugUI ─▶ LoadoutConfig.grenade_options (Items)
main ──(Tests button: scene change)──▶ TestBrowser ─▶ TestRunner ─▶ WorldGen / factories / MatchBuilder (the world stage, binding) / Character scenes / EventBus
Sandbox (Testing) ──(own painter)──▶ PixelArt / PixelCanvas (Art);  Sandbox ──(recipe_for / render)──▶ SoundBank / SoundSynth (Audio) ─▶ its own AudioStreamPlayer2D
TestBrowser / TestRunner / TestWorld ─▶ UI (TestBrowserWindow / TestResultHUD / OverlayToggles / PerformanceOverlay / OverlayRegistry)
TestRunner / GameTestSuite ─▶ Camera (General: frame(targets), pan_enabled)
GameTestSuite / UnitSuite / test_report_hook (Testing) ─▶ GdUnitTestSuite / GdUnitTestSessionHook (the gdUnit4 addon);  TestRunner / GameTestSuite ─▶ TestSession (plays one test)
MatchBuilder (stage: main's match and every TestWorld) ──(WorldLighting.light)──▶ WorldLighting (Lighting, a leaf) ──(get_lights(), the groups `floors` and `characters`, duck-typed)──▶ the world
Item (&"shot") / Explosion (&"explosion") ──▶ EventBus ──▶ WorldLighting (flashes)
Objects (walls, solid pieces, street floors) / Character (the living body) ──(LightMasks.occluder, STREET)──▶ LightMasks (General)
MatchHUD (UI) / CommandServer `match` (General) ──(decide)──▶ MatchVerdict (General)
TestWorld ─▶ vehicle scenes (TestSetup.vehicle)
TestSession / TestWorld ─▶ DecisionStub / DecisionServerLauncher / NPC scenes (AI), config-holder statics (behaviour switches)
TestBrowser ──(Back: scene change)──▶ main
```

Physics, Navigation, Art, Audio, Lighting and World-Gen are leaves — apart from General's infrastructure (`GameLog`, `EventBus`,
`Despawner`, `GameClock`, `PhysicsLayers`, `DrawLayers`, `LightMasks`, `FillBatch`, `WeightedPick`), which every domain may use (World-Gen's only outward code dep is
the four factories and their `RoomWalls` / `WearPlan`; Navigation depends only on Godot's `NavigationServer2D`; Art
only on Godot's `Image`; Lighting reads the world only duck-typed). Tuning is split into seventy-nine `class_name` static holders, one per topic, each with 15 vars or fewer
(`docs/adr/0003-config-holders-split-by-topic.md`); a domain's holders share its stem, so
`grep -r "class_name Character.*Config" scenes` lists the Character ones, and each domain skill says what each holds.
World-Gen's `LayoutRules` (which rooms may
hold the front door or an exit, which room types may share a door) is a rules table in the same style, not
tuning. There is no `Config` autoload. Three more static holders are not tuning but shared ids (General, interface 11):
`PhysicsLayers` (a physics-layer id, the same role `Wall.Side` plays for doorway sides), `DrawLayers` (the shared draw-order
ladder every domain's z knob starts from) and `LightMasks` (the occluder bits, shadow masks and light layers).
The holders, domain by domain, and what each holds: `tuning-holders.md`.


## Cross-cutting conventions

Three conventions hold across domains; the per-domain specifics live in each domain's skill.

- **Layered control / animate / draw.** Within an entity the three verbs live in separate files,
  wired via the scene tree (no `class_name` on scene scripts but a typed component's, below; cross-file calls resolve through
  `$` / `get_parent()`). A "draw" file is attached to its own child `Node2D` (Godot only draws
  from `CanvasItem`s). Ordering: a parent's `_physics_process` runs before its children's. One exception: a primed ambusher's body
  (`process_physics_priority` 1, interface 7, `docs/leadership.md` D37) runs after its own children that process at the default 0 (its
  `Hands`, its `BloodWound`) on those frames, so its hands read the body a frame behind; harmless at a post, where it holds still and
  does not punch. Character's children keep no priority of their own (setting one would leave interface 7).
- **Runtime shapes.** Collision shapes are built **in code in `_ready()`**, not in the scene
  (layout is data-driven). Because of this the editor shows a "no shape" warning on the character scenes'
  `CollisionShape2D` (`character_base.tscn`, so `Player` and the NPCs) — **that is expected** (walls are built in code); don't add scene shapes.
- **Typed components.** A body too big for one file is split into **typed components** held as public properties
  (`character.movement`, `character.inventory`, …), each one topic, at most 15 vars and 20 public methods; callers name the
  component (no forwarders on the body), and the body keeps only what scenes author, what every domain reads as plain
  state, and the contracts that name the body (`docs/adr/0004-the-character-split-into-typed-components.md`,
  `docs/adr/0005-items-and-vehicle-split-into-typed-parts.md`). A
  component is a `class_name` `RefCounted`, or a `class_name` Node child where a scene authors it (the character's
  `Wardrobe`, `CharacterWardrobe`, and the NPC's tuning topic nodes, below): the scene scripts with a `class_name`, so
  their holder can type them. A polymorphic
  base splits the same way, per concern: each part a small base its kinds subclass where they behave differently
  (`item.art`, `item.ammo`); what differs by kind only as data goes in the kind's config row; and no part holds a
  `RefCounted` owner (a cycle never frees: an item's parts are handed the user on each call), while a node's may hold
  it (the vehicle's). The AI splits the same way (`docs/adr/0006-the-ai-orchestrator-and-behaviour-split.md`,
  `docs/adr/0007-ai-perception-and-team-split-into-typed-parts.md`), with two differences. Its tunables are per NPC, in
  typed topic nodes under the controller's `Tuning` child (`tuning: NpcTuning`, fifteen `class_name` `Npc<Topic>Tuning`
  nodes holding only exports, since an export must name a global class), which behaviour's modules, perception and the
  snapshot's vocabulary read live (`tuning.<topic>.<name>`), and perception's geometry modules and the planner copy each
  decision (PlayerStack and the squads build those modules with no NPC).
  The other is how the AI's parts are reached: by preload const, with no `class_name`. That, and which parts each AI
  module, the shell, Main, `Keybinds`, a world piece, `WorldLighting`, `TestContext` and `TestSession` hold, how they are
  reached, and what each part may hold of its owner: `typed-components.md`.

## Running & verifying

The main scene, the worktree editor, the change's tests in a window and the verification ladder (load, lint, tests,
live game, matches, perf): `running-and-verifying.md`.
