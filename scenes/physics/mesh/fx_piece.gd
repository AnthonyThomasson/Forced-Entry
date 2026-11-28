class_name FxPiece
extends RefCounted
## Physics domain, one short-lived thing of the 3D effects (a chip, a bit of a burst): its state
## and its place in a batch. A batch makes every piece it will ever hold when it is built and lends
## them out (`FxBatch.take`), so nothing is allocated while the game runs.

## The batch the piece is in while it is shown, and its colour (the art's sRGB colour).
var batch: FxBatch
var color := Color.WHITE
## Where it is in the 2D world (px) and how it is turned (a 2D angle), and how high over the ground
## (px).
var at := Vector2.ZERO
var turn := 0.0
var height := 0.0
## How big (px) it is.
var size := Vector2.ONE
## Its age and its whole life (s).
var age := 0.0
var life := 1.0
## Where it leaves from: the 2D node it follows (an instance id) or its velocity (px/s, a bit's)
## and how fast it rises (px/s).
var node_id := 0
var velocity := Vector2.ZERO
var rise := 0.0
## How fast a bit's horizontal speed falls (px/s²).
var damping := 0.0
