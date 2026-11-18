class_name CharacterWeapon extends RefCounted
## Using the held item (`character.gd`'s `weapon`): firing and melee, a long gun raised against a
## wall, the recoil a fired gun throws the hands with, the muzzle and the aim an item reads, and how
## each hand is held (`stances`). The character judges the raise each physics frame
## (`update_raise`, after the facing is set) and hands the pose its stances.

## The character holding the item.
var character: CharacterBody2D
## A ducked body's rise over its cover to fire (`character_rise.gd`): the weapon asks it before a
## gun leaves the barrel, `movement.body_posture()` reads the pose it holds.
var rise: CharacterRise
## The held weapon's barrel is against a wall or object (only a weapon that `raises_at_contact`): it
## is held pointing up and cannot shoot. Set at once; `_raise` eases toward it (0 = held to the aim
## .. 1 = fully up).
var _blocked := false
## How far the held weapon is raised off the aim, 0..1, easing toward `_blocked`.
var _raise := 0.0


## The weapon use of `host`.
func _init(host: CharacterBody2D) -> void:
	character = host
	rise = CharacterRise.new(host)


## Melee with the held item (F): runs its primary action. Ignored while locked in an interaction.
func melee() -> void:
	var item: Item = character.inventory.current_item()
	if character.use.is_busy() or item == null:
		return
	item.primary(character)


## Shoot the held item (left-click): runs its secondary action; true when a round left the barrel.
## Ignored while locked in an interaction, running (the arms are down at the sides), reloading, or
## with the weapon's barrel against a wall or object (`blocked()`). A gun also holds back between
## rounds, per its fire rate.
func shoot() -> bool:
	var item: Item = character.inventory.current_item()
	if (character.use.is_busy()
			or item == null
			or character.movement.is_running()
			or character.ammo.is_reloading()):
		return false
	# Judge the barrel now rather than trusting the last frame's verdict: a controller acts before
	# this frame's check runs, and on a character's very first frame none has run at all, so a long
	# gun fired point-blank into a wall would leave through it.
	update_raise(0.0)
	if _blocked:
		return false
	# A ducked gun behind cover rises over it first (it holds its fire while it does).
	if character.movement.posture() == &"crouch" and item.gun_id() != &"":
		if not rise.rise_to(rise.pose_needed(item.weapon_hand())):
			return false
	return item.secondary(character)


## True while the held item keeps firing as long as the trigger is held (an automatic gun): a
## controller re-presses `shoot()` every frame instead of once per click.
func is_automatic() -> bool:
	var item: Item = character.inventory.current_item()
	return item != null and item.is_automatic()


## True while the held weapon's barrel is against a wall or object: it is held pointing up and
## `shoot()` does nothing until the character backs off. Only a weapon that `raises_at_contact()` is
## ever blocked.
func blocked() -> bool:
	return _blocked


## How far the held weapon is raised off the aim, 0 (held to the aim) .. 1 (fully up), easing toward
## the blocked state. For the weapon's art.
func raise() -> float:
	return _raise


## The drawn direction of a held weapon: it trails the aim a little as the character turns. Visual
## only — shots still leave along the character's `facing`.
func facing() -> Vector2:
	return Vector2.from_angle(character.anatomy.pose.weapon_angle)


## Recoil: throw `hand` back and twist the shoulders, as a fired weapon does (the item calls it);
## `strength` scales it (1 = a pistol's), so a light automatic's stream of rounds does not pile up.
## A long gun (one too long for a wall, `raises_at_contact`) fired one-handed kicks
## `CharacterStanceConfig.one_hand_recoil` times harder.
func kick(hand: int, strength := 1.0) -> void:
	var item: Item = character.inventory.current_item()
	if item != null and item.raises_at_contact() and one_handed():
		strength *= CharacterStanceConfig.one_hand_recoil
	character.anatomy.pose.arms.kick(hand, strength)


## World muzzle point for a weapon in `hand`: the held item's `muzzle_ahead()` past it (a long gun
## reaches further than a pistol), along the aim.
func muzzle_origin(hand: int) -> Vector2:
	var item: Item = character.inventory.current_item()
	return character.anatomy.hands.world(hand) + character.facing * _muzzle_ahead(item)


## How high (px above the floor) a round leaves the muzzle: the bore line of the posture the body is
## in (`movement.body_posture()`): standing, ducked, or risen over its cover to fire (`rise_to`).
func muzzle_height() -> float:
	return BodyHeights.muzzle(character.movement.body_posture())


## How high (px above the floor) the shot is aimed at `movement.aim_point`: the height the
## controller set; for `AIM_AUTO` (an AI aiming at where a body is) the centre of the torso of the
## living character standing there, in its posture; else level, the muzzle's own height.
func aim_height() -> float:
	return aim_height_from(muzzle_height())


## `aim_height` for a muzzle at `level` px: the same unless the shot is level (a controller's
## `AIM_LEVEL`, or an `AIM_AUTO` with no body at the aim), which flies level at `level`.
func aim_height_from(level: float) -> float:
	var wanted: float = character.movement.aim_height
	if wanted >= 0.0:
		return wanted
	if wanted == CharacterMovement.AIM_AUTO:
		var target := _target_at(character.movement.aim_point)
		if target != null:
			return _torso_centre(target.movement.body_posture())
	return level


## The plan direction a round leaves the muzzle of the weapon in `hand` in before its spread: toward
## the point `GunConfig.zero_range` ahead of the body along its facing (so a gun held off the line
## still shoots where the character points), turned by the stun's sway.
func shot_direction(hand: int) -> Vector2:
	var muzzle := muzzle_origin(hand)
	var direction: Vector2 = (character.global_position
			+ character.facing * GunConfig.zero_range - muzzle).normalized()
	return direction.rotated(aim_sway())


## The point the character is aiming at, as an item reads it (a grenade is thrown to it): the aim
## point, swayed about the body by `aim_sway()`.
func aim_target() -> Vector2:
	var at: Vector2 = character.global_position
	return at + (character.movement.aim_point - at).rotated(aim_sway())


## How far (rad) the aim has swayed off where the character points: 0 unless stunned, then up to
## `CharacterStunConfig.sway` at the full stun, wandering. A gun turns each shot by it; the
## character's `facing` itself, and so the drawn body and weapon, stays on the aim.
func aim_sway() -> float:
	var stun: CharacterStun = character.stun
	var level := stun.level()
	return (0.0
			if level <= 0.0
			else deg_to_rad(CharacterStunConfig.sway) * level * stun.wander(0.0))


## How far (rad) the aim has swayed up or down: the stun's sway, in the other axis.
func aim_sway_lift() -> float:
	var stun: CharacterStun = character.stun
	var level := stun.level()
	return (0.0
			if level <= 0.0
			else deg_to_rad(CharacterStunConfig.sway) * level * stun.wander(1.7))


## Whether the held gun is held in one hand: the free hand is over the eyes (blind, `_covers_eyes`).
## A gun fired so spreads wider (`GunConfig` `one_hand_spread_deg`) and a long gun kicks harder.
## False for anything but a gun.
func one_handed() -> bool:
	var item: Item = character.inventory.current_item()
	return item != null and item.gun_id() != &"" and _covers_eyes(item)


## Judge whether the held weapon's barrel touches a wall or object, and ease the raise toward it.
## Only a weapon that `raises_at_contact()` is ever blocked. The barrel is a ray from beside the
## body centre along the aim, as far as the weapon reaches held normally (never as raised, or
## pulling it up would clear it and drop it again); it blocks when something solid is within that
## reach, and stays blocked until there is `CharacterStanceConfig.weapon_contact_margin` of
## clearance, so the weapon does not flicker at the edge.
func update_raise(delta: float) -> void:
	var item: Item = character.inventory.current_item()
	if item == null or not item.raises_at_contact():
		_blocked = false
	else:
		var hand := item.weapon_hand()
		var stance: Dictionary = CharacterStanceConfig.stances.get(
			item.hand_stance(hand),
			CharacterStanceConfig.stances[&"relaxed"],
		)
		var reach: float = (float(stance["forward"]) + character.movement.posture_hand_ahead()
				+ _muzzle_ahead(item))
		var lateral: float = float(stance["lateral"]) * (-1.0 if hand == 0 else 1.0)
		var aim: Vector2 = character.facing
		var from: Vector2 = character.global_position + aim.orthogonal() * lateral
		var margin := 0.0 if not _blocked else CharacterStanceConfig.weapon_contact_margin
		var clear: float = character.anatomy.hands.solid_distance(from, aim, reach + margin + 1.0)
		_blocked = clear < reach + margin
	_raise = move_toward(
		_raise,
		1.0 if _blocked else 0.0,
		CharacterStanceConfig.weapon_raise_speed * delta,
	)


## Lower the weapon at once and judge its barrel afresh: a new loadout starts held to the aim.
func reset_raise() -> void:
	_raise = 0.0
	update_raise(0.0)


## How each hand is held (CharacterStanceConfig.stances names), as the held item asks: arms hang
## with nothing held. Running puts both arms down at the sides whatever is held; a weapon whose
## barrel is against a wall or object is held raised, as the item says. Blind, the free hand covers
## the eyes (`eyes`) and a gun is held in the weapon hand alone (`one_hand`; raised off a wall, its
## raised grip), unless the item needs that hand (`_covers_eyes`).
func stances() -> Array:
	if character.movement.is_running():
		return [&"run", &"run"]
	var item: Item = character.inventory.current_item()
	var out: Array
	if item == null:
		out = [&"relaxed", &"relaxed"]
	elif _blocked:
		out = [item.raised_stance(0), item.raised_stance(1)]
	else:
		out = [item.hand_stance(0), item.hand_stance(1)]
	if _covers_eyes(item):
		var weapon_hand := item.weapon_hand() if item != null else 0
		out[1 - weapon_hand] = &"eyes"
		if item != null and item.gun_id() != &"" and not _blocked:
			out[weapon_hand] = &"one_hand"
	return out


## Whether the free hand (the one the held item does not hold its weapon in) is over the eyes: while
## blind, on its own feet (a ride's pose wins), and not while the item needs that hand: a reload, a
## punch, a throw's wind-up.
func _covers_eyes(item: Item) -> bool:
	if (not character.stun.is_blind()
			or character.use.is_riding()
			or character.movement.is_running()
			or character.is_dead):
		return false
	if character.ammo.is_reloading() or character.anatomy.hands.is_attacking():
		return false
	return item == null or item.hand_stance(item.weapon_hand()) != &"throw"


## How far past the weapon hand `item`'s muzzle is: its own `muzzle_ahead()`, or
## `CharacterStanceConfig.muzzle_ahead` for an item that gives none (or no item).
static func _muzzle_ahead(item: Item) -> float:
	var ahead := item.muzzle_ahead() if item != null else -1.0
	return ahead if ahead >= 0.0 else CharacterStanceConfig.muzzle_ahead


## The living character other than this one standing at `at` (within `CharacterHitConfig.aim_reach`
## body radii), the nearest to it; null for none.
func _target_at(at: Vector2) -> Node2D:
	var best: Node2D = null
	var best_gap := INF
	for other: Node in character.get_tree().get_nodes_in_group(&"characters"):
		if other == character or other.is_dead or not character.get_parent().is_ancestor_of(other):
			continue
		var gap := (other as Node2D).global_position.distance_to(at)
		if gap <= other.radius * CharacterHitConfig.aim_reach and gap < best_gap:
			best = other
			best_gap = gap
	return best


## The middle (px above the floor) of the torso band of a body in `posture`.
static func _torso_centre(posture: StringName) -> float:
	for band: Array in BodyHeights.zones(posture):
		if band[0] == &"torso":
			return (float(band[1]) + float(band[2])) * 0.5
	return BodyHeights.head_top(posture) * 0.5
