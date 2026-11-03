25. **Main / Testing (through `MatchBuilder`) → Vision: the player's view** (`scenes/vision/`; spec `docs/player-vision.md`; Vision is a leaf:
    it imports only General and reads the viewer and the world duck-typed)
    - `PlayerView.watch(root: Node, character: Node2D) -> PlayerView` builds the view of what `character` sees under `root` (a `Node2D` in the
      group `player_view`, named `PlayerView`) and returns it; null while `VisionConfig.enabled` is off and for a character already dead (no
      view of the dead). A match has one view (more than one viewer is out of scope). `MatchBuilder.populate` (23) calls it for the match's human (the handle's `view`; none with no
      human, so Watch and Endless draw everything); the Testing world (13) calls it for its `player` actor, or the actor `TestSetup.view(id)`
      names, when the `vision.enabled` switch is on (off unless a test asks). Viewing a character changes nothing in it or its AI.
    - **What it reads of the viewer** (duck-typed, 7): `global_position`, `facing`, `get_rid()`, `sight() -> Dictionary` (a method of the Character body, 7: `{ fov_degrees,
      view_distance, awareness_radius, see_over_coverage }`, its `CharacterVisionConfig`), `is_dead`, and the signals `died` and
      `tree_exiting`: either **lifts** the view (the node, its composite and its viewports are freed within a frame, `SeenArea.clear()` at
      once, so everything is drawn and repainted again, live, for the rest of the match).
    - **What it reads of the world:** the physics space (`SightRay`, 11, on `PhysicsLayers.SOLID`), the groups `floors` (the memory's
      bounds) and, through each blocker, `get_surface()` (`coverage`, `transparent`) and the signal `changed` (a door). It writes `SeenArea`
      (11) each rebuild. It draws at `DrawLayers.VISION` and sorts the world by `ViewLayers` (11): its capture leaves `MOVING` and `OVERLAY`
      out of its cull mask.
    - **Test reads** on a `PlayerView` (helpers in `tests/_vision/vision_probe.gd`): `viewer()`, `cone() -> PackedVector2Array` (the eye, then
      one corner per ray; empty without a facing), `bubble()`, `sees(point) -> bool`, `rebuilds() -> int` (how often the cone was rebuilt), `corner_rays() -> int` and `corners_read() -> int` (the last rebuild's rays to corners and corners read: its cost),
      `memory()`, `capture()`, `mask()` (the `SubViewport`s), `painter()`, `mask_painter()`, `composite()`, `memory_scale()`, `wiping()`.
    - **Tuning:** `VisionConfig` (`enabled`, the look `grey` / `contrast` / `pivot` / `brightness` / `tint`, `feather`, `memory_scale`,
      `cone_rays`, `bubble_rays`, `corner_offset`, `far_depth`, `far_bleed`, `rebuild_every`); what a character sees by is Character's
      `CharacterVisionConfig` (7). The Testing switch `vision.enabled` sets `VisionConfig.enabled`.
    - **Owners of the moving and overlay bits** (11): Character, Items, Projectile, Physics and Vehicles put what they own on `MOVING` and back
      on `WORLD` at rest; the AI's debug overlays, Navigation's `NavDebug` and the UI's markers are overlays; Lighting keeps its flash lights
      under a `CanvasLayer`, since a light ignores the cull mask (`domain-lighting`).
