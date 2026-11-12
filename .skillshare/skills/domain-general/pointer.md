# Pointer

Side file of `domain-general` (`SKILL.md`).

`Pointer` (`pointer.gd`, `class_name`, static; interface 26) is the one place a screen point and a world point are converted. Each method takes a node of the world and reads that node's viewport: `world_of(node, screen)`, `screen_of(node, world)`, `screen_transform(node)` (world to screen), `visible_world_rect(node)`, `screen_mouse(node)` and `world_mouse(node)`. In 2D it is the viewport's canvas transform (the active `Camera2D`'s view; the identity with no camera or viewport), so a world in a second viewport converts by its own view; #193's 3D view swaps the bodies for a camera ray meeting the ground plane.

- `inject(screen)` stands a screen point in for the mouse until `release()`: `screen_mouse` and `world_mouse` (what feeds the player's aim, the camera's look-ahead and the command menu's non-mouse fallback) return it. It never warps the real mouse (the command server's `aim` does that, through `Pointer.screen_of`), and an input event keeps its own position. `TestWorld.restore` releases it (`domain-testing`).
- Tests: `tests/general/pointer_converts_test.gd` (both-way conversion and the visible rect under a camera at a known position and zoom, worked out by hand), `pointer_inject_test.gd` (injection, no warp, release and restore).
