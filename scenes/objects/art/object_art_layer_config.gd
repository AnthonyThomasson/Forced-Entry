class_name ObjectArtLayerConfig
## Objects' rungs on the draw-order ladder (interface 11, General's DrawLayers): the floor's, the
## rug's and an overhang's z index. A `class_name` holder of `static var`s, read as
## `ObjectArtLayerConfig.<name>`; there is no instance and no autoload.

## Floors draw beneath everything else in the house (blood pools, casings, rugs):
## `DrawLayers.FLOOR`.
static var floor_z_index: int = DrawLayers.FLOOR
## Rugs and mats lie on the floor but under blood (`BloodConfig.z_index`), so a pool shows on them:
## `DrawLayers.RUG`.
static var rug_z_index: int = DrawLayers.RUG
## A piece's overhang (a streetlight's arm and head) hangs over everyone under it and a vehicle's
## roof: `DrawLayers.OVERHEAD`.
static var overhang_z_index: int = DrawLayers.OVERHEAD
