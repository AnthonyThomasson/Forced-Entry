extends RefCounted
## AI PERCEPTION sub-domain — ENTRY GEOMETRY's slots, a part the entry geometry holds as `slots`:
## where a stack may stand and walk at a doorway (`docs/tactical-entry.md` E20). Built once by
## `AgentEntry`, it holds nothing of it: the geometry it reads is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry geometry this part is one of, handed in at the call (never held: it holds the part).
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")


## Whether point `p` is ground a stack going in by `g` may walk on its way to a slot (E20): on the
## stack side of the doorway's wall, in the room the stack stands in (or out in the open), and with
## a body there clear of every other doorway's funnel (by `SLOT_BODY` past its jambs).
func on_stack_side(entry: AgentEntry, g: Dictionary, p: Vector2) -> bool:
	var c := {
		"id": g["id"], "pos": g["pos"], "out": g["out"], "along": g["along"],
		"half": float(g["width"]) * 0.5, "from": str(g.get("from", "")),
		"from_rect": g.get("from_room", Rect2()),
	}
	if not entry._in_stack_side(c, p):
		return false
	for f: Dictionary in entry._door_frames():
		var rel: Vector2 = p - (f["pos"] as Vector2)
		if (f["id"] != c["id"]
				and absf(rel.dot(f["along"])) < float(f["half"]) + AgentEntry.SLOT_BODY
				and absf(rel.dot(f["out"])) < StackClaim.FUNNEL_DEPTH):
			return false
	return true
