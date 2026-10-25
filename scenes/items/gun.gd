class_name GunItem extends Item
## Items domain: a gun held in the right hand: the logic every firearm shares, driven by its row in
## `GunConfig` (damage, fire rate, penetration, muzzle speed, spread, recoil, whether it is
## automatic and whether its barrel is too long to use against a wall). F still jabs with the weapon
## hand (melee); left-click fires a projectile and ejects a casing. It is drawn by its `art` part
## (`GunArt`), in its weapon style by the row's look. Its sizes and how it is held are its row's
## too (`art_size`, `flat_size`, `grip_back` and the stances): a subclass (`PistolItem`, `SmgItem`,
## `RifleItem`) only names its row (`super(GUN)`). Items reach into the Projectile System in two
## places: here, via ProjectileSpawner / CasingSpawner (a shot's `hit` is forwarded back to the
## character's `report_shot` for the HUD), and ThrownGrenade, via `Explosion.frag` /
## `Explosion.stun`.

## The gun's id: its `GunConfig` row and the kind of magazine it takes (`Magazine.gun`). Named by
## the subclass (`super(GUN)`).
var gun: StringName = &""
## Seconds until the next round may leave. Counts down in `tick`; firing adds the fire interval, so
## an overshoot carries into the next round and the rate holds even when it is not a whole number of
## frames.
var _cooldown := 0.0
## Its `ammo` part as what it is, the gun's load (`GunAmmo`), so a shot spends a round with no cast.
var _load: GunAmmo


func _init(id: StringName) -> void:
	gun = id
	_load = GunAmmo.new(id)
	var melee := _long_gun_strike() if raises_at_contact() else ItemStrike.new()
	super(melee, _load, GunArt.new(id, melee))
	display_name = str(_stat("name", display_name))
	reach = 32.0


# --- Stats (read live from GunConfig, so tuning it takes effect at once) ---------------------


## A value from this gun's `GunConfig` row (`fallback` when the row has none).
func _stat(key: String, fallback: Variant = null) -> Variant:
	return GunConfig.row(gun).get(key, fallback)


## Damage added on top of the projectile's own base damage at fire time.
func _damage() -> float:
	return float(_stat("damage", 0.0))


## Seconds between rounds.
func _fire_interval() -> float:
	return float(_stat("fire_interval", 0.0))


## The held art's footprint (px): width across, length from butt to muzzle (the row's
## `art_size`).
func _art_size() -> Vector2:
	return _stat("art_size", Vector2.ZERO)


## How far the butt end sits behind the weapon hand's center (px; the row's `grip_back`).
func _grip_back() -> float:
	return float(_stat("grip_back", 0.0))


## A long gun's strike (`ItemStrike`): it strikes with its butt, its length behind the grip, swung
## nearly across the body in both hands, twice as slowly as a fist and a little short of a fist's
## reach, the other hand gripping toward the butt.
func _long_gun_strike() -> ItemStrike:
	var long_gun := ItemStrike.new()
	long_gun.ahead = _grip_back()
	long_gun.turn = ItemStrike.STRIKE_TURN
	long_gun.short = ItemStrike.STRIKE_SHORT
	long_gun.support_gap = ItemStrike.SUPPORT_GAP
	long_gun.tempo = ItemStrike.LONG_TEMPO
	return long_gun


# --- Item contract --------------------------------------------------------------------------


## The gun's id.
func gun_id() -> StringName:
	return gun


## The penetration power of its rounds (the row's `penetration`).
func round_power() -> float:
	return float(_stat("penetration", 1.0))


## The weapon hand aims the gun and holds its grip; the other hand holds it forward, or while
## reloading drops to the belt for the next magazine.
func hand_stance(hand: int) -> StringName:
	if hand == weapon_hand():
		return _stat("grip_stance", &"aim")
	return &"reload" if ammo.reloading else _stat("fore_stance", &"support")


## How `hand` is held while the weapon is raised: the weapon hand's raised stance; the other hand's,
## or the belt while reloading.
func raised_stance(hand: int) -> StringName:
	if hand == weapon_hand():
		return _stat("raised_grip_stance", &"aim")
	return &"reload" if ammo.reloading else _stat("raised_fore_stance", &"support")


## Whether holding the trigger keeps firing (the row's `automatic`).
func is_automatic() -> bool:
	return bool(_stat("automatic", false))


## Whether the barrel is too long to use against a wall (the row's `raises_at_contact`).
func raises_at_contact() -> bool:
	return bool(_stat("raises_at_contact", false))


## Past the hand: the art's length less the butt behind it.
func muzzle_ahead() -> float:
	return _art_size().y - _grip_back()


## Count the time between rounds down. The credit for an overshoot is capped at one frame, so a gun
## left idle fires its next round at once but never a burst to catch up.
func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, -delta)


## F: a melee jab with the weapon hand; a long gun swings round and leads with its butt.
func primary(user: Node2D) -> void:
	user.anatomy.hands.punch(weapon_hand())


## LMB: fire a bullet from the muzzle and eject a casing (both live in world space); the gun kicks
## the hand back. Spends a round; an empty, mid-reload or still-cycling gun does nothing. The round
## leaves within the gun's spread of the aim, wider by its `one_hand_spread_deg` while its user
## holds it in one hand (`weapon.one_handed()`). True when a round left the barrel.
func secondary(user: Node2D) -> bool:
	if _load.reloading or _load.rounds_loaded() <= 0 or _cooldown > 0.0:
		return false
	_load.magazine.rounds -= 1
	_cooldown += _fire_interval()
	var hand := weapon_hand()
	var muzzle: Vector2 = user.weapon.muzzle_origin(hand)
	# Zeroed: the round crosses the aim line `zero_range` ahead of the body, so a gun held off the
	# line (the butt on the right shoulder) still shoots where the character points.
	var direction: Vector2 = (user.global_position + user.facing * GunConfig.zero_range
			- muzzle).normalized()
	# A stunned character's aim wanders off the line.
	direction = direction.rotated(user.weapon.aim_sway())
	var spread_deg := float(_stat("spread_deg", 0.0))
	# Held in one hand (the other over its eyes): the gun wanders off the line.
	if user.weapon.one_handed():
		spread_deg += float(_stat("one_hand_spread_deg", 0.0))
	var spread := deg_to_rad(spread_deg)
	if spread > 0.0:
		direction = direction.rotated(randf_range(-spread, spread))
	var power := round_power()
	var shot := Shot.new()
	shot.shooter = user
	shot.item_damage = _damage()
	shot.muzzle_speed = float(_stat("muzzle_speed", -1.0))
	shot.penetration = power
	var proj := ProjectileSpawner.spawn(muzzle, direction, user.world_root(), shot)
	proj.hit.connect(func(body: Node, dmg: float) -> void: user.report_shot(body, dmg))
	CasingSpawner.spawn(user.anatomy.hands.world(hand), user.facing, user.world_root())
	user.weapon.kick(hand, float(_stat("recoil", 1.0)))
	# The report of the shot, for whoever listens (the Audio domain); the round itself is already on
	# its way.
	EventBus.post(&"shot", { "position": muzzle, "gun": gun, "attacker": user, "power": power })
	return true


## The dead hand lets go: the gun leaves from where it was drawn and skids off at `velocity`.
func drop(user: Node2D, velocity: Vector2) -> Node2D:
	var facing: Vector2 = user.weapon.facing()
	var hand: Vector2 = user.anatomy.hands.world(weapon_hand())
	var at := hand + facing * (_art_size().y * 0.5 - _grip_back())
	var dropped := DroppedItem.spawn(self, facing.angle(), velocity)
	dropped.place(user.world_root(), at, hand)
	return dropped
