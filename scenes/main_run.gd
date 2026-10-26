class_name MainRun
extends Resource
## The composition root's authoring surface for a run: the base match spec's knobs and the mode's
## defaults, an exported `Resource` Main builds per instance and holds as `main.run` (editable
## inline in Main's inspector). Main rewrites `spectator_mode` and `debug_overlays` as the setup
## window chooses, so they live on the one Main, not in a static holder, and go with its scene
## reload.

## Seed for the house layout; 0 = a new random seed each run, resolved to a concrete value at
## spawn so the whole run (house + NPC placement) reproduces from it. The seed is logged and can be
## re-entered in the setup window to pin a layout you like.
@export var house_seed: int = 0
## Force a specific floorplan (a key in HouseDefinitions); "" = pick one at random.
@export var force_plan: String = ""
## Distance from the player to the front entrance's center, straight up the screen.
@export var entrance_distance: float = 70.0
## How many defender NPCs to drop into the house (0 = none). Raise it to exercise coordinated
## flanking from the defending side.
@export var defender_count: int = 1
## How many invader NPCs to spawn outside the house (0 = none). They start together, in one group
## beside the front door (round a perimeter point only in a house with none; round the human
## invader when there is one).
@export var invader_count: int = 1
## Distance (px) beyond the house's outer edge the invaders' group point is drawn at in a house
## with no front door (inside the navmesh's outer band); every invader's spot stays within twice it
## of the rooms' bounds.
@export var invader_margin: float = 80.0
## Room (px) a character is dropped with: its centre stays this far from every solid furniture
## footprint and twice this from anyone already placed (the invaders' group is packed at it). A
## body spawned inside a piece is ejected along with it, and the piece's momentum flings the
## character across the map.
@export var spawn_clearance: float = 20.0
## Spectator match mode: run as an AI-only contest (the defenders vs the invaders) with no human
## player — frees the Player and its HUD, frames every NPC, and shows the match HUD. Off = the
## normal player-driven scene.
@export var spectator_mode: bool = true
## Which side a human player takes when there is one ("defender" / "invader"). The player joins that
## side on top of its NPC count, carrying the side's loadout.
@export var player_side: StringName = &"defender"
## Master switch for the AI debug overlays: off = every overlay is hidden and the in-game toggle bar
## is not built. This export is the default; on a fresh launch the saved `Settings.debug` (the
## settings page's Debug checkbox) takes over, while a scripted restart keeps this value.
@export var debug_overlays: bool = true
