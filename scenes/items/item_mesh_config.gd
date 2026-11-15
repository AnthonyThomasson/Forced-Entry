class_name ItemMeshConfig
## Items domain, the 3D meshes of the held items (`items/art/gun_mesh.gd`, `grenade_mesh.gd`; #193
## phase 2, `domain-art/meshes.md`): how chunky a held item is drawn against its config row's art.
## A `class_name` holder of `static var`s, read as `ItemMeshConfig.<name>` (ADR 0003). The sizes
## themselves are the rows' (`GunConfig` / `GrenadeConfig` `art_size`, `grip_back`), the colours the
## look's; only what a low-poly solid needs more than a 2D drawing is here.

## How much deeper and taller than the 2D art's width a gun or grenade is, the 2D art being a
## top-down drawing a speck at the pixel post's resolution: so a pistol still reads in a hand.
static var thickness: float = 1.3
## Flat faces round a barrel and a grenade's body.
static var sides: int = 6
## How far ahead of the hand (px) a grenade sits: its row's art is drawn this far along the aim
## from the weapon hand (`GrenadeArt.draw_weapon`).
static var grenade_ahead: float = 2.0
## A grenade's lever: how far it stands off the body (share of the body's width), and its width
## (share).
static var lever_lift: float = 0.14
static var lever_width: float = 0.22
## A grenade's spoon lying loose: how thick the strip is (px).
static var spoon_height: float = 0.8
