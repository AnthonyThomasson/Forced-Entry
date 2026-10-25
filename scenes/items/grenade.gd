class_name GrenadeItem extends Item
## Items domain: a throwable held in the right hand: the logic the stun and the frag grenade share,
## driven by its row in `GrenadeConfig` (docs/grenades.md G1 to G6). It is a *count* carried in its
## slot (`uses_left()`), spent one per throw: left-click (`secondary`) starts a throw, the arm is
## drawn back in the `throw` stance for `windup` seconds (counted in `tick`), and then the grenade
## leaves the hand as a `ThrownGrenade` flying to the character's `weapon.aim_target()`. The fuse
## starts on release; there is no cooking. A character that dies, or puts the grenade away, during
## the wind-up throws nothing. When the last one is thrown the character empties the slot
## (`Character`). It is drawn by its `art` part (`GrenadeArt`), in its weapon style by the row's
## look at the row's `art_size`, and a thrown one keeps it. A subclass (`StunGrenadeItem`,
## `FragGrenadeItem`) only names its row (`super(KIND)`).

## The kind's id: its `GrenadeConfig` row. Named by the subclass (`super(KIND)`).
var kind: StringName = &""
## Grenades left in this slot.
var count := 1
## Seconds until the grenade leaves the hand; negative = no throw under way.
var _windup_left := -1.0
## Who is winding up.
var _user: Node


func _init(id: StringName) -> void:
	kind = id
	super(null, null, GrenadeArt.new(id, weapon_hand()))
	display_name = str(_stat("name", display_name))
	reach = 28.0


# --- Stats (read live from GrenadeConfig, so tuning it takes effect at once) --------------------


## A value from this kind's `GrenadeConfig` row (`fallback` when the row has none).
func _stat(key: String, fallback: Variant = null) -> Variant:
	return GrenadeConfig.row(kind).get(key, fallback)


# --- Item contract --------------------------------------------------------------------------


## The grenades left in this slot (`Item.uses_left`; -1 is unlimited, for every other item).
func uses_left() -> int:
	return count


## A grenade is thrown (`Item.is_throwable`).
func is_throwable() -> bool:
	return true


## What a holder may know of this grenade before it is thrown:
## `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`
## (`GrenadeConfig.stats_of`).
func throw_stats() -> Dictionary:
	return GrenadeConfig.stats_of(kind, GrenadeConfig.row(kind))


## The weapon hand cocks back in the `throw` stance for the wind-up and otherwise holds the grenade
## at the chest; the other hand hangs.
func hand_stance(hand: int) -> StringName:
	if hand != weapon_hand():
		return &"relaxed"
	return &"throw" if is_winding_up() else &"guard"


## True from the click to the moment the grenade leaves the hand.
func is_winding_up() -> bool:
	return _windup_left >= 0.0


## LMB: start a throw. Nothing with none left or while one is already under way. True when a throw
## began.
func secondary(user: Node2D) -> bool:
	if count <= 0 or is_winding_up():
		return false
	_user = user
	_windup_left = float(_stat("windup", 0.3))
	return true


## Count the wind-up down and let the grenade go at the end of it. The throw is dropped if the
## thrower died or no longer holds this grenade (a dead character is not ticked, so this is the
## switch-away case).
func tick(delta: float) -> void:
	if not is_winding_up():
		return
	if not is_instance_valid(_user) or _user.is_dead or _user.inventory.current_item() != self:
		_windup_left = -1.0
		return
	_windup_left -= delta
	if _windup_left <= 0.0:
		_release()


## The grenade leaves the hand toward the aim, in this one's weapon style: one is spent, the throw
## is announced (the Audio domain voices it) and the spoon pops off.
func _release() -> void:
	var user := _user
	_windup_left = -1.0
	_user = null
	var from: Vector2 = user.anatomy.hands.world(weapon_hand())
	var world: Node = user.world_root()
	count -= 1
	var throw := GrenadeThrow.new()
	throw.kind = kind
	throw.from = from
	throw.to = user.weapon.aim_target()
	throw.thrower = user
	throw.style = art.style
	ThrownGrenade.spawn(throw, world)
	GrenadeSpoon.pop(from, (user.weapon.aim_target() - from).angle(), world)
	EventBus.post(&"throw", { "position": from, "kind": kind, "attacker": user })
