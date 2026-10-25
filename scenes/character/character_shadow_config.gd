class_name CharacterShadowConfig
## The body's shadows (scenes/character/): the living body's light occluder (an oval of depth, width
## and sides) and the fallen body's drawn floor shadow. A `class_name` holder of `static var`s, read
## as `CharacterShadowConfig.<name>`; there is no instance and no autoload.

## The living body's shadow footprint, in its radius: an oval `depth` deep along its facing
## and `width` across the shoulders (half-axes), as a `sides`-gon. A dead body casts
## none (a 2D occluder has no height: a body lying on the floor would throw a shadow as long as a
## wall's).
static var depth: float = 0.72
static var width: float = 1.05
static var sides: int = 10
## A fallen part's floor shadow shift per px of height (matches the standing drop shadow).
static var body_shadow_per_height: float = 0.03
