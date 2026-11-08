# UI tests (domain `ui`, `tests/ui/`)

The inspector, its detail card and the overlay scope (`domain-ui` (`hud.md`, `overlays.md`)); the player-less match they run in is a test world with an arena. `tools/run_tests.sh --domain=ui` runs them.

- **Tests:** `inspector_right_click_card` (a right-click opens the card with the outfit lines; a second one on the NPC or on empty ground clears them, `docs/outfits.md` O13), `inspector_point_in_card` (a left-click on a
  tactical point fills the Point section), `inspector_scope` (the overlays by scope and selection; the brain's labels and `drawn()` on the selected NPC alone), `detail_card_fits_window` (the card's rect ends inside the 1152×648
  window with a populated brain, the wheel scrolls the Point section into view without zooming the camera, a right-click on the card passes through), `detail_card_width_and_dead` (560 px, the `DEAD` title),
  `detail_card_empty_hand` ("—" for a hand holding nothing), `overlay_scope_sides` and `overlay_scope_saved_per_mode` (`domain-main` (`overlays.md`)), `main_no_demo_panel`, and `ai/debug/overlay_text_in_card` (`domain-ai` (`debug-words.md`)).
- **`tests/_ui/inspector_probe.gd`** (`const InspectorProbe`, not a test; used by the inspector, card and scope tests, so a test copies none of it): real mouse input at a world point or a screen point (`click`, `right_click`,
  `click_screen`, `wheel`), `SIDES` (the four scope-world NPCs `d1`, `d2`, `i1`, `i2` and their sides), `lit(t, prop)` (which of them show an overlay property, in `SIDES` order), `overlays_with(character, prop)` and
  `section(card, heading)` (the body label under a card heading, shown upper-cased). A change to `tests/_ui/` runs the `ui` domain under `--changed` (`runner-flags-changed.md`).
- **A test window is 64 × 64 headless.** A test that reads a layout against the project's window (a panel that must end inside it) first sets the screen a player has: `OrderMenu.player_screen(t, true)` (`tests/_ai/order_menu_probe.gd`).
- **A click at a world point needs a still view** (`OrderMenu.view_still`, `SKILL.md`'s gotchas).
- **Main's live tree.** `main_no_demo_panel` also opens Main whole with a played match (`tests/_main/main_probe.gd`, `tests-entry.md`) and reads the tree it builds, so a panel built at run time shows up.
