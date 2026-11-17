class_name FadeHang
extends RefCounted
## Art domain, the wall links of one fade unit (`fade_unit.gd`, `fade_book.gd`): a wall segment's
## unit is a `wall` and holds the pieces hung on it (`followers`); a piece that hangs on a wall (a
## stain, a menu board) is `hung`, is in no grid cell and holds the wall units it hangs on
## (`hosts`): it is in the way exactly when one of them is.

## Whether the unit is a wall segment's, and whether it is a hung piece's.
var wall := false
var hung := false
## The wall units a hung piece hangs on, and the hung pieces a wall unit holds.
var hosts: Array[FadeUnit] = []
var followers: Array[FadeUnit] = []
