extends RefCounted
## AI BEHAVIOUR sub-domain — COMBAT. Everything a fight does with the character's hands: taking a
## shot, throwing a punch, keeping an automatic gun's trigger down for a burst, stepping back when a
## barrel is against a wall, the reload reflex, and the peek-and-cover cycle (step out, shoot, duck)
## with its committed firing / cover spot, and throwing a grenade (`docs/grenades.md` G17: take it
## in hand, aim at the spot, throw, put the gun back: its part `throw`, `combat_throw.gd`). Owns the
## fire cooldown and that cycle's phase and timers, and reads its tunables live from the NPC's
## `tuning.combat`. `Behavior` decides WHICH fight is on (it holds the engaged
## contact and the hold-ground flag) and passes the target in each call; this class never chooses a
## target and reads the world only through the perception (`has_line_to`, `combat_spots`,
## `note_engaged`) and the character's public contract. It knows no gun from another: the gun it
## fights with is `Character.inventory.gun_slot()`.

## The gun is empty: the shot was not taken (a click is not a shot), so the caller should re-decide.
signal dry

## Facing error (radians) within which a shot is taken, or a grenade let go (`faces`) — aim settles
## a frame after it is set.
const AIM_TOLERANCE := 0.15
## The throw (`throw`).
const Throw := preload("res://scenes/ai/behavior/combat_throw.gd")

## The NPC's tunables, handed in by `setup`: the fight reads `tuning.combat` live (its ranges, the
## ring of spots, the cover time, the cooldown, the burst, the back-off, the reposition interval,
## the reload reflex).
var tuning: NpcTuning
## The throw in hand (`docs/grenades.md` G17): its stage, the grenade, the spot, from where, and its
## clock (combat_throw.gd).
var throw := Throw.new()
## Whether the NPC fires blind while flash-blinded (`docs/grenades.md` G15): the controller's roll
## as it went blind (`Behavior.set_blind_fire`). Read only while blind (`holds_fire`).
var blind_fire := true
## Peek-and-cover phase: "peek" (seek a shot) or "cover" (duck).
var phase := "peek"
## Seconds left ducking behind cover before peeking again.
var cover_timer := 0.0
## Seconds left before the next shot/punch may be thrown.
var fire_timer := 0.0
## Committed fire/cover position the NPC is steering toward.
var dest := Vector2.ZERO
## A squad member following its leader fights within `leash` px of this, the leader's live
## position (`Vector2.INF`: no leash), set every tick by `Behavior.set_leash` (LD23).
var leash_center := Vector2.INF
## The leash (px) round `leash_center` a follower fights within (0 with no leash).
var leash := 0.0
## Seconds left before a new combat position may be chosen.
var dest_timer := 0.0
## Rounds still to fire in the automatic gun's current burst.
var _burst_left := 0
## Seconds left stepping back from whatever the gun's barrel is against.
var _back_off_timer := 0.0
## The Locomotion child (pathing, rooms).
var _loco: Node
## The perception sub-domain (line of fire, candidate spots, engagement memory).
var _perception: Node
## The NPC's body, handed in once by `bind`: whose hands fight.
var _character: Node


## Capture the locomotion, the perception and the NPC's `npc_tuning`, and hand the throw its
## locomotion. Called once by `Behavior.setup()`.
func setup(loco: Node, perception: Node, npc_tuning: NpcTuning) -> void:
	_loco = loco
	_perception = perception
	tuning = npc_tuning
	throw.setup(loco)


## Hand in the NPC's body, the throw's too. Called once by `Behavior.bind()`.
func bind(character: Node) -> void:
	_character = character
	throw.bind(character)


## A fight begins: the cycle starts in its peek phase and a firing spot is picked at once.
func begin_fight() -> void:
	phase = "peek"
	dest_timer = 0.0


## Advance the fire cooldown by `delta`.
func tick(delta: float) -> void:
	fire_timer -= delta


## Whether `target` (a known-contact dict) can be shot at now: a loaded gun not mid-reload, and
## `has_line_of_fire`. The cooldown, the facing and a run are not counted: they pass in a moment,
## this says the NPC is in a position to fire.
func can_fire_at(target: Dictionary) -> bool:
	var gun: int = _character.inventory.gun_slot()
	if (gun < 0
			or _character.ammo.rounds(gun) == 0
			or _character.ammo.is_reloading()
			or target.is_empty()):
		return false
	return has_line_of_fire(target)


## Whether `target` (a known-contact dict) stands within range on a clear line to where it is known
## to be: a shot at it is possible from here whatever the gun's state (the entry reads it as
## "engaged from outside", docs/tactical-entry.md E14).
func has_line_of_fire(target: Dictionary) -> bool:
	if target.is_empty():
		return false
	var pos: Vector2 = target["pos"]
	return (_character.global_position.distance_to(pos) <= tuning.combat.shoot_range
			and _perception.has_line_to(target["node"], pos))


## Shoot `target` (a known-contact dict) when it can be shot at (`can_fire_at`), once the facing has
## settled on it; aims at it meanwhile. No-op otherwise.
func fire_at_will(target: Dictionary) -> void:
	if not can_fire_at(target):
		return
	var pos: Vector2 = target["pos"]
	_character.movement.aim_point = pos
	if fire_timer <= 0.0 and faces(_character, pos):
		shoot()


## Whether the NPC holds its fire: blind, and this blinding's roll said it does not fire blind
## (G15). It shoots again once it can see.
func holds_fire() -> bool:
	return not blind_fire and _character.stun.is_blind()


## Ambush: hold the covered spot and fire the moment a line to the known position opens.
func ambush(node: Node2D, pos: Vector2) -> void:
	_character.movement.move_input = Vector2.ZERO
	if _character.global_position.distance_to(pos) <= tuning.combat.shoot_range \
			and _perception.has_line_to(node, pos) and fire_timer <= 0.0 and faces(_character, pos):
		shoot()


## Peek-and-cover shooting at the known contact (`node` at `pos`): in the PEEK phase, move to a spot
## with a clear shot and fire, then duck; in the COVER phase, hold behind a shielding object for
## `tuning.combat.cover_time` before peeking again. The fire/cover destination is committed for
## `tuning.combat.reposition_interval` rather than re-picked every frame, so the NPC steers smoothly
## instead of vibrating between near-equal candidates. `hold_ground` keeps the chosen spots inside
## the house, or inside room `room` when given (a member ordered to defend it, `docs/leadership.md`
## LD8), and a leash (`leash_center`) within it.
func peek_cover(delta: float, node: Node2D, pos: Vector2, hold_ground: bool, room := "") -> void:
	var dist: float = _character.global_position.distance_to(pos)
	dest_timer -= delta
	if phase == "cover":
		cover_timer -= delta
		if dest_timer <= 0.0:
			dest = _choose_dest("cover", node, pos, hold_ground, room)
			dest_timer = tuning.combat.reposition_interval
		_loco.move_to(dest)
		reload_if_dry()
		if cover_timer <= 0.0:
			phase = "peek"
			dest_timer = 0.0  # Re-pick a firing spot immediately on peeking out.
		return
	# PEEK: take the shot if a clear line to the known position is in range, else reposition to get
	# one.
	if dist <= tuning.combat.shoot_range and _perception.has_line_to(node, pos):
		_character.movement.move_input = Vector2.ZERO
		# Shoot only once the facing has settled on it. A refused shot (a barrel against a wall
		# stepping back, a reload under way) keeps the NPC peeking until it fires, rather than
		# ducking without having fired; a click on an empty gun ducks, where the cover phase reloads
		# it.
		if fire_timer <= 0.0 and faces(_character, pos):
			var fired := shoot()
			if fired or _character.ammo.rounds(_character.inventory.gun_slot()) == 0:
				phase = "cover"
				cover_timer = tuning.combat.cover_time
				dest_timer = 0.0  # Pick a cover spot immediately after shooting.
		return
	if dest_timer <= 0.0:
		dest = _choose_dest("peek", node, pos, hold_ground, room)
		dest_timer = tuning.combat.reposition_interval
	_loco.move_to(dest)


## Melee at the known position `pos`: close to punch range and strike on the fire cooldown (no cover
## cycle for fists). While holding ground it won't chase a contact out of the house, nor off its
## leash — it only swings if one is already in reach.
func melee(pos: Vector2, hold_ground: bool) -> void:
	if _character.global_position.distance_to(pos) > tuning.combat.punch_range:
		if not hold_ground and _on_leash(pos):
			_loco.move_to(pos)
		else:
			_character.movement.move_input = Vector2.ZERO
		return
	_character.movement.move_input = Vector2.ZERO
	if fire_timer <= 0.0:
		_strike()


## Equip the character's gun and fire it, refreshing the combat engagement so an active fight stays
## committed; true when a round left the barrel. Nothing here is specific to a gun:
##   - at a run or mid-reload it holds fire and keeps the cooldown for when that stops;
##   - blind, when its roll said it holds its fire (`holds_fire`), it does not pull the trigger at
##     all, so not even a click;
##   - dry, a click is not a shot, so it neither commits the fight nor needs a hand free to reload —
##     it emits `dry` (the empty gun is in the snapshot now), at most once per cooldown;
##   - with the barrel against a wall or object (`weapon.blocked()`) it cannot fire, so it steps
##     back until it can, keeping the cooldown;
## - an automatic gun's pull is a burst (`tuning.combat.fire_burst` rounds, `continue_burst`), the
## rest at the
##     gun's own rate.
func shoot() -> bool:
	if _character.movement.is_running() or _character.ammo.is_reloading() or holds_fire():
		return false
	var gun: int = _character.inventory.gun_slot()
	if gun < 0:
		return false
	if _character.ammo.rounds(gun) == 0:
		fire_timer = tuning.combat.fire_cooldown
		dry.emit()
		return false
	_character.inventory.select_slot(gun)
	if _character.weapon.blocked():
		_back_off_timer = tuning.combat.back_off_time
		return false
	if not _character.weapon.shoot():
		return false
	_perception.note_engaged()
	fire_timer = tuning.combat.fire_cooldown
	_burst_left = maxi(tuning.combat.fire_burst - 1, 0) if _character.weapon.is_automatic() else 0
	return true


## Keep the trigger down for the rest of an automatic gun's burst: one more round each time the
## gun's own fire rate allows, until the burst is spent or something stops it (a run, a reload, a
## swap, a wall, running dry, a blinding it holds its fire through).
func continue_burst() -> void:
	if _burst_left <= 0:
		return
	if not _character.weapon.is_automatic() or _character.movement.is_running() \
			or _character.ammo.is_reloading() or _character.weapon.blocked() \
			or _character.ammo.rounds() <= 0 or holds_fire():
		_burst_left = 0
		return
	if _character.weapon.shoot():
		_burst_left -= 1


## Step back from whatever the gun's barrel is against (`shoot` set the timer): away from where it
## points, walking, until the barrel is clear or the time is up. Applied after the primitive has
## steered, so it wins.
func apply_back_off(delta: float) -> void:
	if _back_off_timer <= 0.0:
		return
	_back_off_timer -= delta
	_character.movement.move_input = -_character.facing
	_loco.give_way.keep_off()  # Never back into a body it knows of.
	_character.movement.run_input = false


## Reflex: swap in a fresh magazine when the gun is empty and one is carried
## (`tuning.combat.auto_reload`). It equips the gun first, since a reload works on the held item.
func reload_if_dry() -> void:
	if not reload_due():
		return
	_character.inventory.select_slot(_character.inventory.gun_slot())
	_character.ammo.reload()


## A tactical reload (docs/tactical-entry.md E11): swap a part-spent magazine for a full one in a
## lull, the way a stack tops its gun off before it crosses. Starts the reload when the held gun is
## short of full with a magazine to add; true while it is under way or wanted, so a caller that must
## not move on armed waits for false. The caller stands still (a run cancels it).
func top_off() -> bool:
	var gun: int = _character.inventory.gun_slot()
	if gun < 0:
		return false
	if _character.ammo.is_reloading():
		return true
	if (_character.ammo.rounds(gun) >= _character.ammo.capacity(gun)
			or not _character.ammo.can_reload(gun)):
		return false
	_character.inventory.select_slot(gun)
	_character.ammo.reload()
	return true


## Whether the gun the NPC fights with is at or below `fraction` of its magazine (a follower at
## rest tops up such a one, LD22: not only a dry one).
func magazine_low(fraction: float) -> bool:
	var gun: int = _character.inventory.gun_slot()
	return (gun >= 0
			and _character.ammo.rounds(gun) <= ceili(_character.ammo.capacity(gun) * fraction))


## Whether the reload reflex is due: `tuning.combat.auto_reload` is on and the gun is empty with a
## spare magazine
## to put in it. (A reload runs only while standing, so a run is dropped for it.)
func reload_due() -> bool:
	var gun: int = _character.inventory.gun_slot()
	return (tuning.combat.auto_reload
			and gun >= 0
			and not _character.ammo.is_reloading()
			and _character.ammo.rounds(gun) == 0
			and _character.ammo.can_reload(gun))


## Land a blow, refreshing the combat engagement: a standing NPC with a gun in hand keeps it and
## kicks; otherwise (a crouched NPC cannot kick) it equips the fists and punches.
func _strike() -> void:
	if _character.ammo.capacity() >= 0 and _character.movement.posture() == &"stand":
		_kick()
	else:
		_punch()


## Kick with a leg, keeping whatever is held.
func _kick() -> void:
	_perception.note_engaged()
	fire_timer = tuning.combat.fire_cooldown
	_character.anatomy.leg_kick()


## Equip the fists and throw a punch, refreshing the combat engagement.
func _punch() -> void:
	_perception.note_engaged()
	fire_timer = tuning.combat.fire_cooldown
	_character.inventory.select_slot(ItemRegistry.FISTS_SLOT)
	_character.weapon.melee()


## Whether `character`'s facing has settled on world point `pos` (within `AIM_TOLERANCE`): for a
## shot, and for a grenade let go (the throw part's).
static func faces(character: Node, pos: Vector2) -> bool:
	return absf(character.facing.angle_to(pos - character.global_position)) <= AIM_TOLERANCE


## The committed destination for the current phase `kind`: the nearest spot with a clear shot
## ("peek") or the nearest shielded spot ("cover") around the known contact; falls back to closing
## on the contact (peek) or holding (cover) when no suitable spot exists this sample. While holding
## ground, spots are restricted to inside the house and the peek fallback holds position instead of
## advancing out; with a `room` (kept to by order) spots are restricted to inside that room in any
## case; on a leash, spots are restricted to within it and the peek fallback holds position too.
func _choose_dest(
	kind: String,
	node: Node2D,
	pos: Vector2,
	hold_ground: bool,
	room := "",
) -> Vector2:
	var spots: Dictionary = _perception.combat_spots(node, pos, tuning.combat.ring_radius)
	var fire: Array = spots["fire"]
	var cover: Array = spots["cover"]
	if hold_ground or room != "":
		var keep := func(p):
			return _loco.room_key_at(p) == room if room != "" else _loco.inside_house(p)
		fire = fire.filter(keep)
		cover = cover.filter(keep)
	if leash_center != Vector2.INF:
		fire = fire.filter(_on_leash)
		cover = cover.filter(_on_leash)
	if kind == "cover":
		return cover[0] if not cover.is_empty() else _character.global_position
	if not fire.is_empty():
		return fire[0]
	return _character.global_position if hold_ground or leash_center != Vector2.INF else pos


## Whether point `p` is within the leash (true with none).
func _on_leash(p: Vector2) -> bool:
	return leash_center == Vector2.INF or leash_center.distance_to(p) <= leash
