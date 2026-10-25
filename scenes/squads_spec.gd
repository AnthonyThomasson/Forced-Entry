class_name SquadsSpec extends RefCounted
## The squads a match is built over (`MatchBuilder.build_squads` / `squads_over`, interface 23): its
## characters in spawn order, the house's doorways and rooms, the human and whether it leads, and
## how long each squad keeps its members' entry claims. Part of the composition root, beside the
## match builder; `populate` and the Testing world's declared squads fill it.

## The match's characters in spawn order (after `MatchBuilder.arm` has ranked them).
var members: Array = []
## The house's doorways (`WorldGen.get_openings`).
var openings: Array = []
## The house's rooms (`WorldGen.get_rooms`).
var rooms: Array = []
## The human, as the match spec names it (`{ node, side, lead }`; `{}` none): its side is led by it
## when `lead` says so.
var human: Dictionary = {}
## How long each squad keeps its members' entry claims, s; at `MatchBuilder.CLAIM_TTL_OF_NPCS` (any
## negative value), as long as the side's NPCs keep a callout (`MatchBuilder.callout_ttl_of`).
var claim_ttl: float = MatchBuilder.CLAIM_TTL_OF_NPCS
