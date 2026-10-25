class_name DentLimits extends RefCounted
## How deep one body caves under a hit (`Deformation.new_impact`): the deepest one dent goes and
## whether a hard hit carves a missing piece. The defaults are furniture's (`Deformable`'s own knob
## defaults, which Objects' wall keeps); a small body (a character) sets softer values.

## The deepest a single dent caves, px.
var max_depth: float = PhysicsConfig.deform_max_depth
## Whether a hit of `PhysicsConfig.deform_chunk_damage` or more carves a jagged missing piece.
var allow_chunks: bool = true
