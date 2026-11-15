class_name ObjectMeshStateConfig
## Objects domain, the state a furniture mesh shows (`furniture_rig.gd`; `domain-art/meshes.md`): a
## `class_name` holder of `static var`s, read as `ObjectMeshStateConfig.<name>` (ADR 0003).

## How strongly a lit glow part glows by default (the hot ring), and the dimmer bulb and screen.
static var glow_strength: float = 1.0
static var bulb_strength: float = 0.6
static var screen_strength: float = 0.6
## The neon of an awning, a tube or a sign, the sodium lens of a street lamp, the lit window of a
## fridge or a vending machine and the LEDs of a rack, each its own strength.
static var neon_strength: float = 1.0
static var lens_strength: float = 0.9
static var window_strength: float = 0.5
static var led_strength: float = 0.8
## A bed's blanket while someone lies on it: its height scale (1 is raised), and how many frames
## pass between two looks.
static var occupied_blanket_scale: float = 0.25
static var occupied_every: int = 6
