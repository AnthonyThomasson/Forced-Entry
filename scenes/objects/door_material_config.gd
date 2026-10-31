class_name DoorMaterialConfig
## What a door is made of (Objects domain, scenes/objects/door/): per material its hit points, its
## penetration (how far a round is slowed going through, `get_surface().penetration`), its latch,
## the factor each kind of hit counts against its hit points by and the surface material its hits
## sound and throw debris as. `docs/doors.md` DR9, DR10, DR13; the numbers answer the research
## (`docs/research/doors-in-room-entry.md` §3, §4): an interior door is concealment, not cover,
## steel stops a pistol and not a rifle, a hollow door gives to a second kick and falls to a
## fourth, a solid one holds five, no kick opens a steel one.
##
## A `class_name` holder of `static var`s, read as `DoorMaterialConfig.<name>`; there is no instance
## and no autoload.

## Per material id (`hollow`, `solid`, `steel`, `glass`):
##   hp            hit points of the leaf; at 0 it is knocked down.
##   penetration   0..100, the surface rating of a round (the door's coverage is always 100).
##   latch_hp      what the kicks and blasts from the side it swings away from must wear off the
##                 latch before it gives (counted in the damage of the strikes themselves: a kick
##                 deals 14, a frag up to 60).
##   kicks_latch   whether a kick wears the latch (a boot cannot move a steel door's bolt; a blast
##                 does).
##   round_factor, melee_factor, kick_factor, blast_factor   the share of a hit's damage that
##                 comes off the hit points, by the kind of hit.
##   sound         the surface material of its hits (debris, impact sounds); `broken_sound`, when
##                 present, replaces it once the glass panes have shattered.
##   weight        its mass.
static var materials: Dictionary = {
	"hollow": {
		"hp": 80.0, "penetration": 10.0, "latch_hp": 20.0, "kicks_latch": true,
		"round_factor": 1.0, "melee_factor": 1.0, "kick_factor": 1.5, "blast_factor": 1.5,
		"sound": "wood", "weight": 30.0,
	},
	"solid": {
		"hp": 250.0, "penetration": 45.0, "latch_hp": 60.0, "kicks_latch": true,
		"round_factor": 0.8, "melee_factor": 0.5, "kick_factor": 1.0, "blast_factor": 1.2,
		"sound": "wood", "weight": 60.0,
	},
	"steel": {
		"hp": 1200.0, "penetration": 90.0, "latch_hp": 50.0, "kicks_latch": false,
		"round_factor": 0.5, "melee_factor": 0.1, "kick_factor": 0.05, "blast_factor": 1.0,
		"sound": "metal", "weight": 120.0,
	},
	"glass": {
		"hp": 80.0, "penetration": 5.0, "latch_hp": 20.0, "kicks_latch": true,
		"round_factor": 1.0, "melee_factor": 1.0, "kick_factor": 1.5, "blast_factor": 1.5,
		"sound": "glass", "broken_sound": "wood", "weight": 30.0,
	},
}
