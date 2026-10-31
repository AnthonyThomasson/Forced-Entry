# Vehicle art

`vehicle_visuals.gd` draws two layers, `Chassis` and `Roof` (a `layer` export), on the world's draw ladder (`DrawLayers`, interface 11):

- `Chassis` at `UNDER_VEHICLE` (−1) is over everything on the floor (`LYING`: a fallen body, casings, a dropped item, a grenade at rest) and its decals, and under the living and the occupants (`STANDING`). Test: `vehicle/fallen_body_under_vehicle`. It holds the drop shadow (the outline pushed away from `ArtCanvasConfig.light_from`), the wheels, the body's `chassis` art and each door's `panel` at its pose.
- `Roof` at `ABOVE` (+1) is over the occupants: the body's `roof` art, each glazed door's `glass` (fading over the first `glass_fade` of its opening), the wing mirrors, the brake lights while `brake_lights()`, and the dents (`Deformation.draw_marks`). The car's roof starts at x 10 so a driver's head and hands show through the windscreen.

## Painters (`art/`)

- `car_painter.gd` / `van_painter.gd` paint a body (`opts.part` `chassis` or `roof`); `door_painter.gd` (`panel` / `glass` / `mirror`), `wheel_painter.gd`, `lamp_painter.gd`. Each is `static func paint(c, base, material, opts)` (interface 12) and reads its geometry from the `VehicleConfig` `kinds` and `looks` rows, wrapped in `VehiclePaint`.
- `vehicle_art.gd` holds the shared helpers (`paint_parts`, cabin `seats` / `dashboard` / `sills`, door frames, the lamps).
- The body painters cut holes where each door's side glass goes (`clear_door_glass`), because the door draws that glass.
- **Body painters call no `cast_shadows`**: a body is repainted for every lighting step it turns through and the pass walks the whole canvas; bevels shade it instead. The small door panel does call it.

## Regions and caching

- `vehicle_art.region` builds a `PixelConvexShape` from a vehicle-frame point test, once per geometry key and canvas size (`_regions`), and reuses it for every lighting step. A mask `PixelShape` would test every pixel on each paint; a convex one's fill, bevel and outline cost only its edge. The test must be convex along both canvas axes.
- Every texture goes through `PixelArt.render_turned`, lit for the nearest of `ArtCanvasConfig.turn_steps` steps and drawn rotated to the exact angle. A layer redraws only when its `_key()` changes: the lighting step, the body's turn in `redraw_turn_step` steps (the shadow), each door's amount and the wheel angle in `redraw_step` steps, and on the roof the brake lights and the dents. Once the engine runs, `_warm_ahead` paints the other lighting steps one a frame, nearest first, so turning never waits on a paint.
