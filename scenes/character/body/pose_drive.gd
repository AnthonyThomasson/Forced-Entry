class_name PoseDrive extends RefCounted
## What drives a character's pose for one physics frame (`character_pose.gd`'s `update`): the aim,
## the walk, what each hand holds and does, and the stun. The character fills one each frame.

## The way the character aims (unit).
var facing := Vector2.RIGHT
## How it moves (px/s), and its top walking speed.
var velocity := Vector2.ZERO
var top_speed := 0.0
## Per hand: the stance it is held in (a `CharacterConfig.stances` name) and its punch's
## extension, 0 (resting) .. 1 (fully punched).
var stances: Array = []
var punch: Array = []
## The character's stun level (0..1; 0 while a ride poses it).
var stun := 0.0
