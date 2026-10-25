class_name CharacterWardrobe extends Node
## How a character is drawn and what it wears (`character.gd`'s `wardrobe`, its `Wardrobe` child in
## `character_base.tscn`): its style, the variety within it, a police unit's rank (looks only), and
## the `Outfit` it wears (its armour and weight, and for the art its look). A Node, so a scene can
## author its style (`npc_defender.tscn`'s `merc`). Every change of the style, the seed or the rank
## bumps `revision`, which the visuals compare once a frame to re-resolve the look.

## The style it is drawn in (`docs/outfits.md`, styles; a key of `CharacterStyleConfig.styles`):
## `zenitex` or `trauma` (the invaders' police units), `merc` or `borg` (the defenders' crew). What
## it wears is drawn in the style, and its own variety (skin, hair, implants, the colours a defender
## found its garments in) is drawn from `look_seed`. Looks only: nothing it does changes. A
## character never given one is a `zenitex`. Set before `_ready` (as a prop) or with `set_style`.
@export var style: StringName = &"zenitex":
	set(v):
		style = v
		revision += 1
## The seed of its own variety within its style.
@export var look_seed: int = 0:
	set(v):
		look_seed = v
		revision += 1
## A police unit's rank marks: 0 a trooper, 1 the sergeant (chevrons on the shoulder), 2 the lead (a
## stripe across the helmet).
@export var rank: int = 0:
	set(v):
		rank = v
		revision += 1

## Bumped by every change of `style`, `look_seed` or `rank`: the visuals re-resolve the look when it
## moves.
var revision := 0
## What the character wears (Items domain; `outfit.set_ids(ids)`): its armour, its weight and, for
## the art, its look. A new one wears nothing (no armour, no weight).
var outfit := Outfit.new()


## Draw the character in `new_style` (a key of `CharacterStyleConfig.styles`) with its own variety
## from `seed_value`, and a police unit's `new_rank` (0 trooper, 1 sergeant, 2 lead): how Main
## styles a spawn (through `LoadoutConfig.apply`). Looks only.
func set_style(new_style: StringName, seed_value: int, new_rank := 0) -> void:
	style = new_style
	look_seed = seed_value
	rank = new_rank
