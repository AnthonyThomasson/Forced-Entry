class_name ObjectArtShellDecorConfig
## The loose things lying in a district shell's roofless interior (shell_decor_painter.gd): rebar,
## rubble, scaffold, cement bags and the damp stains running down a wall. The colours are as drawn:
## the painter is `ObjectArt.AS_GIVEN`. A `class_name` holder of `static var`s, read as
## `ObjectArtShellDecorConfig.<name>`; there is no instance and no autoload. A piece's catalogue
## `art_opts` overrides a painter knob for that piece only, keyed by the knob's name without its
## painter prefix (`shell_steel` -> `steel`).

## Rebar's steel, concrete rubble, scaffold tubes and boards, cement paper bags and wall damp.
static var shell_steel: Color = Color(0.44, 0.34, 0.28)
static var shell_concrete: Color = Color(0.5, 0.5, 0.52)
static var shell_tube: Color = Color(0.6, 0.62, 0.66)
static var shell_board: Color = Color(0.56, 0.44, 0.28)
static var shell_bag: Color = Color(0.62, 0.6, 0.55)
static var shell_damp: Color = Color(0.08, 0.1, 0.12)
