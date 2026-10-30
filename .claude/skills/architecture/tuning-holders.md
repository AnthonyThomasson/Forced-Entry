# Tuning holders, by domain

The catalogue `SKILL.md` points to from the dependency graph's tuning note.

`grep -r "class_name Character.*Config" scenes` lists the Character ones, and each domain skill says what each holds.
**Projectile:** `BallisticsFlightConfig` (speeds, a bullet's height and the fly-over, a surfaceless collider),
`BallisticsPenetrationConfig` (going through, the blood a round carries out), `BallisticsRicochetConfig`.
**Physics:** `PhysicsConfig` (the wall mask, the debris and hit-particle switches and particle caps),
`PhysicsImpactConfig` (a hit's shove, furniture bodies' damping), `PhysicsDeformConfig` (dents, chunks, the collider
rebuild: interface 4's defaults), `PhysicsDeformLookConfig` (cracks, holes, scorch, darkening, the blood mark),
`PhysicsRagdollConfig` (the solver), `PhysicsExplosionConfig` (the burst's look); and blood's `BloodConfig` (the master
switch, the colours, the draw layers, the decal cap and drying), `BloodDripConfig`, `BloodSprayConfig`,
`BloodSplatConfig`, `BloodPoolConfig`, `BloodSurfaceConfig`, `BloodPrintConfig`, `BloodSmearConfig`,
`BloodSmearLookConfig` and `BloodTrailConfig`.
**Character:** `CharacterPostureConfig`, `CharacterPaceConfig` (running, stamina, the outfit's weight),
`CharacterPushConfig`, `CharacterMeleeConfig` (punch and kick), `CharacterStunConfig`, `CharacterHitConfig` (flesh, hit
zones, sides), `CharacterShadowConfig`, `CharacterArtConfig`, `CharacterStyleConfig` (the styles), `CharacterBodyConfig`
(the skeleton), `CharacterStrideConfig`, `CharacterStanceConfig` (stances, the muzzle, the raise, recoil),
`CharacterPoseTurnConfig`, `CharacterPoseHandConfig`, `CharacterPoseHeadConfig`, `CharacterRagdollConfig`,
`CharacterRagdollJointConfig` and `CharacterRagdollFallConfig`.
**Art:** `ArtCanvasConfig` (the art pixel, the light, turn steps, shadows) and `ArtSurfaceConfig` (tones, finishes).
**Objects** (its painters, floors, walls and the run-down look): `ObjectArtTableConfig`, `ObjectArtFabricConfig`,
`ObjectArtStorageConfig`, `ObjectArtKitchenBathConfig`, `ObjectArtDecorConfig`, `ObjectArtOutdoorConfig`,
`ObjectArtClinicConfig`, `ObjectArtTechConfig`, `ObjectArtLightConfig` (light specs, neon), `ObjectArtLayerConfig` (its
z rungs), `ObjectArtFloorConfig`, `ObjectArtWallConfig`, `ObjectArtDecayConfig`, `ObjectArtWearConfig` and
`ObjectArtStreetConfig`.
**World-Gen:** `WorldGenFillConfig`, `WorldGenDressConfig` (the run-down dressing's placement) and
`WorldGenStreetConfig` (the street ring and its street lamps).
**Items:** `MagazineConfig` (magazine types, capacities and reload times), `GunConfig` (one row per gun — damage, fire rate,
penetration, muzzle speed, spread, recoil, magazine, whether it raises at a wall, its sizes and hold, its looks per weapon style),
`GrenadeConfig` (one row per grenade kind — fuse, windup, range, flight, the blast or flash and bang numbers, its art size, its looks per
weapon style, and a thrown grenade's size, spin and shadow), `DroppedItemConfig` (a dropped item's fall, bounce, skid and shadow),
`OutfitConfig`
(the garment and plate rows — slot, name, weight, looks per character style, the armour's zones, sides and protection numbers, a
plate's durability) and `LoadoutConfig` (the setup choices' bounds — spare magazines, grenades — and the default outfit).
**Audio:** `SoundConfig` (the master switch, levels, jitter, voices, ranges), `SoundLibraryConfig` (rate, peak, variants,
weight bands, seed, prewarm), `SoundDeafnessConfig` and `SoundVehicleConfig`.
**Vehicles:** `VehicleConfig` (one `kinds` and one `looks` row per kind), `VehicleBoardingConfig`,
`VehicleDoorConfig`, `VehicleDriveConfig` (with the camera's zoom-out), `VehicleCollisionConfig` and `VehicleArtConfig`.
**Lighting:** `LightingConfig` (the master switch, the dusk, the flashes and the per-floor budget),
`LightingFixtureConfig` and `LightingTextureConfig`.
**AI:** `SquadFollowConfig` (the squads' follow spacing and leash, `docs/leadership.md` LD21 to LD23).
**General:** `CameraConfig` (the camera's follow, framing, zoom and hand pan) and `CameraShakeConfig` (its explosion shake).
A new tunable goes in the holder of its topic; one that fits no topic starts a holder of its own, never a kept family
holder unless it is a family-wide switch or a per-kind row (ADR 0003). World-Gen's `LayoutRules` (which rooms may
