class_name CharacterRiseConfig
## Rise to fire (scenes/character/, #194 D7 and D7a, `docs/cover-and-stance.md` P6): how a ducked
## character that fires behind cover rises over it. A `class_name` holder of `static var`s, read as
## `CharacterRiseConfig.<name>`; there is no instance and no autoload.

## How far (px) from the body's centre a piece of cover counts as the cover the character is behind:
## the duck's muzzle line is judged blocked only by what it meets within this reach (a far obstacle
## is not its cover). About 1.4 m.
static var reach: float = 60.0
## How far (px) past where its line first meets a piece of cover the line is still judged against
## that piece: the depth of the cover, so a part at the back of it (a counter's backsplash) counts.
## About 1.9 m.
static var cover_depth: float = 80.0
## Seconds a character takes to rise before its first shot: it is already exposed (its body is the
## risen pose's) but holds its fire this long.
static var rise_time: float = 0.2
## Seconds a risen body stays risen after the last time it judged a round it could fire (the shot
## itself, or the rise it waits to fire in), before it drops back to the duck, so a burst and a held
## trigger do not flicker. A slow gun holds it longer: at least its time between rounds plus
## `dwell_margin`.
static var dwell: float = 0.6
## Seconds past a gun's time between rounds a rise is held for, so the gun's next round finds the
## body still risen however slow the gun is.
static var dwell_margin: float = 0.2
