class_name CharacterStanceConfig
## How a hand and its weapon are held (scenes/character/): the stance table, the ease between
## stances, the muzzle ahead of the hand, the weapon raised off a wall, and the weapon's kick on the
## hand (the recoil spring, one-handed recoil). A `class_name` holder of `static var`s, read as
## `CharacterStanceConfig.<name>`; there is no instance and no autoload.

## A long gun fired one-handed (its user's free hand over the eyes, `Character.weapon.one_handed()`)
## kicks this many times harder.
static var one_hand_recoil: float = 1.75
## A hand rests `forward` px ahead of the body center and `lateral` px out to its own side, in the
## frame it chases the aim in; its grip is `height` body radii off the floor (the arm bends to reach
## it) and its elbow bends toward `elbow_pole` (out, forward, up). `swing` is the walk's
## fore-and-aft swing of a free hand (px); a `steady` hand follows the aim closely and only drifts
## sideways; `recoil_share` is how much of a kick the hand feels when the other hand fires; an
## optional `waver` (px, 0 when absent) wanders a steady hand slowly either way across its frame.
static var stances: Dictionary = {
	&"relaxed": { "forward": 2.0, "lateral": 13.0, "height": 3.7, "swing": 9.0, "steady": false,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.2, -0.8, -0.2) },
	# Running: both arms hang and pump at the sides whatever is held (a pistol is just carried in
	# its hand).
	&"run": { "forward": 2.0, "lateral": 10.5, "height": 4.9, "swing": 16.0, "steady": false,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.05, -0.8, 0.0) },
	&"guard": { "forward": 11.5, "lateral": 7.0, "height": 6.0, "swing": 1.5, "steady": false,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.35, -0.1, -1.0) },
	&"aim": { "forward": 27.0, "lateral": 2.0, "height": 6.0, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.3, 0.0, -1.0) },
	&"support": { "forward": 27.0, "lateral": 2.0, "height": 6.0, "swing": 0.0, "steady": true,
		"recoil_share": 0.7, "elbow_pole": Vector3(0.6, -0.1, -1.0) },
	# A grenade's wind-up: the throwing arm drawn back behind the shoulder and up, before it is
	# thrown forward.
	&"throw": { "forward": -6.0, "lateral": 15.0, "height": 6.4, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.6, -0.8, -0.5) },
	# Reloading: the supporting hand drops to the belt for the next magazine.
	&"reload": { "forward": 1.0, "lateral": 11.5, "height": 4.4, "swing": 0.0, "steady": false,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.1, -0.8, -0.2) },
	# A submachine gun: the butt on the right shoulder, the grip hand just ahead of it and the other
	# hand out on the shroud. Both hands lie on one line along the barrel (hand 0 at +lateral, hand
	# 1 at -lateral; both land on the character's right), 9 px right of the aim.
	&"smg_grip": { "forward": 12.0, "lateral": 9.0, "height": 5.8, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.5, -0.1, -1.0) },
	&"smg_fore": { "forward": 24.0, "lateral": -9.0, "height": 5.8, "swing": 0.0, "steady": true,
		"recoil_share": 0.8, "elbow_pole": Vector3(0.4, 0.0, -1.0) },
	# An assault rifle: held in front of the face as if looking down the sight, the butt in the
	# right shoulder, the grip hand just ahead of it and the other hand reaching out along the
	# handguard, both on the barrel line 5 px right of the aim.
	&"rifle_grip": { "forward": 15.0, "lateral": 5.0, "height": 5.9, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.8, -0.1, -1.0) },
	&"rifle_fore": { "forward": 27.0, "lateral": -5.0, "height": 5.8, "swing": 0.0, "steady": true,
		"recoil_share": 0.8, "elbow_pole": Vector3(0.4, 0.0, -1.0) },
	# A long gun raised off a wall or object (butt still on the shoulder, barrel pointed up): both
	# hands drawn in toward the chest, the front one higher as the barrel tips up.
	&"ready_grip": { "forward": 8.0, "lateral": 9.0, "height": 6.4, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.8, -0.1, -1.0) },
	&"ready_fore": { "forward": 14.0, "lateral": -9.0, "height": 6.8, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.5, 0.0, -1.0) },
	# Blinded by a flash: the free hand over the eyes, the palm on the face, the elbow down and out
	# (the Character picks it for the hand the held item does not hold its weapon in;
	# docs/grenades.md G13).
	&"eyes": { "forward": 9.0, "lateral": 0.0, "height": 7.0, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.7, -0.2, -1.0) },
	# A gun held in one hand while the other covers the eyes: the arm out, the gun low, wandering
	# `waver` px either way across.
	&"one_hand": { "forward": 24.0, "lateral": 5.0, "height": 5.2, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.4, -0.1, -1.0), "waver": 3.0 },
}
## How fast a hand eases from one stance to another (1/s).
static var stance_ease: float = 12.0
## How far ahead of a hand its weapon's muzzle is (px): bullets leave there. The default for an item
## that does not say (`Item.muzzle_ahead()`); a long gun reaches further.
static var muzzle_ahead: float = 11.0
## How fast a long gun comes up off a wall (and back down) once its barrel touches (or leaves) it:
## the share of the way per second (8 = about an eighth of a second).
static var weapon_raise_speed: float = 8.0
## Clearance (px) a raised gun needs beyond the touching distance before it comes back down, so it
## does not flicker at the edge.
static var weapon_contact_margin: float = 6.0
## Recoil: how far a kick throws the hand back (px).
static var pose_recoil: float = 4.0
## Shoulder twist per kick (rad).
static var pose_recoil_twist: float = 0.08
## Recoil spring speed (rad/s).
static var pose_recoil_freq: float = 18.0
## Recoil spring damping.
static var pose_recoil_damping: float = 0.6
