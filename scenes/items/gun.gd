class_name GunItem extends Item
## Items domain: a gun held in the right hand: the logic every firearm shares, driven by its row in
## `GunConfig` (damage, fire rate, penetration, muzzle speed, spread, recoil, whether it is
## automatic and whether its barrel is too long to use against a wall). F still jabs with the weapon
## hand (melee); left-click fires a projectile and ejects a casing. It is drawn in its weapon style
## (`Item.style`) by the row's look (`GunConfig.look`: the painter and colours). Its sizes and how
## it is held are its row's too (`art_size`, `flat_size`, `grip_back` and the stances): a subclass
## (`PistolItem`, `SmgItem`, `RifleItem`) only names its row (`super(GUN)`). Items reach into the
## Projectile System in two places: here, via ProjectileSpawner / CasingSpawner (a shot's `hit` is
## forwarded back to the character's `report_shot` for the HUD), and ThrownGrenade, via
## `Explosion.frag` / `Explosion.stun`.

## How far the pulled-up barrel shortens at full raise (fraction of its length): pointed up, a
## top-down view sees it foreshortened. The art is re-rendered at `RAISE_STEPS` lengths between full
## and this, so it stays crisp and cached.
const RAISED_LENGTH := 0.42
const RAISE_STEPS := 5
## How far (px) along a long gun's barrel from the weapon hand the support hand grips through a butt
## strike: toward the butt, so the other arm does not reach across the weapon hand.
const SUPPORT_GAP := -8.0
## How far (rad) a long gun turns in a butt strike: nearly across the body (105 degrees), the butt a
## little ahead of the muzzle.
const STRIKE_TURN := 1.833
## How far (px) short of a fist's reach a long gun's blow lands.
const STRIKE_SHORT := 5.0

## The guns and styles whose art `prepaint` has painted: [gun, style] -> true.
static var _prepainted := {}

## The gun's id: its `GunConfig` row and the kind of magazine it takes (`Magazine.gun`). Named by
## the subclass (`super(GUN)`).
var gun: StringName = &""
## The magazine it is loaded with (null = unloaded); every shot spends one of its rounds.
var magazine: Magazine
## Seconds until the next round may leave. Counts down in `tick`; firing adds the fire interval, so
## an overshoot carries into the next round and the rate holds even when it is not a whole number of
## frames.
var _cooldown := 0.0


func _init(id: StringName) -> void:
	gun = id
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


## The flat art's footprint (px): its profile across, its length along (the row's `flat_size`).
func _flat_size() -> Vector2:
	return _stat("flat_size", Vector2.ZERO)


## How far the butt end sits behind the weapon hand's center (px; the row's `grip_back`).
func _grip_back() -> float:
	return float(_stat("grip_back", 0.0))


## How it is drawn: its row's look in its weapon style (`GunConfig.look`: `painter`, colours,
## `finish`).
func look() -> Dictionary:
	return GunConfig.look(gun, style)


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
	return &"reload" if reloading else _stat("fore_stance", &"support")


## How `hand` is held while the weapon is raised: the weapon hand's raised stance; the other hand's,
## or the belt while reloading.
func raised_stance(hand: int) -> StringName:
	if hand == weapon_hand():
		return _stat("raised_grip_stance", &"aim")
	return &"reload" if reloading else _stat("raised_fore_stance", &"support")


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


## Rounds left in the loaded magazine (0 when unloaded).
func rounds_loaded() -> int:
	return magazine.rounds if magazine else 0


## Rounds the loaded magazine holds when full (0 when unloaded).
func ammo_capacity() -> int:
	return magazine.capacity if magazine else 0


## How long a reload takes: the loaded magazine's type decides (`MagazineConfig.reload_time_of`).
func reload_time() -> float:
	var type: StringName = magazine.type if magazine else StringName(_stat("magazine", &"standard"))
	return MagazineConfig.reload_time_of(type)


## A carried magazine holds more rounds than the one loaded.
func can_reload(user: Node2D) -> bool:
	var best: Magazine = user.ammo.best_magazine(gun)
	return best != null and best.rounds > rounds_loaded()


## Seat the fullest carried magazine; the one it replaces goes back into the carried store unless it
## is empty (nothing refills a magazine, so an empty one is dropped).
func finish_reload(user: Node2D) -> void:
	var fresh: Magazine = user.ammo.take_magazine(gun)
	if fresh == null:
		return
	var spent := magazine
	magazine = fresh
	if spent != null and spent.rounds > 0:
		user.ammo.stow_magazine(spent)


## A long gun (the kind too long for a wall) strikes with its butt: its length behind the grip.
func strike_ahead() -> float:
	return _grip_back() if raises_at_contact() else 0.0


## How far (px) the other hand grips ahead of the weapon hand along the barrel: it holds the gun
## through a butt strike.
func strike_support_gap() -> float:
	return SUPPORT_GAP if raises_at_contact() else 0.0


## A long gun swung in both hands lands a little short of a fist's reach, which keeps the support
## arm from overstretching.
func strike_short() -> float:
	return STRIKE_SHORT if raises_at_contact() else 0.0


## A long gun turns nearly across the body in a butt strike.
func strike_turn() -> float:
	return STRIKE_TURN if raises_at_contact() else 0.0


## A long gun is swung twice as slowly as a fist is thrown.
func strike_tempo() -> float:
	return 2.0 if raises_at_contact() else 1.0


## F: a melee jab with the weapon hand; a long gun swings round and leads with its butt.
func primary(user: Node2D) -> void:
	user.anatomy.hands.punch(weapon_hand())


## LMB: fire a bullet from the muzzle and eject a casing (both live in world space); the gun kicks
## the hand back. Spends a round; an empty, mid-reload or still-cycling gun does nothing. The round
## leaves within the gun's spread of the aim, wider by its `one_hand_spread_deg` while its user
## holds it in one hand (`weapon.one_handed()`). True when a round left the barrel.
func secondary(user: Node2D) -> bool:
	if reloading or rounds_loaded() <= 0 or _cooldown > 0.0:
		return false
	magazine.rounds -= 1
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


## Draw the gun's pixel art at the weapon hand, its butt behind the hand and the muzzle along the
## character's weapon.facing() (trailing the aim a touch as it turns): lit for the nearest lighting
## step, drawn rotated to the exact angle. Raised off a wall, the barrel foreshortens about the
## hand.
func draw_weapon(canvas: CanvasItem, user: Object) -> void:
	var facing: Vector2 = user.weapon.facing()
	# A punch turns a long gun about its grip until the butt leads.
	facing = strike_direction(facing, user.anatomy.hands.punch_amount(weapon_hand()))
	var step := clampi(roundi(float(user.weapon.raise()) * RAISE_STEPS), 0, RAISE_STEPS)
	var shrink := lerpf(1.0, RAISED_LENGTH, float(step) / RAISE_STEPS)
	var art_size := _art_size()
	var size := Vector2(art_size.x, maxf(roundf(art_size.y * shrink), 4.0))
	var centre: Vector2 = (user.anatomy.hands.hand_position(weapon_hand())
			+ facing * (size.y * 0.5 - _grip_back() * shrink))
	_draw_art(canvas, centre, facing, size)


## The dead hand lets go: the gun leaves from where it was drawn and skids off at `velocity`.
func drop(user: Node2D, velocity: Vector2) -> Node2D:
	var facing: Vector2 = user.weapon.facing()
	var hand: Vector2 = user.anatomy.hands.world(weapon_hand())
	var at := hand + facing * (_art_size().y * 0.5 - _grip_back())
	var dropped := DroppedItem.spawn(self, facing.angle(), velocity)
	dropped.place(user.world_root(), at, hand)
	return dropped


## The gun lying flat on its side, centered at `at`, its muzzle along `angle`, in its look's painter
## lying (`flat`); `opts.flip` picks the side facing up.
func draw_dropped(canvas: CanvasItem, at: Vector2, angle: float, modulate: Color = Color.WHITE,
		opts: Dictionary = {}) -> void:
	var turn := angle - PI * 0.5
	var size := _flat_size()
	var flip: bool = opts.get("flip", false)
	var drawn := look()
	var tex := PixelArt.render_turned(
		drawn["painter"], size, drawn["body"], PixelArt.snap_angle(turn),
		{
			"gun": gun, "look": _look_handle(drawn), "flat": true, "flip": flip,
			"material": drawn["finish"],
		},
	)
	_note_drawn(tex)
	canvas.draw_set_transform(at, turn, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Paint this gun's art ahead of time, once per gun and style: held at every raise step
## (`draw_weapon`) and lying on the floor either side up (`draw_dropped`), each at every lighting
## step. A gun turns, is raised off walls and skids from a dead hand through those, and each first
## paint (0.3 to 0.5 ms) would land in the busiest frames of a fight. The same calls the draws make,
## so the same cached textures: what is drawn never changes.
func prepaint() -> void:
	var key := [gun, style]
	if _prepainted.has(key):
		return
	_prepainted[key] = true
	var drawn := look()
	var handle := _look_handle(drawn)
	var art_size := _art_size()
	var step := TAU / maxi(1, ArtCanvasConfig.turn_steps)
	for k in ArtCanvasConfig.turn_steps:
		var angle := PixelArt.snap_angle(k * step)
		for raise in RAISE_STEPS + 1:
			var shrink := lerpf(1.0, RAISED_LENGTH, float(raise) / RAISE_STEPS)
			var size := Vector2(art_size.x, maxf(roundf(art_size.y * shrink), 4.0))
			PixelArt.render_turned(
				drawn["painter"],
				size,
				drawn["body"],
				angle,
				{ "gun": gun, "look": handle, "material": drawn["finish"] },
			)
		for flip in [false, true]:
			PixelArt.render_turned(
				drawn["painter"], _flat_size(), drawn["body"], angle,
				{
					"gun": gun, "look": handle, "flat": true, "flip": flip,
					"material": drawn["finish"],
				},
			)


## The held art of `size` centered at `centre`, muzzle along `facing`, in its look's painter: lit
## for the nearest lighting step, drawn rotated to the exact angle.
func _draw_art(canvas: CanvasItem, centre: Vector2, facing: Vector2, size: Vector2) -> void:
	var angle := facing.angle() - PI * 0.5
	var drawn := look()
	var tex := PixelArt.render_turned(
		drawn["painter"], size, drawn["body"], PixelArt.snap_angle(angle),
		{ "gun": gun, "look": _look_handle(drawn), "material": drawn["finish"] },
	)
	_note_drawn(tex)
	canvas.draw_set_transform(centre, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
