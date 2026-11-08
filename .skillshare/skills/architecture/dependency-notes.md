# Architecture: notes on the dependency graph

Side file of `architecture` (`SKILL.md`).

- **Leaves:** Physics, Navigation, Art, Audio, Lighting, Vision and World-Gen depend on nothing outward but General (and World-Gen on the Objects factories). Audio imports only `EventBus`; Lighting reads the world duck-typed (`get_lights()`, the groups `floors` and `characters`), Vision the viewer's `sight()`.
- **Duck-typed, no class reference:** Items, Projectile, Physics and Explosion strike Objects, Character and Vehicles through interface 3; Camera reads a vehicle through `use.vehicle()` and its state, `Sound` off the `vehicle` key of the `engine` / `skid` events (interface 10); a fading overhang (Objects) reads a `characters` member's `is_dead` and `use.is_riding()` and a vehicle's `seats()`; UI reads Character and AI by exported path and signals (the spectator's detail card reads the NPC overlays' `card_lines()`).
- **Events:** `EventBus` carries hits, shots, callouts, orders, explosions, grenades, footfalls, stuns, deaths and vehicle events between domains that do not reference each other. Topics and payloads: interface 10.
- **Inside the AI** (the stack seam, doorway views, what team reads of perception): `domain-ai` (`team.md`, `perception.md`).
- A new edge, façade, contract method or signal goes into this graph or the interfaces (`audit` checks it).
