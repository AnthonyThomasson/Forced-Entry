class_name CoverRule extends RefCounted
## What stops a grenade burst's line to a body for `Explosion.shields` (G7, `docs/grenades.md`): the
## body's height (a piece of furniture whose `coverage` is above it stops the line, the lower ones
## are cleared), the rids the line passes through and, for a stun's flash, how near the body must
## be to a piece for it to count. Whoever asks (the AI's perception) fills it.

## The body's height on the 0..100 coverage scale.
var height: float = 0.0
## The rids the line passes through (the characters').
var exclude: Array = []
## With a finite reach (a stun's flash, G11) a piece only stops the line when the body is within
## that many px of it, on the burst's side; INF = any distance (a frag's blast).
var cover_reach: float = INF
