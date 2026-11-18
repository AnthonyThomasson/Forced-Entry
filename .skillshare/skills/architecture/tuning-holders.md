# Tuning holders

Tuning is `class_name` static holders, one per topic, ≤ 15 vars each (ADR 0003; `docs/adr/0003-config-holders-split-by-topic.md`). A holder shares its domain's stem: `grep -rn "class_name Character.*Config" scenes` lists the Character ones; each `domain-<name>` skill says what its holders hold. There is no `Config` autoload.

A new tunable goes in the holder of its topic. One that fits no topic starts a holder of its own; a kept family holder takes it only when it is a family-wide switch or a per-kind row.

| Domain | Holders |
|---|---|
| Projectile | `Ballistics{Flight,Penetration,Ricochet}Config` |
| Physics | `Physics{,Impact,Deform,DeformLook,Ragdoll,Explosion}Config`; blood: `BloodConfig` (master switch, colours, draw layers, decal cap) and `Blood{Drip,Spray,Splat,Pool,Surface,Print,Smear,SmearLook,Trail}Config` |
| Character | `Character*Config` (Posture, Rise, Pace, Push, Door, Melee, Stun, Hit, Shadow, Art, Style, Body, Stride, Stance, PoseTurn, PoseHand, PoseHead, Ragdoll, RagdollJoint, RagdollFall, Vision) |
| Art | `ArtCanvasConfig`, `ArtSurfaceConfig`; the 3D mirror: `MirrorConfig` (a proxy's heights and colours) |
| Objects | `ObjectArt*Config` (Table, Fabric, Storage, KitchenBath, Decor, Outdoor, Clinic, Tech, Light, Floor, Wall, Decay, Wear, Street, Door, and the district's Shop, Awning, Stencil, StreetProp, Podium, ShellDecor, Crossing, RoadGlyph); the doors': `DoorConfig`, `DoorPushConfig`, `DoorMaterialConfig` (a row per door material) |
| World-Gen | `WorldGen{Fill,Dress,Street,Door,District,Tower,Shell}Config` (the district's grid, streets and clutter; a tower's podium, shadow and body; a shell's decor) |
| Items | `GunConfig` and `GrenadeConfig` (one row per gun / grenade kind), `MagazineConfig`, `DroppedItemConfig`, `OutfitConfig` (garment and plate rows), `LoadoutConfig` (setup bounds, default outfit) |
| Audio | `Sound{,Library,Deafness,Vehicle}Config` |
| Vehicles | `VehicleConfig` (a `kinds` and a `looks` row per kind), `Vehicle{Boarding,Door,Drive,Collision,Art}Config` |
| Lighting | `Lighting{,Fixture,Texture,3D,Cost}Config` |
| AI | `SquadFollowConfig`, `SquadAmbushConfig` (squad tuning, not per NPC); an NPC's own tunables are the `Npc<Topic>Tuning` nodes (`typed-components.md`) |
| Navigation | `NavBakeConfig` (the physics frame a planning re-bake lands on) |
| General | `Camera{,Shake}Config`; the 3D render: `RenderConfig` (the one 2D-to-3D scale, the camera's pitch, yaw, distance and clip, the internal height, the view's canvas layer) and `RenderLightConfig` (the 3D view's backdrop) |
| Vision | `VisionConfig` (the switch, the look, the memory's scale, the cone's rays, the rebuild backstop), `VisionSliceConfig` (a sliced cone rebuild: unit prices, slice size, restart cap) |

World-Gen's `LayoutRules` (which rooms may hold the front door or an exit, which room types may share a door) and `DoorRules` (which doorways get a door) are rules tables in the same style, not tuning. `PhysicsLayers` and `ViewLayers` are shared ids, not tuning (interface 11).
