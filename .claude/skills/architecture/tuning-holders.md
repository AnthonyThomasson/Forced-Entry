# Tuning holders

Tuning is `class_name` static holders, one per topic, ≤ 15 vars each (ADR 0003; `docs/adr/0003-config-holders-split-by-topic.md`). A holder shares its domain's stem: `grep -rn "class_name Character.*Config" scenes` lists the Character ones; each `domain-<name>` skill says what its holders hold. There is no `Config` autoload.

A new tunable goes in the holder of its topic. One that fits no topic starts a holder of its own; a kept family holder takes it only when it is a family-wide switch or a per-kind row.

| Domain | Holders |
|---|---|
| Projectile | `Ballistics{Flight,Penetration,Ricochet}Config` |
| Physics | `Physics{,Impact,Deform,DeformLook,Ragdoll,Explosion}Config`; blood: `BloodConfig` (master switch, colours, draw layers, decal cap) and `Blood{Drip,Spray,Splat,Pool,Surface,Print,Smear,SmearLook,Trail}Config` |
| Character | `Character*Config` (Posture, Pace, Push, Melee, Stun, Hit, Shadow, Art, Style, Body, Stride, Stance, PoseTurn, PoseHand, PoseHead, Ragdoll, RagdollJoint, RagdollFall) |
| Art | `ArtCanvasConfig`, `ArtSurfaceConfig` |
| Objects | `ObjectArt*Config` (Table, Fabric, Storage, KitchenBath, Decor, Outdoor, Clinic, Tech, Light, Layer, Floor, Wall, Decay, Wear, Street) |
| World-Gen | `WorldGen{Fill,Dress,Street}Config` |
| Items | `GunConfig` and `GrenadeConfig` (one row per gun / grenade kind), `MagazineConfig`, `DroppedItemConfig`, `OutfitConfig` (garment and plate rows), `LoadoutConfig` (setup bounds, default outfit) |
| Audio | `Sound{,Library,Deafness,Vehicle}Config` |
| Vehicles | `VehicleConfig` (a `kinds` and a `looks` row per kind), `Vehicle{Boarding,Door,Drive,Collision,Art}Config` |
| Lighting | `Lighting{,Fixture,Texture}Config` |
| AI | `SquadFollowConfig`, `SquadAmbushConfig` (squad tuning, not per NPC); an NPC's own tunables are the `Npc<Topic>Tuning` nodes (`typed-components.md`) |
| General | `Camera{,Shake}Config` |

World-Gen's `LayoutRules` (which rooms may hold the front door or an exit, which room types may share a door) is a rules table in the same style, not tuning. `PhysicsLayers`, `DrawLayers` and `LightMasks` are shared ids, not tuning (interface 11).
