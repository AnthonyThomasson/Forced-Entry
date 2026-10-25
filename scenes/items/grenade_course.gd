class_name GrenadeCourse extends RefCounted
## The way a thrown grenade's lob is planned over (`ThrownGrenade`'s fit to the floor): from where
## it leaves the hand toward the aim, along which direction, over which world, swept with which
## query, passing which bodies just after the release. `ThrownGrenade.spawn` fills one per throw.

## Where it leaves the hand, world px.
var from: Vector2 = Vector2.ZERO
## Where it is aimed, world px.
var to: Vector2 = Vector2.ZERO
## Which way it heads across the floor (unit).
var direction: Vector2 = Vector2.RIGHT
## The world it flies over: the walls, furniture and bodies the node itself strikes.
var space: PhysicsDirectSpaceState2D = null
## The sweep it is moved with (`ThrownGrenade._sweep_query`).
var query: PhysicsShapeQueryParameters2D = null
## The bodies passed for the first `ThrownGrenade.THROWER_CLEAR` px (the thrower's).
var passed: Array[RID] = []
