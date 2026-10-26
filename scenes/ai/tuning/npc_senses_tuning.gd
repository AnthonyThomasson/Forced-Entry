class_name NpcSensesTuning extends Node
## What an NPC senses: the sight cone, the near-awareness bubble, the furniture it sees over, and
## what it hears (gunfire, and footsteps by gait). One topic node of the NPC's tunables, under its
## controller's `Tuning` hub (`NpcTuning.senses`), per NPC: its scene authors it (the presets'
## overrides), a test sets it as an indexed path (`tuning:senses:<name>`). Only exports.

## Whether sight is gated at all. Off = everything is visible (omniscient), for debugging.
@export var vision_enabled: bool = true
## Maximum distance (px) at which the NPC can see anything.
@export var view_distance: float = 2520.0
## Full angular width (degrees) of the forward view cone, centred on the NPC's facing (its aim).
@export var fov_degrees: float = 110.0
## Radius (px) of a 360° near-awareness bubble: things this close are sensed regardless of facing.
@export var awareness_radius: float = 48.0
## Coverage rating (0–100 height proxy) at or below which furniture is low enough to see OVER —
## tables, beds, islands, counters. Taller pieces (cabinets, wardrobes, fridges) and walls still
## block sight. Sight-only: line-of-fire and cover still treat every solid piece as an obstacle.
@export var see_over_coverage: float = 60.0
## Radius (px) within which a hit elsewhere is heard as gunfire (an investigation lead).
@export var hearing_radius: float = 900.0
## How far (px) the footsteps of a character not of the NPC's own faction are heard, through walls,
## by gait (`docs/hearing.md` H1): walking, running and crouched. A heard step is an investigation
## lead and a reason to suspect the room it came from.
@export var hear_walk: float = 250.0
@export var hear_run: float = 450.0
@export var hear_crouch: float = 100.0
