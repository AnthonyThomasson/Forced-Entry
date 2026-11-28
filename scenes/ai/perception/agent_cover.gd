extends RefCounted
## AI PERCEPTION sub-domain: what makes a piece COVER for an NPC, on real heights (`SightRay`,
## `BodyHeights`). Static, preloaded (no `class_name`), read by the tactics (`agent_tactics.gd`),
## the snapshot's line to a hostile and the entry posts. Cover is where a body ducked behind a piece
## is out of a threat's sight: `is_cover` says a piece is tall enough to hide a ducked head at all,
## `AgentVision.hiding_piece` whether it does from this threat at this spot
## (`docs/cover-and-stance.md` A1, A2).


## Whether `obj` is tall enough to hide behind at all: a solid whose top (the highest part of its
## twin, `SightRay.top_of`) reaches a ducked head (`BodyHeights.head_top(DUCK)`), a sofa's back, a
## counter, a wall; not a coffee table nor a dining table, which leave the head showing. A solid
## with no twin counts as a wall. A character is never cover: it is someone to shoot or protect, and
## it moves. Whether it is cover *here* is the line from the threat (`AgentVision.hiding_piece`): a
## tall enough piece covers a spot only where it stands between that eye and the ducked head.
static func is_cover(obj: Object) -> bool:
	if (obj == null
			or (obj is Node and obj.is_in_group(&"characters"))
			or not obj.has_method("get_surface")):
		return false
	return SightRay.top_of(obj) >= BodyHeights.head_top(BodyHeights.DUCK)


## The eye height (px) of the hostile `node` (its posture's), -1 (a standing body's) for none. An
## eye already read (a float, `viewer_of` a pinned contact) is itself.
static func eye_of(node: Variant) -> float:
	if node is float:
		return node
	if is_instance_valid(node) and node is Node2D and (node as Node2D).get("movement") != null:
		return SightRay.eye_of(node)
	return -1.0


## What `eye_of` reads for a contact: the eye it was pinned with (`AgentSnapshot._pinned`: one read
## of a hostile's posture for the two pieces of its analysis), else its node.
static func viewer_of(contact: Dictionary) -> Variant:
	return contact.get("eye", contact.get("node"))


## The eye height (px) a ray toward `contact` starts from (`viewer_of`).
static func eye_of_contact(contact: Dictionary) -> float:
	return eye_of(viewer_of(contact))


## The twin rid a ray toward `contact` excludes, as a one-element array: the one it was pinned with,
## else its node's (empty when it is gone or has no twin).
static func rids_of(contact: Dictionary) -> Array:
	if contact.has("rids"):
		return contact["rids"]
	var n = contact.get("node")
	return SightRay.exclude_of(n) if is_instance_valid(n) and n is Node else []
