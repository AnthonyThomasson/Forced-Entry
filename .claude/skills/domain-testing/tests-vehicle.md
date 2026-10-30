## Vehicle tests (domain `vehicle`, `tests/vehicle/`)

The rules are `docs/vehicles.md` (V1 to V9, each with its tests named under it). Thirty puppet-driven tests in `tests/vehicle/`, plus
`tests/audio/vehicle_sounds_test.gd`, `tests/audio/vehicle_door_tone_test.gd`, `tests/general/camera_zooms_out_driving_test.gd` and `tests/general/use_vehicle_key_test.gd` (a
`player` actor and injected E). The shared helper is `tests/_vehicle/vehicle_probe.gd` (`const Probe := preload(...)`; not a test): the plan's
numbers as consts (`DOOR_REACH`, `BOARD_MAX_SPEED`, `EXIT_MAX_SPEED`, `HARM_MIN_SPEED`, `DOOR_OPEN_TIME`, `FOLD_TIME`: `board_animation_is_continuous`
checks the door's and the fold's measured ease against the last two, within 0.4× to 2×) and each kind's door table
(`CAR_DOORS`, `VAN_DOORS`), so a test checks the spec and not the code; `ready` / `has_reads` (a read that does not exist fails a `require`
instead of a script error), `config_value(holder, prop)` / `kind_value` (a Vehicles holder's static read by class name; a missing holder or var is an error, never a fallback), the door and seat reads (`door`, `open_of`,
`seat_of`, `occupant`, `watch_doors` / `opened`) and the draw layers (`layer`, `absolute_z`, `draws_above`). Beside it, the vehicle frame
in `tests/_vehicle/vehicle_frame_probe.gd` (`const VehicleFrame := preload(...)`: `forward`, `right`, `outward`, `stand_point`, `edge`,
`gap_to_solid`, `tail_offset`, `local_velocity`, `pivot`, `outward_slip`, `along`), and placing (`place`, `move_vehicle`), the ride (`exit`,
`board_by`) and driving (`reach_speed`, `hold_speed`, `hold`) in `tests/_vehicle/vehicle_ride_probe.gd` (`const VehicleRide :=
preload(...)`). Everything goes through the drivable contract (interface 19) duck-typed. `tools/run_tests.sh --domain=vehicle` runs the domain; `--changed` on `scenes/vehicle/` runs vehicle, character,
items, interaction, projectile, physics, objects, ai, perf, audio and general.
