# The player's view is a domain of its own, and the sight ray lives in General

What the human sees (the cone, the memory of what it has seen, the greyscale outside, nothing that moves out of view; issue #168,
`docs/player-vision.md`) is a seventeenth domain, `scenes/vision/`, a leaf like Lighting: it imports only General and reads the
viewer and the world duck-typed. The line of sight it casts is the NPCs' own, so that rule moved from AI perception to General
(`SightRay`, with `ViewLayers`, `SeenArea` and two new `DrawLayers` rungs, interface 11), and both domains cast through it. A reader
who meets the code will ask both.

## A domain, not a part of Lighting or the UI

Lighting already owns occluders and light masks, and the cone looks like a light: a polygon from an eye. It is not one. A light is
recomputed from the world each frame; the view must also keep what it showed (the memory), draw what the capture of the world
looked like, and tell other domains what to skip drawing. It is neither a HUD (the UI reads Character and AI by path and signal and
draws screen widgets) nor Lighting's. As its own leaf it owns one node, `PlayerView`, and its one caller is `MatchBuilder`
(interface 25), so a test can put the view on any character, an NPC included, and run the real cost.

## The sight rule in General, not imported from the AI

The view has to see as the NPCs do (a table is looked over, a wall is not, a glass-panel door is looked through). Importing the AI's
`AgentVision` into Vision would make a leaf depend on the AI and the AI's perception on a node of the view. The rule is a few lines
over `intersect_ray` and the hittable contract's `get_surface()`, so it moved to General, and the NPCs' answers are held unchanged
by every AI vision test. General also holds what the other domains must set for the view without knowing it: the visibility bits
(`ViewLayers`), the two rungs the view and the overlays draw at, and `SeenArea`, the part of the world shown live, which Character
and Physics read to skip a repaint.

## What the view does not do, and why

- **It hides no node.** A character outside the cone is not drawn because the composite covers it and, to save the CPU, because its
  repaint is skipped (`SeenArea`); its node stays shown. Hiding unseen characters' nodes would also un-draw the dead bodies, which
  the memory keeps.
- **It does not draw the still world once.** The plan was a main viewport that draws only what moves and a capture that draws the
  rest. Godot 4.4 draws a canvas item in a viewport only if the item and every ancestor share a bit with the viewport's
  `canvas_cull_mask`, so that would have removed the HUD, the world root and every child of a moving thing, and it would have
  needed every still subtree relabelled across seven domains, failing only in a window. The main viewport draws every bit; the
  capture leaves out the moving things and the overlays.
- **It does not rely on a cull mask for a light.** A `Light2D` is not culled by the mask, so the flash lights live under a
  `CanvasLayer` the capture does not draw (`docs/lighting.md`).
- **It does not rebuild the cone on a simple rule.** "The eye, the facing and the blockers' transforms are the same" skipped frames
  a fresh rebuild would have drawn differently (0.7 to 6 % of them: a dent or a wall re-cut changes a shape with no move of its
  body). The rebuild is driven by what the cone reads (`ViewWatch`), with a forced rebuild every ten frames as a backstop, and a
  test holds every skipped frame to a fresh rebuild vertex for vertex.
