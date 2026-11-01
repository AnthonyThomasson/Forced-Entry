# Ticket: assets

Follow `story.md`; load `domain-art` for anything drawn, `domain-audio` for anything heard, and the `domain-<name>` skills
that own where it goes (painters, the character rig, a gun, an effect). With `bug` or `spike` that kind wins: no showroom.
With `ai`: also `ai.md`. Nothing visible or audible to make (a voice-pool cap): no showroom; say so.

## Grilling: references

Before anything is built, ask for reference material: images, clips, sound files, links, games or films to match, what to
avoid. None given: search the web and offer a few to pick from. Record links and file paths in the plan and the showroom
brief; supplied files stay in the scratchpad, never committed; read images with `Read`.

## Showroom (before the plan)

A `showroom` worker builds it; you run the feedback rounds. Run `show-me` before the first round.

- **Files:** `sandboxes/showroom/<slug>_sandbox.gd` (`<slug>`: the ticket in snake_case, e.g. `muzzle_flash`), helpers in
  `sandboxes/showroom/<slug>/`. It extends `GameTest` like `sandboxes/player_gun_range_sandbox.gd`: a `player` actor, a
  `describe()` name, no assertions.
- **Exhibits:** one per new asset, sound, effect or animation: today's version (if any) beside 2–3 variants A/B/C. A floor
  label each: name, letter, one line on how it differs. At game zoom, beside the real things it will sit among. Animations
  loop; effects and sounds fire when the player steps onto the exhibit's pad. The user walks it as the player.
- **Variants live in the showroom files,** drawn and synthesized through the API `architecture` interface 13 sanctions: a
  showroom painter on `PixelCanvas`, rendered by `PixelArt.render` / `render_turned`; a recipe in `SoundBank`'s shape
  (`SoundBank.recipe_for(profile)` is today's) rendered by `SoundSynth.render(recipe, seed_value) -> AudioStreamWAV` and
  played on the showroom's own `AudioStreamPlayer2D`, so a variant skips `Sound`'s volume and muffle. Today's sound plays by
  posting its real EventBus event. Production code is untouched before acceptance.
- **Exception:** what cannot be shown that way (an animation in the real character rig) goes in its domain behind a
  temporary, named variant switch (`static var`) the showroom flips (`set_static` in `configure`). The plan's risks name it.
- **One set at a time:** the showroom is a staging room with on-screen previous / next buttons and a label naming the set
  shown; a press removes the current set and spawns the next (today's version, then each variant). Setup recipe:
  `assets-showroom.md`.
- **Check:** load check and lint pass (`godot-run`), and each sandbox runs headless without engine errors or warnings
  through every set. No screenshot tours: the user looks at the showroom in the game window (`show-me`).

## Feedback rounds

Before each round run `show-me` so the game window is open (an editor already up without a game gets one opened; never ask
the user to press Play). The sandbox opens from Tests → SANDBOXES, by its `describe()` name (or the runner's `--play
<words>`, `test-debug`). Ask per exhibit: pick A/B/C, steer one, or new variants. The `showroom` worker revises; repeat
until each exhibit has a pick, all before the plan is accepted.

## Plan

The brief's desired behaviour names each new asset, sound, effect or animation and where it shows or plays. In `## Plan`,
per exhibit: the pick, its parameters, the references, the rejected variants and why.

## Build and tests

Rebuild the pick properly in its domain (painter, recipe, config row), not pasted from the showroom; a variant switch
collapses to the pick. Tests per `story.md` phase 3 cover the wiring, mapping and registration; the look is the user's
pick, not asserted.

## Feedback gate and before the audit

The showroom shows the built asset, through the real code, beside the picked variant; an exhibit whose variant was a
switch shows the built version only, compared with the pick's parameters in the plan. Once the user approves, a
`showroom-removal` worker deletes `sandboxes/showroom/<slug>*` and any leftover switch, and the audit brief adds a check
that no showroom file, switch or reference to them remains.
