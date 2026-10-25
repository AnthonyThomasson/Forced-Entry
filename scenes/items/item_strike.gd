class_name ItemStrike extends RefCounted
## Items domain: the melee geometry of a held item, the item's `strike` part, which the character's
## hands read every physics frame through a blow: how the item swings round in it, where its
## striking end is, how much shorter and slower the blow is than a fist's and where the other hand
## holds on. Plain data, built once with its item (`Item._init`) and never replaced: a fist's are
## the defaults (the fist leads, nothing turns), and `GunItem._init` fills a long gun's (a
## `GunConfig` row with `raises_at_contact`) from its row and the values below, so its punch swings
## it nearly across the body, butt leading. It holds no reference to its item.

## How far (px) along a long gun's barrel from the weapon hand the support hand grips through a butt
## strike: toward the butt, so the other arm does not reach across the weapon hand.
const SUPPORT_GAP := -8.0
## How far (rad) a long gun turns in a butt strike: nearly across the body (105 degrees), the butt a
## little ahead of the muzzle.
const STRIKE_TURN := 1.833
## How far (px) short of a fist's reach a long gun's blow lands.
const STRIKE_SHORT := 5.0
## How many times slower than a fist a long gun is swung.
const LONG_TEMPO := 2.0

## How far (px) behind the weapon hand the striking end sits when held, which a blow swings round to
## lead with (a long gun's butt). 0 = the fist leads.
var ahead := 0.0
## How far (rad) the weapon turns about the weapon hand, outward from the body, by the end of a
## blow: short of a half turn, so it ends nearly across the body with the striking end a little
## ahead of the far end.
var turn := 0.0
## How much (px) shorter than a fist's the blow reaches: a weapon held in both hands cannot be
## thrown as far.
var short := 0.0
## How far (px) along the weapon from the weapon hand the other hand grips (negative: toward the
## striking end). It holds on as the weapon turns. 0 = it does not follow.
var support_gap := 0.0
## How many times slower than a fist the blow is thrown (a heavy weapon swings, it does not jab).
var tempo := 1.0
## The hand that holds the weapon (the item's `weapon_hand()`, set when the item is built): the
## weapon turns outward from the body on its side.
var hand := 0


## How far round the weapon has swung, 0 (held as usual) .. 1 (at `turn`), at a punch `amount` (0
## resting .. 1 fully thrown).
func swing(amount: float) -> float:
	return smoothstep(0.0, 0.6, amount) if ahead > 0.0 else 0.0


## The way the weapon points at a punch `amount` when held along `aim`.
func direction(aim: Vector2, amount: float) -> Vector2:
	return aim.rotated(turn * swing(amount) * (1.0 if hand == 0 else -1.0))


## Where the striking end is, relative to the weapon hand, when the weapon is held along `aim` at a
## punch `amount`.
func end(aim: Vector2, amount: float) -> Vector2:
	return -direction(aim, amount) * ahead


## How far (px) ahead of the weapon hand the striking end ends up at a full blow: the hands shorten
## the punch's extension by it, so a blow lands as far out as ever.
func forward() -> float:
	return ahead * maxf(-cos(turn), 0.0)
