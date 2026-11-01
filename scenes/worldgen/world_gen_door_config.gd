class_name WorldGenDoorConfig
## World Generation domain: the master switch for the doors a generated house is built with. A
## `class_name` holder of `static var`s, read as `WorldGenDoorConfig.<name>`; there is no instance
## and no autoload. Which doorways get a door, the swing and the start state are `DoorRules`.

## Whether HouseSpawner builds the house's doors (`docs/doors.md` DR2): on, as in a match; off, the
## doorways stay open archways (the test switch `worldgen.doors`).
static var enabled: bool = true
