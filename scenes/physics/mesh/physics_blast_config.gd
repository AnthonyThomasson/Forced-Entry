class_name PhysicsBlastMeshConfig
## Physics domain, the 3D look of a grenade's burst (#193 phase 2; `blast_fx.gd`,
## `blast_rig.gd`, `domain-physics/meshes.md`): what the 3D adds to the 2D look
## (`PhysicsExplosionConfig.looks`, whose radii, times, puffs, colours and scorch it reads again):
## how high things stand and how the rig is pooled. A `class_name` holder of `static var`s, read as
## `PhysicsBlastMeshConfig.<name>` (ADR 0003). Lengths and heights are 2D px. The effect is a few
## solid shapes in stepped tones, no blending: the fireball cools in thirds, the smoke and the fade
## of the rest thin out by a dither of the picture's own pixels (`MeshNodes.fade`), in
## `fade_levels` steps. A burst's light is phase 3's flash light, not this.

## How many bursts show at once: each is a rig of parts made with the layer, and a burst past
## them takes the oldest one's.
static var rigs: int = 6
## The flash's disc stands this high (px, over the pavement and the floor's wear, under a
## character's waist) and glows (`flash_glow`); the shock ring stands `ring_lift` px up, is as
## tall as `ring_height`, reaches `ring_reach` times the fireball's radius and glows `ring_color`.
static var flash_height: float = 6.0
static var flash_glow: float = 1.0
static var ring_lift: float = 4.0
static var ring_height: float = 2.0
static var ring_reach: float = 1.3
static var ring_color: Color = Color(1.0, 0.95, 0.75)
## The fireball's middle stands at this share of its radius over the ground, and glows
## `fire_glow`; it cools in `fire_steps` steps from its core's colour to its edge's.
static var fire_height: float = 0.45
static var fire_glow: float = 1.0
static var fire_steps: int = 3
## A puff of smoke starts `smoke_base` px up and rises `smoke_rise` px over its life.
static var smoke_base: float = 8.0
static var smoke_rise: float = 40.0
## The fade is this many steps from whole to gone.
static var fade_levels: int = 6
