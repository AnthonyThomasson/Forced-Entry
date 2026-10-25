class_name CharacterWeapon extends RefCounted
## Using the held item (`character.gd`'s `weapon`): firing and melee, a long gun raised against a
## wall, the recoil a fired gun throws the hands with, the muzzle and the aim an item reads, and how
## each hand is held (`stances`). The character judges the raise each physics frame
## (`update_raise`, after the facing is set) and hands the pose its stances.

## The character holding the item.
var character: CharacterBody2D
## The character's `Hands` node (`character_hands.gd`), which casts the barrel's ray. Set by the
## character's `_ready`.
var hands: Node2D
## The held weapon's barrel is against a wall or object (only a weapon that `raises_at_contact`): it
## is held pointing up and cannot shoot. Set at once; `_raise` eases toward it (0 = held to the aim
## .. 1 = fully up).
var _blocked := false
## How far the held weapon is raised off the aim, 0..1, easing toward `_blocked`.
var _raise := 0.0


## The weapon use of `host`.
func _init(host: CharacterBody2D) -> void:
	character = host


## Melee with the held item (F): runs its primary action. Ignored while locked in an interaction.
func melee() -> void:
	var item: Item = character.current_item()
	if character.is_busy() or item == null:
		return
	item.primary(character)


## Shoot the held item (left-click): runs its secondary action; true when a round left the barrel.
## Ignored while locked in an interaction, running (the arms are down at the sides), reloading, or
## with the weapon's barrel against a wall or object (`blocked()`). A gun also holds back between
## rounds, per its fire rate.
func shoot() -> bool:
	var item: Item = character.current_item()
	if (character.is_busy()
			or item == null
			or character.is_running()
			or character.ammo.is_reloading()):
		return false
	# Judge the barrel now rather than trusting the last frame's verdict: a controller acts before
	# this frame's check runs, and on a character's very first frame none has run at all, so a long
	# gun fired point-blank into a wall would leave through it.
	update_raise(0.0)
	if _blocked:
		return false
	return item.secondary(character)


## True while the held item keeps firing as long as the trigger is held (an automatic gun): a
## controller re-presses `shoot()` every frame instead of once per click.
func is_automatic() -> bool:
	var item: Item = character.current_item()
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
	return Vector2.from_angle(character.pose.weapon_angle)


## Recoil: throw `hand` back and twist the shoulders, as a fired weapon does (the item calls it);
## `strength` scales it (1 = a pistol's), so a light automatic's stream of rounds does not pile up.
## A long gun (one too long for a wall, `raises_at_contact`) fired one-handed kicks
## `CharacterStanceConfig.one_hand_recoil` times harder.
func kick(hand: int, strength := 1.0) -> void:
	var item: Item = character.current_item()
	if item != null and item.raises_at_contact() and one_handed():
		strength *= CharacterStanceConfig.one_hand_recoil
	character.pose.arms.kick(hand, strength)


## World muzzle point for a weapon in `hand`: the held item's `muzzle_ahead()` past it (a long gun
## reaches further than a pistol), along the aim.
func muzzle_origin(hand: int) -> Vector2:
	return character.hand_world(hand) + character.facing * _muzzle_ahead(character.current_item())


## The point the character is aiming at, as an item reads it (a grenade is thrown to it): the aim
## point, swayed about the body by `aim_sway()`.
func aim_target() -> Vector2:
	var at: Vector2 = character.global_position
	return at + (character.aim_point - at).rotated(aim_sway())


## How far (rad) the aim has swayed off where the character points: 0 unless stunned, then up to
## `CharacterStunConfig.sway` at the full stun, wandering. A gun turns each shot by it; the
## character's `facing` itself, and so the drawn body and weapon, stays on the aim.
func aim_sway() -> float:
	var stun: CharacterStun = character.stun
	var level := stun.level()
	return (0.0
			if level <= 0.0
			else deg_to_rad(CharacterStunConfig.sway) * level * stun.wander(0.0))


## Whether the held gun is held in one hand: the free hand is over the eyes (blind, `_covers_eyes`).
## A gun fired so spreads wider (`GunConfig` `one_hand_spread_deg`) and a long gun kicks harder.
## False for anything but a gun.
func one_handed() -> bool:
	var item: Item = character.current_item()
	return item != null and item.gun_id() != &"" and _covers_eyes(item)


## Judge whether the held weapon's barrel touches a wall or object, and ease the raise toward it.
## Only a weapon that `raises_at_contact()` is ever blocked. The barrel is a ray from beside the
## body centre along the aim, as far as the weapon reaches held normally (never as raised, or
## pulling it up would clear it and drop it again); it blocks when something solid is within that
## reach, and stays blocked until there is `CharacterStanceConfig.weapon_contact_margin` of
## clearance, so the weapon does not flicker at the edge.
func update_raise(delta: float) -> void:
	var item: Item = character.current_item()
	if item == null or not item.raises_at_contact():
		_blocked = false
	else:
		var hand := item.weapon_hand()
		var stance: Dictionary = CharacterStanceConfig.stances.get(
			item.hand_stance(hand),
			CharacterStanceConfig.stances[&"relaxed"],
		)
		var reach: float = (float(stance["forward"]) + character.posture_hand_ahead()
				+ _muzzle_ahead(item))
		var lateral: float = float(stance["lateral"]) * (-1.0 if hand == 0 else 1.0)
		var aim: Vector2 = character.facing
		var from: Vector2 = character.global_position + aim.orthogonal() * lateral
		var margin := 0.0 if not _blocked else CharacterStanceConfig.weapon_contact_margin
		_blocked = hands.solid_distance(from, aim, reach + margin + 1.0) < reach + margin
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
	if character.is_running():
		return [&"run", &"run"]
	var item: Item = character.current_item()
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
			or character.is_riding()
			or character.is_running()
			or character.is_dead):
		return false
	if character.ammo.is_reloading() or hands.is_attacking():
		return false
	return item == null or item.hand_stance(item.weapon_hand()) != &"throw"


## How far past the weapon hand `item`'s muzzle is: its own `muzzle_ahead()`, or
## `CharacterStanceConfig.muzzle_ahead` for an item that gives none (or no item).
static func _muzzle_ahead(item: Item) -> float:
	var ahead := item.muzzle_ahead() if item != null else -1.0
	return ahead if ahead >= 0.0 else CharacterStanceConfig.muzzle_ahead
