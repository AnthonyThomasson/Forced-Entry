class_name CoverRule extends RefCounted
## What stops a grenade burst's line to a body for `Explosion.shields` (G7, `docs/grenades.md`): the
## posture the body is in (its head, chest and hips at that posture's heights, `BodyHeights`) and,
## for a stun's flash, how near the body must be to a piece for it to count. Whoever asks (the AI's
## perception) fills it.

## The posture the body is in (`BodyHeights.STAND`, `DUCK`, `FIRE_OVER`): the heights the line is
## drawn to.
var posture: StringName = BodyHeights.STAND
## With a finite reach (a stun's flash, G11) the line is the eye's alone and a piece only stops it
## when the body is within that many px of it, on the burst's side; INF = any distance, every point
## of the body (a frag's blast).
var cover_reach: float = INF
