class_name SquadAmbushConfig
## The defenders' ambush rule's pacing (`squad_ambush.gd`), the same for every squad that runs it:
## how often an AI leader may move its crew's ambush to another doorway and how many members a
## re-order must reach. A `class_name` holder of `static var`s, read as `SquadAmbushConfig.<name>`;
## there is no instance and no autoload.

## Seconds of game time an ambush order stands before the leader may order another doorway.
static var reorder_gap := 8.0
## The fewest recipients (the rear guard left out) a re-order must have, or none is posted.
static var min_recipients := 2
