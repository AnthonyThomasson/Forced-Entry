extends RefCounted
## AI DECISION sub-domain: what keeps a walk's `confine` subtrees (combat) in bounds, a data leaf
## the planner builds once and holds as `confines`; the controller pushes it each decision. Inside
## such a subtree an option outside the house (a territorial NPC), outside the room a member was
## ordered to defend, or beyond a follower's leash is dropped.

## Territory: inside a `confine` subtree (combat), drop options outside the house.
var inside_only: bool = false
## The room a member ordered to defend it keeps to (`docs/leadership.md` LD8; "" = none): inside a
## `confine` subtree, drop options whose `tags.room` is another room or outside, as `inside_only`
## drops those outside the house. Pushed each decision from the live order.
var confine_room: String = ""
## The point a squad member following its leader keeps to (the leader's position, `Vector2.INF` =
## none) and how far from it (px): inside a `confine` subtree, drop options placed farther than
## `leash` from it, as `confine_room` drops those outside its room. Pushed each decision from the
## squad.
var leash_center: Vector2 = Vector2.INF
## The leash (px) round `leash_center` (0 with no leash).
var leash: float = 0.0
