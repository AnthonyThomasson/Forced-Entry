class_name BloodThrow extends RefCounted
## One splatter's throw, as `BloodSpawner.splat` reads it: how big its core is, which way and how
## hard the blood flew, and the bleeding body its wall clipping ignores. The bleeder (`BloodWound`)
## fills the fields it needs.

## The core radius, px.
var size: float = 0.0
## The way the blood was thrown.
var direction: Vector2 = Vector2.RIGHT
## How hard, 0..1: forward spikes grow longer with it.
var energy: float = 0.0
## The bleeding body's RID(s), ignored by the splat's wall clipping.
var exclude: Array = []
