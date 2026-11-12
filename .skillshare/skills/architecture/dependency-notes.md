# Architecture: notes on the dependency graph

Side file of `architecture` (`SKILL.md`).

- **Leaves:** Physics, Navigation, Art, Audio, Lighting, Vision and World-Gen depend on nothing outward but General (and World-Gen on the Objects factories). Audio imports only `EventBus`; Lighting reads the world duck-typed (`get_lights()`, the groups `floors` and `characters`), Vision the viewer's `sight()`.
- **Duck-typed, no class reference:** Items, Projectile, Physics and Explosion strike Objects, Character and Vehicles through interface 3; Camera reads a vehicle through `use.vehicle()` and its state, `Sound` off the `vehicle` key of the `engine` / `skid` events (interface 10); a fading overhang (Objects) reads a `characters` member's `is_dead` and `use.is_riding()` and a vehicle's `seats()`; UI reads Character and AI by exported path and signals (the spectator's detail card reads the NPC overlays' `card_lines()`).
- **World's chance and order:** `WorldRng` (General, 11) is the leaf every domain that draws chance in a fight (Projectile, Physics' debris, Character, Items' gun) or orders by who spawned first (the AI) reads; `MatchBuilder.stage` registers a world with it, and `Character._enter_tree` enrols a character. No domain takes an instance id as an order.
- **Events:** `EventBus` carries hits, shots, callouts, orders, explosions, grenades, footfalls, stuns, deaths and vehicle events between domains that do not reference each other. Topics and payloads: interface 10.
- **Inside the AI** (the stack seam, doorway views, what team reads of perception, the decision job's seam: it steps perception's staged build, `begin_sense`, and the planner, and holds no owner): `domain-ai` (`team.md`, `perception.md`, `decision.md`).
- A new edge, façade, contract method or signal goes into this graph or the interfaces (`audit` checks it).
