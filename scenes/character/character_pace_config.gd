class_name CharacterPaceConfig
## How fast and how long a character goes (scenes/character/): running (speed, stamina, regen,
## resume, the least input that counts) and the outfit's weight slowing pace and tiring a run. A
## `class_name` holder of `static var`s, read as `CharacterPaceConfig.<name>`; there is no instance
## and no autoload.

## Walk-speed multiplier while running.
static var run_speed_mult: float = 1.7
## Seconds of continuous running a full stamina bar lasts.
static var run_stamina_seconds: float = 4.0
## Stamina (fraction of a full bar) regained per second when not running.
static var stamina_regen_per_sec: float = 0.2
## After running dry the character walks until stamina refills to this fraction.
static var run_resume_fraction: float = 0.3
## Smallest `movement.move_input` length that counts as moving, so holding run while standing spends
## nothing.
static var run_min_input: float = 0.1
## What a body carries at its tuned speed (kg: ordinary clothes); only the outfit's weight above it
## slows and tires.
static var outfit_free_weight: float = 2.0
## Share of the move speed lost per kg worn above `outfit_free_weight` (a full plated kit, 12 kg
## over: about 8%), floored at `outfit_speed_min`.
static var outfit_speed_per_kg: float = 0.0067
## The least share of the move speed an outfit's weight leaves.
static var outfit_speed_min: float = 0.6
## Extra share of stamina a run spends per kg worn above `outfit_free_weight` (the plated kit: about
## 1.3x).
static var outfit_stamina_per_kg: float = 0.025
