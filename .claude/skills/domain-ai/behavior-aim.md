# AI locomotion: pointing the agent (`aim`)

Side file of `behavior-locomotion.md`: `scenes/ai/behavior/locomotion/loco_aim.gd`.

`NavigationAgent2D.target_position` asks the server for a path at once, and the server scans every polygon of the map to place the path's two ends, so a path per walker per frame is the biggest nav cost of a match on a district's map (ten times a house's polygons). `aim.at(agent, goal)` sends the target only when the goal or the agent's map changed or `tuning.pace.reask_frames` (4) frames have passed; every place that set the target goes through it. The period is the model: the agent moves on at `path_desired_distance`, so a path that stands cuts a corner a path asked from the body keeps, and a long wait (20 frames) lets a walker press into the wall for a second (`ai/entry/stack_reach_garage_home_garage_exit`); the entry tests are sensitive to the walk's timing (`ai/entry/entry_team_flows_in`). Test: `ai/movement/walk_requeries_only_on_change`.
