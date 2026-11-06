---
name: architecture
description: Use before planning any change or exploring the code, and to find where something lives or how two domains may talk. The domain map, the cross-domain interfaces and the dependency graph.
---

# Forced-Entry architecture

A top-down Godot 4.4 demo: a pixel-art character in a procedurally furnished house lit at dusk, plus AI defenders and invaders. The code is **seventeen isolated domains**, one folder each under `scenes/`. Keep a change inside its domain and cross a boundary only through an interface below. Inside a domain, also load its `domain-<name>` skill. `GLOSSARY.md` holds the terms.

## The seventeen domains

A folded sub-domain is a side file `.claude/skills/<skill>/<name>.md`.

| Domain | Folder | Skill | Owns |
|---|---|---|---|
| World Generation | `worldgen/` | `domain-worldgen` | Floorplan (front door, exits, hallways), building and furnishing a house or tower, its doors, its run-down dressing, the downtown district (towers, streets, lamps, shells). |
| Objects | `objects/` | `domain-objects` | Furniture, walls, floors, the street and the house doors: data, hit / push behaviour, wear and decals, every painter. |
| Items | `items/` | `domain-items` | What a character holds and does with it (guns, grenades, loadout), and what it wears (outfits). |
| Character | `character/` | `domain-character` (`body.md`; `character/body/`) | The player character and its components, built so other character types can exist. |
| Interaction | `interaction/` | `domain-interaction` | Finding a reachable object and running one of its actions (sit, lie, …). |
| Projectile | `projectile/` | `domain-projectile` | Shooting (penetration, armour, damage, cover, ricochet) and a grenade's burst (`Explosion`). |
| Physics | `physics/` | `domain-physics` (`blood.md`; `physics/blood/`) | Forces, knockback, deformation, debris, hit particles, an explosion's look, ragdoll, blood. |
| Art | `art/` | `domain-art` | The procedural pixel-art engine every painter draws through, and its shared tuning. |
| Audio | `audio/` | `domain-audio` | Procedural sound: synthesized in code, picked by event, played by the `Sound` autoload. |
| Lighting | `lighting/` | `domain-lighting` | The dusk ambient, a light per light-giving piece and room fixture, flashes (`docs/lighting.md`). |
| Vision | `vision/` | `domain-vision` | The player's view: cone, memory, greyscale outside. |
| Navigation | `navigation/` | `domain-navigation` | Baking the house into a nav map, and re-baking it. |
| General | `general/` | `domain-general` | Infrastructure: input, settings, `EventBus`, `GameLog`, `GameClock`, `Despawner`, camera, dev command server, shared ids and helpers. |
| UI | `ui/` | `domain-ui` (`menus.md`, `hud.md`, `command.md`, `overlays.md`, `testing.md`; `ui/<folder>/`) | Every HUD and menu. |
| AI | `ai/` | `domain-ai` (`perception.md`, `snapshot.md`, `decision.md`, `behavior.md`, `combat.md`, `coverage.md`, `watch.md`, `entry.md`, `debug.md`, `team.md`) | NPC brains: one controller for every NPC around five sub-domains (orchestrator, perception, decision, behaviour, debug), plus `ai/team/` (the human's stack, each side's squad). `domain-ai` holds the sub-domain map. |
| Vehicles | `vehicle/` | `domain-vehicle` | Cars and vans (sandbox only): driving, doors, seats, getting in and out, collisions, dents. |
| Testing | `testing/` | `domain-testing` | Game tests: a second composition root that builds a declared world, runs a test against it, asserts; the test browser and runner; gdUnit4 suites. Cases live in `tests/<domain>/` (one folder deeper by topic), sandboxes in `sandboxes/`. |
| Main | `main.gd`, `match_builder.gd`, `match_spawner.gd` | `domain-main` | The composition root, no domain: it builds a match and is the one place that knows every domain. |

**Composition root.** `scenes/main.gd` (`main.tscn`) and the Testing runner (interface 13) are the only code that knows every domain. A match is built by `MatchBuilder` (`scenes/match_builder.gd`, interface 23) with its helper `scenes/match_spawner.gd`: a match spec in (`Main.start_match(spec)`), a match handle out. Main's flow, placement rules, the endless run: `domain-main`. Autoloads (`project.godot`): `Keybinds`, `Despawner`, `EventBus`, `GameClock` (General) and `Sound` (Audio). `GameLog` and the other General helpers are `class_name` statics.

## The cross-domain interfaces

Everything not listed here is private to its domain. A signature lives only in its `interfaces/` file; a domain skill names the interfaces it takes part in by number.

1. **Main → World Generation** (through `MatchBuilder`). Read to generate a house or district, or use the catalogue and street: `interfaces/01-main-to-world-generation.md`
2. **World Generation → Objects.** Read to spawn a piece, wall, floor, wear or decal: `interfaces/02-world-generation-to-objects.md`
3. **The "hittable" contract** (Objects, Character, Vehicles and their strikers). Read to hit something or make something hittable: `interfaces/03-hittable-contract.md`
4. **Objects / Character / Vehicles → Physics.** Read for knockback, deformation, debris, particles, ragdoll, blood, an explosion's look: `interfaces/04-physics.md`
5. **The "pushable" contract** (Objects, Vehicles, Character). Read to shove a body: `interfaces/05-pushable-contract.md`
6. **Items ↔ Character** (+ Projectile). Read for an item's API, guns and ammo, grenades, the loadout, outfits: `interfaces/06-items-and-character.md`
7. **Character ↔ Controller** (Character, AI, General input). Read to drive a character: `interfaces/07-character-and-controller.md`
8. **Interaction ↔ Character & Objects.** Read for object interactions: `interfaces/08-interaction.md`
9. **Main / Testing / AI → Navigation.** Read to bake, query or path the nav map: `interfaces/09-navigation.md`
10. **Any domain ↔ General (`EventBus`).** Read to post or listen to an event and for every topic's payload: `interfaces/10-eventbus.md`
11. **General → every domain: shared ids and rules.** Read for `PhysicsLayers`, `DrawLayers`, `LightMasks`, `GameClock`, `FillBatch`, `WeightedPick`, `MatchVerdict`: `interfaces/11-general-shared-ids-and-rules.md`
12. **Objects / Character / Items / Vehicles / World Generation → Art.** Read to render pixel art or pre-warm the shared district textures: `interfaces/12-art.md`
13. **Testing → every domain.** Read for what a test world (house, arena or district) may build and call: `interfaces/13-testing.md`
14. **Main → General settings, UI settings page.** Read for saved settings and key rebinding: `interfaces/14-settings.md`
15. **Any domain → General (`GameLog`).** Read to print to the game's log: `interfaces/15-gamelog.md`
16. **Objects → Audio: `SoundSurface`.** Read for what a floor tells Audio: `interfaces/16-soundsurface.md`
17. **Main / Testing → AI team: the human's place in a stack.** Read for `PlayerStack` and the human on the entry radio: `interfaces/17-player-stack.md`
18. **Main → Audio: `Sound.focus`.** Read for whose ears the player has: `interfaces/18-sound-focus.md`
19. **Character ↔ Vehicle: the drivable contract.** Read for getting in, driving, and a vehicle striking a character: `interfaces/19-drivable-contract.md`
20. **Main / Testing → Lighting; the world's lights and shadows.** Read to light the world or add a light or an occluder: `interfaces/20-lighting.md`
21. **Main / Testing → AI team: squads, leaders, orders.** Read for `Squad`, leaders, orders and following: `interfaces/21-squads.md`
22. **Main → UI.** Read for how Main wires a HUD, the setup window or the overlay bar: `interfaces/22-main-to-ui.md`
23. **Main / Testing → `MatchBuilder`.** Read to build a match or a test world: `interfaces/23-match-builder.md`
24. **Objects' `Door` ↔ Character, AI, Testing: the door contract.** Read to open, turn, hit or walk through a house door: `interfaces/24-door-contract.md`
25. **Main / Testing → Vision: the player's view.** Read to build or read a view: `interfaces/25-vision.md`

## Dependency graph

An arrow is "code references" (class names or preloads). No cycles.

```
main ──▶ worldgen, navigation, lighting, vision, ai, items, character, audio, ui   (a match is built by MatchBuilder)
main ──(Tests button: scene change)──▶ testing (TestBrowser)
testing ──▶ every domain; builds its worlds through MatchBuilder (a second composition root)
Sandbox ──(recipe_for / render)──▶ SoundBank / SoundSynth (Audio) ─▶ its own AudioStreamPlayer2D
worldgen ──▶ objects (the six factories, `DecalFactory` among them, RoomWalls, WearPlan, `SharedTextures`, and `DoorConfig.open_angle`: 24), art (`PixelArt.warm`: 12)
objects ──▶ physics, art, audio (SoundSurface.register)   (a door posts `&"door"`: 10; a nav bake leaves the group `doors` out but carves a leaf at its open stop, duck-typed: 9, 24; a door's swing nudges a character clear, duck-typed: 7, 24)
character ──▶ items, interaction, vehicle (CharacterVehicleUse), physics, art   (and a house door, duck-typed: interface 24, and `DoorConfig.step_degrees`)
items ──▶ projectile, art          projectile ──▶ physics          vehicle ──▶ physics, art
ai ──▶ navigation, items (slot ids, GrenadeConfig), projectile (CoverRule, Explosion), character (CharacterMovement)   (and a house door, duck-typed: 24)
ui ──▶ items, physics            (plain dicts in, signals out; never calls Main)
every domain ──▶ general
```

- Which domains are leaves, which are reached duck-typed, what `EventBus` carries, and the AI's own seams: `dependency-notes.md`. A new edge, façade, contract method or signal goes into this graph or the interfaces (`audit` checks it).

## Cross-cutting conventions

- **Layered control / animate / draw.** Within an entity the three verbs live in separate files wired by the scene tree. Scene scripts have no `class_name` (a typed component's has), and cross-file calls resolve through `$` / `get_parent()`. A draw file sits on its own child `Node2D` (only `CanvasItem`s draw). A parent's `_physics_process` runs first. Two exceptions: a primed ambusher's body runs at `process_physics_priority` 1 (`docs/leadership.md` D37, interface 7), and a `Vehicle` at -1, so it moves before the characters it strikes; Character's children keep none.
- **Runtime shapes.** Collision shapes are built in code in `_ready()`. The editor's "no shape" warning in `character_base.tscn` is expected; keep scene shapes out.
- **Typed components.** A body too big for one file splits into typed components held as public properties (`character.movement`, `character.inventory`, …), each one topic, ≤ 15 vars and 20 public methods (gdstyle's `max-class-variables`, `max-public-methods`). Callers name the component; no forwarders. A component is a `class_name` `RefCounted`, or a `class_name` Node where a scene authors it. A polymorphic base splits per concern into small bases its kinds subclass (`item.art`, `item.ammo`); what differs by kind only as data goes in the kind's config row. ADRs 0004 to 0008. The AI's parts, owner references and the shell: `typed-components.md`.
- **Tuning** lives in `class_name` static holders, one per topic, ≤ 15 vars (ADR 0003); there is no `Config` autoload: `tuning-holders.md`.

## Running and verifying

The verification ladder, the worktree editor and the change's tests in a window: `running-and-verifying.md`.
