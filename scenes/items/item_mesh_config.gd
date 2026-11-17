class_name ItemMeshConfig
## Items domain, the 3D meshes of the items (`items/art/gun_mesh.gd`, `grenade_mesh.gd`,
## `spoon_art.gd`; `domain-art/meshes.md`): how tall an item stands over its 2D art. The
## footprint is the art's own (the silhouette of the painter's flat render, `ItemSolid`), as are the
## sizes (`GunConfig` / `GrenadeConfig` `art_size`, `flat_size`, `grip_back`) and colours; only what
## a solid needs more than a drawing is here. A `class_name` holder of `static var`s, read as
## `ItemMeshConfig.<name>` (ADR 0003).

## How much taller than the 2D art's own heights (`WeaponArt.HELD_PARTS`, the ones its shadows are
## cast by) a gun is, and how much thicker than its width one lying on its side is.
static var thickness: float = 1.3
## Where a held gun's underside is (px, from the weapon hand's height): below the hand, so the gun
## is about the hand's height.
static var held_base: float = -2.5
## How much brighter a loose item's art is tinted (a multiplier on its colours, 1 = as painted). The
## gun and grenade art is gunmetal and the near top-down camera lights a lying item in the base
## band like the floor: 1 left a lying gun near-black on a dark floor, 2 made it silver; 1.4 keeps
## it gunmetal and visible.
static var lying_brighten: float = 1.4
## How tall a gun lying on its side is along its profile, as a share of the gun's width: its stock,
## its hand guard and its barrel (the receiver is the whole width).
static var lying_stock: float = 0.8
static var lying_guard: float = 0.7
static var lying_barrel: float = 0.45
## Flat faces round a grenade's body: a vertex up and one to each side, so its width is the art's.
static var grenade_sides: int = 12
## How far ahead of the hand (px) a grenade sits: its row's art is drawn this far along the aim
## from the weapon hand (as the 2D art drew it).
static var grenade_ahead: float = 2.0
## A grenade's lever held down: how far (px) it stands off the body's top.
static var lever_height: float = 1.0
## A grenade's spoon lying loose: how thick the strip is (px).
static var spoon_height: float = 0.8
