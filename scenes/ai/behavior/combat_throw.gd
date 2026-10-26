extends RefCounted
## AI BEHAVIOUR sub-domain — COMBAT's throw, its part `throw`: throwing a grenade
## (`docs/grenades.md` G17: walk to the throw spot, take it in hand, aim at the spot, throw, put the
## gun back). Built once with its `Combat` (`setup`), it holds the throw in hand and, handed in by
## Combat's `setup` and `bind`, the locomotion it walks with and the body whose hand throws; it
## holds no Combat. The GRENADE tactic's `throw` primitive and the bang entry's thrower drive it
## (`begin`, `step`, `released`, `end`).

## Seconds a throw may take to start (the grenade in hand, the facing settled, the hand free) before
## it is given up, and to leave the hand once started.
const START_CAP := 2.0
const RELEASE_CAP := 1.5
## How close (px) a thrower walks to its throw spot before it takes the grenade in hand: all the way
## in, since the lob was judged from there and from no farther off than this
## (`AgentThrow.ARRIVAL_SLACK`; a stride short, a jamb can be in the way of it).
const SPOT_REACH := 6.0
## Facing error (radians) within which the grenade is let go — aim settles a frame after it is set;
## a shot's is the same (`Combat.AIM_TOLERANCE`).
const AIM_TOLERANCE := 0.15

## The throw in hand (`begin`): "" none, "walk" on the way to the throw spot (the gun still in
## hand), "aim" taking the grenade and turning to the spot, "windup" the hand drawn back, "away" it
## has left the hand (or never will).
var stage := ""
## The inventory slot of the grenade being thrown.
var slot := -1
## Where it is thrown to.
var spot := Vector2.ZERO
## Where it is thrown from (the throw spot; where the thrower stood when it was offered, for a throw
## in place).
var from := Vector2.ZERO
## How far (px) from the spot the thrower stands to let it go.
var reach := 0.0
## How many of that grenade were carried when the throw started.
var before := 0
## Seconds in the current stage of the throw.
var clock := 0.0
## The Locomotion child (pathing), handed in by `Combat.setup`.
var _loco: Node
## The NPC's body, handed in by `Combat.bind`: whose hand throws.
var _character: Node


## Capture the locomotion. Called once by `Combat.setup()`.
func setup(loco: Node) -> void:
	_loco = loco


## Hand in the NPC's body. Called once by `Combat.bind()`.
func bind(character: Node) -> void:
	_character = character


## Start a throw of the grenade in `grenade_slot` at world point `to`, let go no farther than
## `let_go` px from it (`AgentPerception.grenade_reach`). With a throw spot `throw_from`
## (`Vector2.INF`: none) the thrower walks there first (`stage` "walk"), then throws from it.
func begin(grenade_slot: int, to: Vector2, let_go: float, throw_from := Vector2.INF) -> void:
	stage = "aim" if throw_from == Vector2.INF else "walk"
	slot = grenade_slot
	spot = to
	from = throw_from
	reach = let_go
	clock = 0.0


## Forget a throw (a new order replaced it).
func end() -> void:
	stage = ""


## Carry the throw out one tick. With a throw spot, first walk all the way to it (`SPOT_REACH`) with
## the gun in hand: the caller's watch keeps its eyes on a threat meanwhile, and its commit timer
## and the locomotion's held walk bound the walk. Then, standing still: take the grenade in hand,
## aim at the spot and, once the facing has settled, click the trigger
## (`Character.weapon.shoot()`: the wind-up starts, the grenade leaves the hand `windup` seconds
## later). A thrower that stands farther than its reach from the spot (it moved on since the spot
## was offered) walks the last few px toward the spot first, within the same `START_CAP`. Returns
## `&"failed"` when it never could (none left, the hand busy, the wind-up cut short), else `&""`.
func step(delta: float) -> StringName:
	clock += delta
	_character.movement.move_input = Vector2.ZERO
	match stage:
		"walk":
			if _character.inventory.item_count(slot) <= 0:
				stage = "away"
				return &"failed"
			if not _loco.reached(from, SPOT_REACH):
				_loco.move_to(from, SPOT_REACH)
				return &""
			stage = "aim"
			clock = 0.0
		"aim":
			if _character.inventory.item_count(slot) <= 0 or clock > START_CAP:
				stage = "away"
				return &"failed"
			_character.inventory.select_slot(slot)
			_character.movement.aim_point = spot
			if _character.global_position.distance_to(spot) > reach:
				_loco.move_to(spot)
				return &""
			if _character.inventory.current_slot() == slot and _faces(spot):
				before = _character.inventory.item_count(slot)
				if _character.weapon.shoot():
					stage = "windup"
					clock = 0.0
		"windup":
			_character.movement.aim_point = spot
			if clock > RELEASE_CAP:
				stage = "away"
				return &"failed"  # The wind-up was cut short (it died, or put the grenade away).
	return &""


## Whether the grenade being thrown has left the hand since the last call (true once): the end of
## the wind-up. The gun is taken back in hand then (a last grenade empties its slot by itself).
func released() -> bool:
	if stage != "windup" or _character.inventory.item_count(slot) >= before:
		return false
	stage = "away"
	_character.inventory.select_slot(_character.inventory.gun_slot())
	return true


## Whether the facing has settled on world point `pos` (within `AIM_TOLERANCE`).
func _faces(pos: Vector2) -> bool:
	return absf(_character.facing.angle_to(pos - _character.global_position)) <= AIM_TOLERANCE
