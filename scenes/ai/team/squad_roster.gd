class_name SquadRoster extends RefCounted
## A squad's roster (`Squad.setup`, interface 21): its side, its members in spawn order, the human
## when the human leads it, how long it keeps its members' entry claims, and whether its AI leader
## ambushes the doorway an attack comes through. The match builder fills it
## (`MatchBuilder.build_squads`), one per side.

## The side's faction tag.
var faction: StringName = &""
## The side's characters in spawn order (the leader rule's tie-break).
var members: Array = []
## The human when the human leads the squad (null: the leader is the rule's, LD3).
var human: Node = null
## How long the squad keeps a member's entry claim, s: its NPCs' `callout_ttl`
## (`MatchBuilder.callout_ttl_of`); 0 keeps none.
var claim_ttl: float = 0.0
## Whether an AI leader of this squad orders its crew to ambush the doorway into its room an attack
## comes through (`squad_ambush.gd`): set for the defenders' side only; never run while the human
## leads.
var ambush_attacks := false
