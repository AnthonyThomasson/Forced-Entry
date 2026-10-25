class_name SquadRoster extends RefCounted
## A squad's roster (`Squad.setup`, interface 21): its side, its members in spawn order, the human
## when the human leads it, and how long it keeps its members' entry claims. The match builder fills
## it (`MatchBuilder.build_squads`), one per side.

## The side's faction tag.
var faction: StringName = &""
## The side's characters in spawn order (the leader rule's tie-break).
var members: Array = []
## The human when the human leads the squad (null: the leader is the rule's, LD3).
var human: Node = null
## How long the squad keeps a member's entry claim, s: its NPCs' `callout_ttl`
## (`MatchBuilder.callout_ttl_of`); 0 keeps none.
var claim_ttl: float = 0.0
