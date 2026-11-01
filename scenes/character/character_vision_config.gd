class_name CharacterVisionConfig
## The character's sight (scenes/character/): what any character sees, the numbers the Vision
## domain draws a view by when it is made for one (`docs/player-vision.md` V1). They are the NPCs'
## default sight (`NpcSensesTuning`), so a human sees what the NPCs see. A `class_name` holder of
## `static var`s, read as `CharacterVisionConfig.<name>`, handed out through `Character.sight()`;
## there is no instance and no autoload.

## The full width of the forward view cone round the character's `facing`, degrees.
static var fov_degrees: float = 110.0
## How far it sees, px.
static var view_distance: float = 2520.0
## The radius of the near bubble all round it, which sees whichever way it faces, px.
static var awareness_radius: float = 48.0
## The `coverage` (0 to 100, the Objects height proxy) at or below which a piece is looked over
## (tables, beds, counters); a taller one (a wall, a wardrobe) breaks the line of sight.
static var see_over_coverage: float = 60.0
