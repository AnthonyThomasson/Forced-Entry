class_name GrenadeCourse
extends RefCounted
## What a throw is planned over (`GrenadeArc.plan`): where a grenade of a kind leaves the hand and
## how high, where it is aimed, which world it flies in, which bodies it passes just after the
## release and how much room to spare the arc is judged with. `ThrownGrenade.spawn` fills one per
## throw; the AI fills one for each throw it judges (`AgentThrow`), so both ask the one planner.

## Where it leaves the hand (plan point, world px) and how high (px, `BodyHeights.release`).
var from: Vector2 = Vector2.ZERO
var release: float = 0.0
## Where it is aimed (plan point, world px).
var to: Vector2 = Vector2.ZERO
## The `GrenadeConfig` row of the kind thrown: its speed, restitution, friction and range.
var row: Dictionary = {}
## The twin space the arc is flown in (`TwinSpace.space_of`); none flies over a bare floor.
var space: PhysicsDirectSpaceState3D = null
## The bodies passed for the first `GrenadeArc.THROWER_CLEAR` px (the thrower's twin).
var passed: Array[RID] = []
## What the arc strikes (`PhysicsLayers` 3D): everything by default; the AI leaves the characters
## out (they stop nothing a throw is judged by).
var mask: int = PhysicsLayers.TWIN_ALL
## Extra room (px) the arc must clear to either side of its path (the AI's, for a thrower that
## stops a step off its spot, `AgentThrow.LOB_MARGIN`); 0 is the grenade's own width.
var margin: float = 0.0
## The apex (px, the centre's height) the thrower chose, or -1 to let the planner pick the lowest
## arc that clears.
var apex: float = -1.0
## Whether to fly each clear arc over the floor to rest (`GrenadeArc.rest_of`) and keep the one that
## rests nearest the aim, as a throw is made; false is the cheaper question, whether an arc clears.
var verify: bool = false
## The highest the centre of the arc may peak (px), worked out by the planner (`GrenadeArc._top`);
## -1 until then.
var top: float = -1.0
## The underside of the roof over the hand or the aim, the lower (px; `INF`: none): worked out with
## `top`.
var roof: float = INF
## The arcs the planner made for this plan, by the apex asked for (`GrenadeArc._arc`): kept for the
## one `plan` and cleared at the next, so the planner works each out and sweeps each lob once.
var made: Dictionary = {}
