extends RefCounted
## AI PERCEPTION sub-domain — what the leads and the entries a snapshot's group piece builds ahead
## of the walk read of the radio, kept to see whether it is out of date by the time the walk begins
## (`SnapshotDemand.forget_stale_groups`). A group's key is what it read when it began: the allies'
## combat calls (by ally, without their ages: time passing is no change) and, for the entries, the
## claims on the doorways' slots (`ClaimLedger.heard_key`); a later key that differs means a call or
## a claim came in, changed or lapsed since. Also holds the rooms the entries lead into, which the
## leads leave out while a stun can be thrown: derived from the entries, so it goes with them.

## The allies' entry claims heard on the radio; see stack/claim_ledger.gd.
var ledger: RefCounted
## The rooms a doorway of ENTER leads into (`SnapshotOptions.entry_rooms`), once worked out (null
## before).
var entered: Variant = null
## Group name -> the key it read when it began.
var _keys := {}


## What group `name` (`entries` or `leads`) reads of the radio, of the decision's context `ctx`:
## each ally's combat call by the ally's id, so the order the calls are listed in (a call radioed
## again moves to the end of the list) is no change.
func key(ctx: Dictionary, name: String) -> Dictionary:
	var calls := {}
	for c: Dictionary in ctx["callouts"]:
		if str(c.get("path", "")).begins_with("combat"):
			var said := c.duplicate()
			said.erase("age")
			calls[c["id"]] = said
	return { "calls": calls, "claims": ledger.heard_key() if name == "entries" else {} }


## Note what group `name` is about to read, when the re-read can find it out of date.
func note(ctx: Dictionary, name: String) -> void:
	if name == "entries" or name == "leads":
		_keys[name] = key(ctx, name)


## Whether group `name` read the radio as it is not now (`false` for one not noted).
func stale(ctx: Dictionary, name: String) -> bool:
	return _keys.has(name) and _keys[name] != key(ctx, name)


## Group `name` is forgotten: what was noted of it, and what is derived from it.
func forget(name: String) -> void:
	_keys.erase(name)
	if name == "entries":
		entered = null
