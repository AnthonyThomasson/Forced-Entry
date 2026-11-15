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
## character's waist) and the flash, the ring and the fireball glow `glow`; the shock ring stands
## `ring_lift` px up, is as tall as `ring_height`, reaches `ring_reach` times the fireball's radius
## and glows `ring_color`. Every height counts from the ground under the burst (a road lies a kerb
## lower: `FxWorld`).
static var flash_height: float = 6.0
static var glow: float = 1.0
static var ring_lift: float = 4.0
static var ring_height: float = 2.0
static var ring_reach: float = 1.3
static var ring_color: Color = Color(1.0, 0.95, 0.75)
## The fireball is a dome, not a ball, so it hides little: its middle stands `fire_height` of its
## swell over the ground and it is `fire_squash` as tall as it is wide; its body is `fire_body` of
## the swell (the lumps round it follow) and at most `fire_opacity` whole (it dithers from the
## start); it cools in `fire_steps` steps from its core's colour to its edge's.
static var fire_height: float = 0.25
static var fire_squash: float = 0.55
static var fire_body: float = 0.6
static var fire_opacity: float = 0.67
static var fire_steps: int = 3
## A puff of smoke starts on the ground, `smoke_squash` as tall as it is wide, and rises
## `smoke_rise` px over its life.
static var smoke_rise: float = 40.0
static var smoke_squash: float = 0.8
## The fade is this many steps from whole to gone.
static var fade_levels: int = 6
