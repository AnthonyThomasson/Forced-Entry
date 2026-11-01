class_name ObjectFadeConfig
## How an overhang that fades under a character fades (overhang_visuals.gd): a definition's
## `overhang` with `fade_under: true` drops to `alpha` over `seconds` while any node of the group
## `characters` stands inside its rect, and comes back to opaque over the same time when none does.
## A `class_name` holder of `static var`s, read as `ObjectFadeConfig.<name>`; there is no instance
## and no autoload.

## The overhang's opacity while someone is under it.
static var alpha: float = 0.25
## Seconds to fade to `alpha` and to come back.
static var seconds: float = 0.15
