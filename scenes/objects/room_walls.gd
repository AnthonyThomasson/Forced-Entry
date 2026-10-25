class_name RoomWalls extends RefCounted
## A room's walls as `WallFactory.spawn` builds them round its outline: how thick they are, the
## doorways cut through them and the cap's look. World-Gen and the Testing domain's layouts fill it;
## a wall with no doorways and no style leaves those alone.

## The walls' thickness, px (they run along the outline's centre line).
var thickness: float = 0.0
## The doorways, in `Wall.Side` format (`WallFactory.openings_for` makes them from
## `{ pos, width }`).
var openings: Array = []
## The cap's look: `art` (a tiling painter id), `color`, `art_opts`; empty = a flat gray line.
var style: Dictionary = {}
