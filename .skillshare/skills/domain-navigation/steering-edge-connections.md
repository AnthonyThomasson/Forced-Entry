# Navigation: the steering map's edge-connection pass

Side file of `domain-navigation` (`SKILL.md`); the welded tiles it rests on: `district-tiles-and-avoid.md`.

The server joins polygons that hold the same edge (the same two 1 px cells) and then runs a pass joining free edges of different regions within `default_edge_connection_margin` (1 px). The pass rebuilds the whole map's links on any change: a sync of the 42-tile district costs ~10.6 ms with it and 0.32 ms without, whether one tile or five changed (roughly quadratic in the regions: 21 tiles 2.3 ms, 10 tiles 0.45). The steering map is built **without** it (`NavBuilder._steering_map_for`, `NavSource.new_map(false)`); the planning, ring and avoid maps keep it (nothing measured there).

What makes that safe is the weld (`NavSeams`, `district-tiles-and-avoid.md`): every border edge both tiles hold is one edge to the server, so the hash joins them (`navigation/steering_seams_welded`).

## What the pass left that the weld does not

Asked every ordered pair of every tile's probe point and both ways across every seam edge (`tests/_navigation/seam_probe.gd`), 24 district seeds and a lone house, pass off against pass on:

- **Identical to the point** (0.0 px) on 17 of the 24 seeds and the house, as built; seeds 7 and 23 and the house after a character stops on a corner of four tiles too (`steering_routes_match_edge_connections`, `_other_districts`, `_house`).
- **Different** on 7 seeds, 11 to 172 of ~2000 routes: seed 24 (172, the pass off shorter by up to 224 px), 6 (79, 55 px), 4 (52, 57 px), 17 (48, 1.6 px), 2 (97, 3 px), 1 and 14 (under half a pixel). No route is lost (every destination the pass reaches is reached) and, as built, none is longer.
- **After a character stops on a corner of four tiles** on seed 6, 3 of 2401 routes are longer with the pass off, by up to 105 px (71 shorter, by up to 55 px). The route with the pass on goes through the corner point itself as a hairline, between two obstacle corners that only touch: the pass links two polygons that meet at a point, which no shared edge does and a single mesh would not. The route with it off goes round.
- The differences begin at wall corners on a border, where the pass adds a second, point-like link to polygons already joined by the seam edge; a route through it is pinched through the point. The server does not expose its connections, so this is read from the routes taken apart, not proven.

The user accepted these (2026-11-13): equal-or-shorter routes, every destination reachable, the rare longer one through a pinch the pass invented. `steering_routes_other_seeds_edge_connections` (seed 24) and `_six` (seed 6) pin it as measured: no route unreachable, at most the measured count longer and by the measured px, none shorter by over its bound; a change that makes a route longer or a destination unreachable fails them. A test for a changed bound states the new measurement.

With the sync at ~0.3 ms, a tick's tiles need not land together for the map's sake (`rebake.md`): the burst's one landing stays as it is, it also gives a walker one consistent map.

Measured on `perf/match_10v10_stress --verbose` (load ~3.5): with the pass on all five worst frames were tile-landing frames (30.5 to 45.5 ms, max 45.5 against 33.4); off, the max is 27.1 ms and the tile frames are 25 to 26 ms. A same-fight `tools/perf_ab.sh` (8 rounds) 10v10_stress avg -1.6 %, npc_vision -1.6 %.
