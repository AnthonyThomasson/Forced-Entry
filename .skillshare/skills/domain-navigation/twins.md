# Navigation: the bake reads the twins

Side file of `domain-navigation` (`SKILL.md`). ADR 0014 ("The nav bake reads the twins").

Since #194 del2d-c the bake's source is the 3D twins of the twin space (`TwinSpace`, interface 29), not the 2D colliders. `NavTwins` is the
reader: `parts(body, grounded)` the `[shape, pose]` of each shape of the body's twin (`TwinSpace.twin_for`, in the tree), `footprints` their plan polygons
(`TwinShapes.footprint_of`), `stamp_of(body)` what a footprint depends on (the twin and its pose), `walls_under(house)` the walls (a `StaticBody2D`
that reports `wall_segments`; pieces are `RigidBody2D`s: both still found by engine type until the 2D bodies go). A body with no twin has no footprint: a
house with no twin space bakes no walls and no holes, so `MatchBuilder.stage` makes the twin space before it bakes, and a test that adds a piece waits a
frame for its twin.

- **Walls** (`NavSource.walls_of(house, frame)`): the plan footprint of each *grounded* shape of each wall twin (`grounded`: its underside within
  `NavTwins.FLOOR_SLACK` of the floor), moved into the house's frame by `frame * house.global_transform.affine_inverse()` and snapped to the 1 px grid.
  A wall twin also holds a **lintel** over each doorway (84 to 96 px up): it is not grounded, so it closes no doorway. The bake projects at the plan and never by an agent's height.
- **Holes** (`NavHoles.cut`): the convex hull of each shape's footprint grown by `OBSTACLE_MARGIN` (a polygon offset, corners mitred: a
  rectangle stays one); an upright cylinder (a round piece, a character) is `NavHoles.CIRCLE_SEGMENTS` (10) points round `r + margin`, as the 2D circle
  was (the twin's own 16-sided disc moved ambush posts and broke recorded AI fights). A tipped piece's twin is tilted: the hull of what its parts reach.
- **Caches** (`NavPieces`, `NavHoles.hull_of`): a hull is cut again when its stamp (twin and pose) changes. A dent does not change a twin (it keeps the
  outline it was built with), so a shot-up piece's hole stays its full footprint, and a wall's dent is already in its twin (`WallTwin`).
- **A footprint moved by hand** (a 2D piece's `global_position` set by a test) reaches its twin up to `TwinSpace.PARK_SPREAD` frames later: wait for it, or move the twin.
- **What it moved** (measured against the old 2D-collider read when the bake moved to the twins, a test since deleted with the colliders it compared against): the same walls; the same holes but for
  a piece hung on a wall (a menu board, a mirror, a towel rail), which carves its twin's depth (about half its collider's); the same navmesh area and a polygon
  fewer; every route found, none over 3% longer or shorter.
- Still 2D: finding pieces by engine type (walls are found by the group `walls`), a character's `collision_layer`, a fallen door's `fallen_footprint` (a 2D collider).
