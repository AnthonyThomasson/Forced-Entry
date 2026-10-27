extends RefCounted
## AI PERCEPTION sub-domain — SNAPSHOT OPTIONS. Writes the option groups Von picks from: which
## hostile to fight, where to fire from, which flank side, how to close in or fall back, what to
## investigate, which room to search or explore and which furniture to use. Options are places and
## things, never verbs; each carries the facts that tell it from its siblings. A pure read of the
## event memory, the tactics geometry, the shared vocabulary and the knowledge handed in for the
## decision (`know`, set by `AgentSnapshot.build()`). `agent_snapshot.gd` calls it from `build()`.
## The grenade throws are `snapshot_throws.gd`'s and the leader's order `snapshot_orders.gd`'s.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const AgentSuspicion = preload("res://scenes/ai/perception/agent_suspicion.gd")
## How a doorway's option says why its room is suspect (docs/grenades.md G18), one phrase per
## `AgentSuspicion` reason, measured with tools/von_probe.py
## (tools/von_scenarios/stun_entry_*.json).
const SUSPECT_PHRASES := {
	AgentSuspicion.GUNFIRE: "gunfire heard there",
	AgentSuspicion.FOOTSTEPS: "footsteps heard there",
	AgentSuspicion.SHOT_FROM: "shots at you came from there",
	AgentSuspicion.ALLY_FIGHT: "an ally radioed a fight there",
	AgentSuspicion.SEEN_IN: "a hostile seen going in",
	AgentSuspicion.LOST_BY_DOOR: "a hostile lost by its doorway",
	AgentSuspicion.HEADING_IN: "a hostile seen heading in",
}

## The knowledge the perception hands in for this decision (see `AgentSnapshot.build()`).
var know := {}
## The shared vocabulary and tuning; see snapshot_vocab.gd.
var _v: SnapshotVocab
## The agent's event memory (read-only here); see agent_memory.gd.
var _memory: RefCounted
## The combat geometry; see agent_tactics.gd.
var _tactics: RefCounted
## The NPC's body, handed in once by `bind`.
var _character: Node
## The doorway geometry; see agent_entry.gd.
var _entry: RefCounted
## The doorway views and the walk round them; see agent_door_views.gd.
var _views: RefCounted
## Why a room is suspect; see agent_suspicion.gd.
var _suspicion: AgentSuspicion
## The allies' entry claims heard on the radio; see stack/claim_ledger.gd.
var _ledger: RefCounted


## Capture the shared vocabulary and the collaborators the groups read (`sources`). Called once by
## `AgentSnapshot.setup()`.
func setup(vocab: SnapshotVocab, sources: SnapshotSources) -> void:
	_v = vocab
	_memory = sources.memory
	_tactics = sources.tactics
	_entry = sources.entry
	_views = sources.views
	_suspicion = sources.suspicion
	_ledger = sources.ledger


## Hand in the NPC's body. Called once by `AgentSnapshot.bind()`.
func bind(character: Node) -> void:
	_character = character


## Which hostile to fight: one option per known hostile, with what makes it urgent or easy.
func hostile_group(ctx: Dictionary, hostiles: Array, analyses: Dictionary) -> Dictionary:
	var options: Array = []
	for t in hostiles.slice(0, _v.tuning.decision.max_options_per_level):
		var a: Dictionary = analyses[t["id"]]
		options.append({
			"id": "t_%d" % t["id"], "label": t["name"],
			"desc": " — ".join(_hostile_parts(ctx, t, a)),
			"bind": {
				"target": t["name"], "target_id": t["id"],
				"blinded": ("%s is blinded by a flash and cannot see you, or " % t["name"])
					if t.get("blind", false)
					else "",
			},
		})
	return { "summary": "", "options": options }


## What tells hostile `t` (geometry `a`) apart from the others, in a fixed order: its name, whether
## it is in sight, its distance and bearing, then its movement, aim, item, an attack, wounds, a
## flash, the line to it and the ally already on it. Only what tells the hostiles apart — common
## facts ("hostile") blur the match.
func _hostile_parts(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var parts: Array = [
		t["name"],
		"in sight" if t["visible"] else "last seen %s" % _v.recency(t["age"]),
		"%s, %s of you"
			% [_v.dist_band(self_pos.distance_to(t["pos"])), _v.compass(t["pos"] - self_pos)],
	]
	if (t.get("vel", Vector2.ZERO) as Vector2).length() >= _v.tuning.context.still_speed:
		parts.append(_v.move_text(t, self_pos))
	var aim := _v.aim_text(t, self_pos, ctx["allies"])
	if aim != "":
		parts.append(aim)
	if t.get("item", "") != "Pistol":
		parts.append("holding a %s" % t.get("item", "nothing"))
	if t["reason"] == "attacked you":
		parts.append("they attacked you")
	var wound := _v.wound_band(t.get("wound_dmg", 0.0))
	if wound != "":
		parts.append(wound)
	if _v.blind_text(t) != "":
		parts.append(_v.blind_text(t))
	parts.append("you have a clear shot at them"
			if a["line"]["clear"] and a["line"]["in_range"]
			else "your line to them is blocked")
	var fighting := _allies_on(ctx, t)
	if fighting != "":
		parts.append("%s is already on them" % fighting)
	return parts


## Reloading the gun: one option, offered only while a carried magazine would add rounds, so the
## planner takes it without asking (a lone option).
func reload_group(gun: int) -> Dictionary:
	var options: Array = []
	if gun >= 0 and _character.ammo.can_reload(gun):
		var text := "reload your %s" % _v.gun_noun(gun)
		options.append({ "id": "reload", "label": text, "desc": text })
	return { "summary": "a spare magazine is carried", "options": options }


## Where to fight hostile `t` from: this spot, firing spots around them named by place and cover,
## and an ambush in cover. Tactics has already dropped any spot the NPC would reach past a hostile
## or in the open under a hostile's eye.
func fire_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var f: Dictionary = a["fire"]
	var self_pos: Vector2 = ctx["self_pos"]
	var tpos: Vector2 = t["pos"]
	var options: Array = []
	var cap: int = _v.tuning.decision.max_options_per_level
	if not f["here"].is_empty():
		options.append(_spot_option(
			"fire_here",
			"where you stand",
			"fire from where you stand" + _v.room_suffix(self_pos),
			f["here"],
			false,
		))
	for s in f["spots"]:
		if options.size() >= cap - (0 if f["ambush"].is_empty() else 1):
			break
		var dir := _v.compass(s["point"] - tpos)
		var place := _spot_place(s, dir)
		var lead := "fire from %s%s" % [place, (", %s of them" % dir) if s["cover"] != "" else ""]
		options.append(_spot_option("fire_" + dir.replace("-", "_"), place, lead, s, true))
	if not f["ambush"].is_empty():
		options.append(_fire_ambush_option(t, f["ambush"], self_pos))
	return { "summary": _fire_summary(t, f), "options": options }


## The ambush option of hostile `t`'s fire group: wait behind the cover of ambush spot `amb` for
## them to show.
func _fire_ambush_option(t: Dictionary, amb: Dictionary, self_pos: Vector2) -> Dictionary:
	var cover: String = amb["cover"] if amb["cover"] != "" else "cover"
	var desc := ("wait in ambush behind the %s — you shoot when they show — %s"
			% [cover, _v.coming_text(t, self_pos)])
	if not amb["exposed_to"].is_empty():
		desc += " — also exposed to %s" % ", ".join(amb["exposed_to"])
	return {
		"id": "ambush", "label": "ambush behind the %s" % cover, "desc": desc,
		"params": { "point": amb["point"], "style": &"ambush" },
		"tags": { "inside": _v.is_inside(amb["point"]) },
	}


## The FIRE branch summary over hostile `t`'s fire spots `f`: where the best one is (where it
## stands, a spot around them, or an ambush), and how wounded they look.
func _fire_summary(t: Dictionary, f: Dictionary) -> String:
	var tpos: Vector2 = t["pos"]
	var summary := ""
	if not f["here"].is_empty():
		summary = "from where you stand"
	elif not f["spots"].is_empty():
		summary = "from %s" % _spot_place(f["spots"][0], _v.compass(f["spots"][0]["point"] - tpos))
	elif not f["ambush"].is_empty():
		summary = "once they show, from an ambush behind cover"
	var wound := _v.wound_band(t.get("wound_dmg", 0.0))
	if summary != "" and wound != "":
		summary += "; they %s" % wound.replace("looks", "look")
	return summary


## Which side to flank hostile `t` from: one option per reachable side other than the NPC's own.
func flank_group(t: Dictionary, a: Dictionary, rooms: Array) -> Dictionary:
	var tpos: Vector2 = t["pos"]
	var options: Array = []
	var open: Array = []
	for s in a["flanks"]:
		var room := HouseRooms.at(s["point"], rooms)
		options.append({
			"id": "side_" + s["side"],
			"label": "%s (%s)" % [
				SnapshotVocab.SIDE_WORDS[s["side"]],
				_v.room_name(room["type"]) if not room.is_empty() else "outside",
			],
			"desc": " — ".join(_flank_parts(s, tpos, room)),
			"params": { "point": s["point"] },
			"tags": _geo_tags(
				s,
				{
					"inside": not room.is_empty(), "held": s["held_by"] != "",
					"crosses": s["crosses"] != "", "no_shot": not s["clear_shot"],
					"heading": s["heading_toward"], "lane": s["ally_lane"] != "",
				},
			),
		})
		if (s["held_by"] == ""
				and s["crosses"] == ""
				and s["clear_shot"]
				and not s["heading_toward"]
				and s["ally_lane"] == ""):
			open.append(s)
	var inside_open: Array = open.filter(
		func(s): return not HouseRooms.at(s["point"], rooms).is_empty(),
	)
	return {
		"summary": _flank_summary(a["flanks"], open, rooms),
		"summary_inside": _flank_summary(a["flanks"], inside_open, rooms),
		"options": options,
	}


## What a flank side option says of side `s` (in `room`, {} outside) round a hostile at `tpos`:
## which side and where, who holds it, the shot and cover from there, the route, and what makes it
## risky.
func _flank_parts(s: Dictionary, tpos: Vector2, room: Dictionary) -> Array:
	var place: String = (("in the %s" % _v.room_name(room["type"]))
			if not room.is_empty()
			else "outside the house")
	var parts: Array = [
		"%s — %s of them, %s"
			% [SnapshotVocab.SIDE_WORDS[s["side"]], _v.compass(s["point"] - tpos), place],
		_v.side_status(s),
		"clear shot from there" if s["clear_shot"] else "line blocked from there",
		("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open",
		_v.route_text(s["route_len"], s["route_exposed"]) + " route",
	]
	if s["heading_toward"]:
		parts.append("they are moving toward that side")
	if not s["exposed_to"].is_empty():
		parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
	if s["ally_lane"] != "":
		parts.append("in %s's line of fire" % s["ally_lane"])
	return parts


## Punching hostile `t`: one option, offered only while they are point-blank
## (`SnapshotVocab.dist_band`'s point-blank band), so MELEE is never chosen from across a room.
func melee_group(self_pos: Vector2, t: Dictionary) -> Dictionary:
	var dist := self_pos.distance_to(t["pos"])
	var summary := "they are %s and hold a %s" % [_v.dist_band(dist), t.get("item", "nothing")]
	var options: Array = []
	if dist <= _v.tuning.combat.punch_range * 1.5:
		options.append({ "id": "punch", "label": "punch them", "desc": "punch them — " + summary })
	return { "summary": summary, "options": options }


## How to close in on hostile `t`: part-way along the route (with cover if any) or a straight rush.
func advance_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var options: Array = []
	for s in a["advance"]:
		var parts: Array = []
		var id := ""
		var label := ""
		if s.get("rush", false):
			id = "rush"
			label = "rush them"
			parts.append("rush straight at where they are" + _v.room_suffix(s["point"]))
			parts.append(_v.route_text(s["route_len"], s["route_exposed"]) + " route")
			parts.append("they hold a %s" % t.get("item", "nothing"))
		else:
			id = "advance_half" if s["fraction"] < 0.6 else "advance_close"
			label = "halfway to them" if id == "advance_half" else "close to them"
			parts.append(("advance halfway to them"
					if id == "advance_half"
					else "advance most of the way to them") + _v.room_suffix(s["point"]))
			parts.append(("cover close by (the %s)" % s["cover"])
					if s["cover"] != ""
					else "in the open")
			parts.append("clear shot from there" if s["clear_shot"] else "line blocked from there")
		if not s["exposed_to"].is_empty():
			parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
		options.append({
			"id": id, "label": label, "desc": " — ".join(parts), "params": { "point": s["point"] },
			"tags": _geo_tags(s, { "inside": _v.is_inside(s["point"]) }),
		})
	var summary := "they are %s, %s, holding a %s" % [
		_v.dist_band((ctx["self_pos"] as Vector2).distance_to(t["pos"])),
		_v.move_text(t, ctx["self_pos"]),
		t.get("item", "nothing"),
	]
	var wound := _v.wound_band(t.get("wound_dmg", 0.0))
	if wound != "":
		summary += ", %s" % wound
	if _v.blind_text(t) != "":
		summary += ", %s" % _v.blind_text(t)
	return { "summary": summary, "options": options }


## Where to fall back to: out of sight of every known threat first, then farther away; with cover,
## route and the ally a spot lies toward. Threats are the known hostiles, else where fire came from.
func retreat_group(ctx: Dictionary, hostiles: Array, known_rooms: Array, dmg: float) -> Dictionary:
	var threats: Array = hostiles.map(func(h): return h["pos"])
	if threats.is_empty() and _memory.under_fire():
		threats.append(_shot_origin(ctx, false))
	if threats.is_empty():
		return { "summary": "", "options": [] }
	var spots: Array = _tactics.retreat_positions(ctx, threats, known_rooms)
	spots.sort_custom(_retreat_before)
	var options: Array = []
	for s in spots:
		if options.size() >= _v.tuning.decision.max_options_per_level:
			break
		var named := _retreat_name(s)
		var id: String = named[0]
		var lead: String = named[1]
		if options.any(func(o): return o["id"] == id):
			continue
		var parts: Array = [
			lead,
			"out of every hostile's sight"
				if s["hidden"]
				else "farther from them, still in their sight",
			("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open",
			_v.route_text(s["route_len"], s["route_exposed"]) + " route",
		]
		options.append({
			"id": id, "label": lead.trim_prefix("fall back to ").trim_prefix("back off "),
			"desc": " — ".join(parts), "params": { "point": s["point"] },
			"tags": _geo_tags(s, { "inside": _v.is_inside(s["point"]), "hidden": s["hidden"] }),
		})
	var inside: Array = options.filter(func(o): return o["tags"]["inside"])
	return {
		"summary": _retreat_summary(options, dmg),
		"summary_inside": _retreat_summary(inside, dmg),
		"options": options,
	}


## The order retreat spots are offered in: out of every threat's sight first, then with cover close
## by, then the shortest route.
func _retreat_before(x: Dictionary, y: Dictionary) -> bool:
	if x["hidden"] != y["hidden"]:
		return x["hidden"]
	if (x["cover"] != "") != (y["cover"] != ""):
		return x["cover"] != ""
	return x["route_len"] < y["route_len"]


## A retreat spot's option id and its lead words, `[id, lead]`: toward the ally it lies by, into the
## room it is in, else behind the cover close by.
func _retreat_name(s: Dictionary) -> Array:
	if s.get("ally", "") != "":
		return ["fall_ally_" + str(s["ally"]).to_lower(), "fall back to %s" % s["ally"]]
	if s.get("room", "") != "":
		return [
			"fall_" + str(s["room"]).to_lower().replace(" ", "_"),
			"fall back to the %s" % s["room"],
		]
	return [
		"fall_cover",
		"back off behind the %s close by" % (s["cover"] if s["cover"] != "" else "cover"),
	]


## What to investigate: lost hostiles (where last seen, and where they were heading), gunfire and
## footsteps heard, where unseen shots came from, and allies' radio calls for support — freshest
## first. What makes a room suspect (`AgentSuspicion`: a hostile last seen in it, by its doorway or
## heading in, gunfire or footsteps heard in it, shots from it, an ally's fight in it) is not a lead
## when the room is one a doorway of ENTER leads into (`entered`, see `entry_rooms`; the snapshot
## hands it over only while a stun can be thrown): that room is entered, and the entry says why
## (docs/grenades.md G18). Beside the options it hands out `lead_pos`, the point of the freshest
## lead that places a hostile (every lead but an ally's support, over them all before the option
## cap), `Vector2.INF` with none: an INVESTIGATE decision radios it (the defenders' ambush rule).
func lead_group(ctx: Dictionary, hostiles: Array, entered := {}) -> Dictionary:
	var leads: Array = (_lost_leads(ctx, entered)
			+ _heard_leads(ctx, &"heard_gunfire", "gunfire", entered)
			+ _heard_leads(ctx, &"heard_footsteps", "footsteps", entered)
			+ _shooter_lead(ctx, hostiles, entered)
			+ _ally_leads(ctx, entered))
	# A lead checked more recently than the event behind it is spent (fresh news there is offered
	# again).
	leads = leads.filter(
		func(l): return not _memory.age_of(&"checked_lead", "id", l["id"]) < l["age"],
	)
	leads.sort_custom(func(x, y): return x["age"] < y["age"])
	var options: Array = []
	for l in leads.slice(0, _v.tuning.decision.max_options_per_level):
		options.append({
			"id": l["id"], "label": l["label"], "desc": l["desc"],
			"params": { "point": l["point"], "lead": l["id"] },
			"tags": { "inside": _v.is_inside(l["point"]) },
		})
	var summary := ""
	if not options.is_empty():
		summary = "%d lead%s (freshest: %s)" % [
			leads.size(),
			"" if leads.size() == 1 else "s",
			options[0]["desc"].get_slice(" — ", 0),
		]
	var placing := leads.filter(func(l): return not String(l["id"]).begins_with("lead_ally_"))
	var lead_pos: Vector2 = placing[0]["point"] if not placing.is_empty() else Vector2.INF
	return { "summary": summary, "options": options, "lead_pos": lead_pos }


## The leads of the hostiles the NPC has lost track of: where it last saw each, and where a moving
## one was heading; none for a hostile whose room is one of `entered`.
func _lost_leads(ctx: Dictionary, entered: Dictionary) -> Array:
	var leads: Array = []
	for c in know["lost"].filter(
			func(c): return not _entered_any(entered, _suspicion.lost_rooms(_v.rooms, c).keys()),
	):
		var moving: bool = (c["vel"] as Vector2).length() >= _v.tuning.context.still_speed
		leads.append({
			"age": c["age"], "id": "lead_seen_%d" % c["id"],
			"label": "where you last saw %s" % c["name"],
			"desc": "where you last saw %s, %s — %s — %s route%s" % [
				c["name"], _v.where(c), _v.recency(c["age"]),
				_v.route_band(_route_len(ctx, c["pos"])),
				("; they were moving %s" % _v.compass(c["vel"])) if moving else "",
			],
			"point": c["pos"],
		})
		if moving:
			var ahead: Vector2 = NavBuilder.snap(
				ctx["map"],
				c["pos"] + c["vel"] * minf(c["age"], _v.tuning.context.extrapolate_cap),
			)
			leads.append({
				"age": c["age"] + 0.01, "id": "lead_heading_%d" % c["id"],
				"label": "where %s was heading" % c["name"],
				"desc": "where %s was heading, %s — %s of where you last saw them — %s route" % [
					c["name"], _v.place(ahead), _v.compass(c["vel"]),
					_v.route_band(_route_len(ctx, ahead)),
				],
				"point": ahead,
			})
	return leads


## The leads of what the NPC heard, memory topic `topic` (`heard_gunfire` / `heard_footsteps`)
## worded as `what` (`gunfire` / `footsteps`): one per point heard, none in a room of `entered`.
func _heard_leads(ctx: Dictionary, topic: StringName, what: String, entered: Dictionary) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var leads: Array = []
	for rec in _memory.recall_aged(topic):
		var pos: Vector2 = rec["data"]["pos"]
		if _entered_at(entered, pos):
			continue
		leads.append({
			"age": rec["age"],
			"id": "lead_%s_%d_%d" % [what, floori(pos.x / 200.0), floori(pos.y / 200.0)],
			"label": "%s to the %s" % [what, _v.compass(pos - self_pos)],
			"desc": "%s heard to the %s, %s — %s — %s route" % [
				what, _v.compass(pos - self_pos), _v.place(pos), _v.recency(rec["age"]),
				_v.route_band(_route_len(ctx, pos)),
			],
			"point": NavBuilder.snap(ctx["map"], pos),
		})
	return leads


## The lead toward where the shots at the NPC came from, under fire with no hostile known: `[lead]`,
## or `[]` when the line back from the newest shot runs into a room of `entered` or the walk there
## ends where the NPC stands.
func _shooter_lead(ctx: Dictionary, hostiles: Array, entered: Dictionary) -> Array:
	var shot: Dictionary = _memory.recall(&"shot_from")
	if not _memory.under_fire() or not hostiles.is_empty():
		return []
	if not shot.is_empty() and _entered_any(entered, AgentSuspicion.shot_rooms(_v.rooms, shot)):
		return []
	var from: Vector2 = _memory.under_fire_from()
	var origin: Vector2 = _shot_origin(ctx)
	# The point toward the shots is measured from where the NPC stands, so reaching it never spends
	# it: one the walk to which ends where it stands (shots from beyond the walkable ground) is not
	# a lead, as for LOCATE (`AgentTactics.where_it_stands`).
	if _tactics.where_it_stands(ctx, origin):
		return []
	return [{
		"age": 0.0, "id": "lead_shooter", "label": "where the shots came from",
		"desc": "where the shots at you came from — the %s, just now" % _v.compass(from),
		"point": origin,
	}]


## The leads of the allies' combat calls on the radio: support each where it fights; none for a
## fight in a room of `entered`.
func _ally_leads(ctx: Dictionary, entered: Dictionary) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var leads: Array = []
	for c in ctx["callouts"]:
		if (not str(c.get("path", "")).begins_with("combat")
				or _entered_at(entered, c.get("target_pos", Vector2.INF))):
			continue
		var at: Vector2 = c.get("position", self_pos)
		var status: String = c.get("status", "")
		leads.append({
			"age": c["age"], "id": "lead_ally_%d" % c["id"], "label": "support %s" % c["name"],
			"desc": "support %s, %s — %s, %s of you — radio %s%s" % [
				c["name"], _v.place(at), c.get("label", "fighting"), _v.compass(at - self_pos),
				_v.recency(c["age"]), ("; " + status) if status != "" else "",
			],
			"point": NavBuilder.snap(ctx["map"], at),
		})
	return leads


## Whether world point `p` lies in a room of `entered` (the rooms a doorway of ENTER leads into).
func _entered_at(entered: Dictionary, p: Vector2) -> bool:
	return not entered.is_empty() and entered.has(HouseRooms.key_at(p, _v.rooms))


## Whether any of room keys `keys` is in `entered`.
func _entered_any(entered: Dictionary, keys: Array) -> bool:
	return not entered.is_empty() and keys.any(func(k): return entered.has(k))


## Under fire from someone the NPC cannot see: the one way to find them — toward where the shots
## came from. Empty unless under fire with no hostile known, and empty for shots from a room the NPC
## is outside of (the line back from the newest shot, `shot_from`, runs into a room it is not in: a
## barricaded shooter), which it does not walk into: GRENADE at the shots' origin
## (snapshot_throws.gd `shots_grenade_group`) or RETREAT instead. Empty too when the walk there ends
## where the NPC stands (within `AgentTactics.STRIDE`: the shots came from beyond the walkable
## ground, and the navmesh pulls the point back to it).
func shooter_group(ctx: Dictionary, hostiles: Array) -> Dictionary:
	if not _memory.under_fire() or not hostiles.is_empty() or _shots_from_a_room(ctx):
		return { "summary": "", "options": [] }
	var from: Vector2 = _memory.under_fire_from()
	var origin: Vector2 = _shot_origin(ctx)
	if _tactics.where_it_stands(ctx, origin):
		# The shots came from beyond the walkable ground: the walk toward them ends where it stands.
		return { "summary": "", "options": [] }
	var dir := _v.compass(from)
	return {
		"summary": "the shots came from the %s" % dir,
		"options": [
			{
				"id": "toward_shots", "label": "toward the shots",
				"desc": "move toward where the shots came from — the %s%s — %s route"
					% [dir, _v.room_suffix(origin), _v.route_band(_route_len(ctx, origin))],
				"params": { "point": origin }, "tags": { "inside": _v.is_inside(origin) },
			},
		],
	}


## Whether the line back from the newest shot at the NPC (`shot_from`) runs into a room the NPC is
## not in.
func _shots_from_a_room(ctx: Dictionary) -> bool:
	var shot: Dictionary = _memory.recall(&"shot_from")
	if shot.is_empty():
		return false
	var here := HouseRooms.key_at(ctx["self_pos"], _v.rooms)
	return AgentSuspicion.shot_rooms(_v.rooms, shot).any(func(key): return key != here)


## Which known room to search next: not-recently-searched first, then nearest; plus the front
## entrance (`entry_point`) while outside. With doorways to enter by (`entered`: the keys of the
## rooms they lead into), those rooms and the front entrance are left to ENTER.
func search_group(ctx: Dictionary, known_rooms: Array, rooms: Array, entered := {}) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var here := HouseRooms.at(self_pos, rooms)
	var candidates: Array = []
	var unsearched := 0
	for room in known_rooms:
		if (not here.is_empty() and room["key"] == here["key"]) or entered.has(str(room["key"])):
			continue
		var age: float = _memory.age_of(&"visited_room", "key", room["key"])
		var point: Vector2 = NavBuilder.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		var stale := age > _v.tuning.memory.search_ttl
		if stale:
			unsearched += 1
		candidates.append({
			"room": room,
			"age": age,
			"stale": stale,
			"point": point,
			"len": _route_len(ctx, point),
		})
	candidates.sort_custom(func(x, y):
		if x["stale"] != y["stale"]:
			return x["stale"]
		return x["len"] < y["len"])
	var options: Array = []
	# With doorways to enter by, ENTER offers the way in.
	if here.is_empty() and entered.is_empty() and know["entry_point"] != Vector2.ZERO:
		options.append({
			"id": "entrance", "label": "the front entrance",
			"desc": "the front entrance — %s route"
				% _v.route_band(_route_len(ctx, know["entry_point"])),
			"params": { "point": know["entry_point"] }, "tags": { "inside": false },
		})
	for c in candidates:
		if options.size() >= _v.tuning.decision.max_options_per_level:
			break
		options.append(_search_option(c))
	var summary := "%d of %d known rooms unsearched" % [unsearched, known_rooms.size()]
	if known_rooms.is_empty():
		summary = "find your way into the house and explore it"
	return { "summary": summary, "options": options }


## The option of a room to search, candidate `c` of `search_group`: the room, whether it is
## unsearched or when it was searched, and the route there.
func _search_option(c: Dictionary) -> Dictionary:
	var room: Dictionary = c["room"]
	return {
		"id": "room_%s" % room["key"], "label": "the %s" % _v.room_name(room["type"]),
		"desc": "the %s — %s — %s route" % [
			_v.room_name(room["type"]),
			"unsearched" if c["stale"] else "searched %s" % _v.recency(c["age"]),
			_v.route_band(c["len"]),
		],
		"params": { "point": c["point"], "look_around": true }, "tags": { "inside": true },
	}


## The doorways the NPC could enter a room by, for a tactical entry (ENTER): from outside the outer
## doors, from a room its doors into the next, each into a room it has not seen (named by direction
## only) or not searched lately. A doorway's place is the NPC's stack slot beside it (the lowest the
## radio leaves free, on the side the team stacks on, or its own when the way there crosses the
## doorway's view), out of the doorway's line of sight; the behaviour runs the entry from there.
## A room a hostile is suspected in first, then nearest; capped.
func entry_group(ctx: Dictionary, rooms: Array) -> Dictionary:
	if not know.get("entry_enabled", false):
		return { "summary": "", "options": [] }
	var self_pos: Vector2 = ctx["self_pos"]
	var here := HouseRooms.at(self_pos, rooms)
	var known: Dictionary = know["known_room_keys"]
	var why: Dictionary = _suspicion.rooms_suspected(rooms, know["lost"], ctx["callouts"])
	var picks: Array = []
	for e in _entry.entries_from(str(here.get("key", ""))):
		var pick := _entry_pick(ctx, e, known, why)
		if not pick.is_empty():
			picks.append(pick)
	picks.sort_custom(func(x, y):
		if x["suspect"].is_empty() != y["suspect"].is_empty():
			return not x["suspect"].is_empty()  # A room a hostile is suspected in first.
		return x["len"] < y["len"])
	var options: Array = []
	for p in picks.slice(0, _v.tuning.decision.max_options_per_level):
		options.append(_entry_option(p, rooms, self_pos, here))
	return { "summary": options[0]["desc"] if not options.is_empty() else "", "options": options }


## Doorway `e` as an entry the NPC could make (`known`: the room keys it knows, `why`: why each room
## is suspect): `{ e, status, point, slot, len, suspect }`, its place being the slot and side its
## entry's `begin` would take; {} for a room cleared lately, a doorway with no geometry, or no slot
## or place for this NPC there.
func _entry_pick(ctx: Dictionary, e: Dictionary, known: Dictionary, why: Dictionary) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var into: String = e["into"]
	var status := "unexplored"
	if known.has(into) or known.has(StringName(into)):
		if _memory.age_of(&"cleared_room", "key", into) <= _v.tuning.memory.search_ttl:
			return {}  # Cleared lately: nothing to clear.
		status = "unsearched"
	var g: Dictionary = _entry.geometry(e["id"], into, ctx["map"], ctx["space"])
	if g.is_empty():
		return {}
	# The slot and side its entry's `begin` would take, claiming now from where it stands, by the
	# stack's claim chain (`DoorStack.claim`), the side asked for its own from there.
	var stack: RefCounted = _ledger.stack(e["id"], g)
	var at: Dictionary = stack.claim(
		{ "id": ctx["self_id"], "slot": 0, "frame": GameClock.frame(), "pos": self_pos },
		func(_n): return _entry.stack_side_from(stack, self_pos, ctx["map"], ctx["space"]),
	)
	if not at["held"]:
		return {}  # A dead end already holding all it can (E20): no slot for this NPC there.
	var point: Vector2 = at["point"]
	if point == Vector2.INF:
		return {}  # A slot laid nowhere (no open floor nor tail past the wall): no place.
	return {
		"e": e, "status": status, "point": point, "slot": at["slot"],
		"len": _route_len(ctx, point),
		"suspect": why.get(into, []).map(func(w): return SUSPECT_PHRASES[w]),
	}


## The ENTER option of entry pick `p`: the doorway, named by the room it leads into once searched
## before, else by direction from `self_pos`; why its room is suspect (or its status) and the route.
## `here` is the room the NPC stands in ({} outside).
func _entry_option(p: Dictionary, rooms: Array, self_pos: Vector2, here: Dictionary) -> Dictionary:
	var e: Dictionary = p["e"]
	var room := HouseRooms.by_key(rooms, e["into"])
	var place := ("the doorway into the %s" % _v.room_name(room["type"])
			if p["status"] == "unsearched"
			else "the doorway to the %s" % _v.compass((e["pos"] as Vector2) - self_pos))
	return {
		"id": e["id"], "label": place,
		"desc": " — ".join([place]
				+ (p["suspect"] if not p["suspect"].is_empty() else [p["status"]])
				+ ["%s route" % _v.route_band(p["len"])]),
		"params": {
			"opening": e["id"],
			"into": e["into"],
			"point": p["point"],
			"slot": p["slot"],
		},
		"tags": { "inside": not here.is_empty() },
	}


## The keys of the rooms the doorways of an `entry_group` lead into: those are entered by ENTER, not
## walked into.
static func entry_rooms(entries: Dictionary) -> Dictionary:
	var out := {}
	for opt in entries.get("options", []):
		out[str(opt["params"]["into"])] = true
	return out


## Unexplored parts of the house (rooms not yet seen), named by direction only — the NPC doesn't
## know what they are. One per compass direction, nearest first, at most two. A room a doorway of
## ENTER leads into (`entered`) is left to it.
func explore_group(ctx: Dictionary, rooms: Array, entered := {}) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var known: Dictionary = know["known_room_keys"]
	var by_dir := {}
	for room in rooms:
		if known.has(room["key"]) or entered.has(str(room["key"])):
			continue
		var point: Vector2 = NavBuilder.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		var dir := _v.compass(point - self_pos)
		var dist := self_pos.distance_to(point)
		if not by_dir.has(dir) or dist < by_dir[dir]["dist"]:
			by_dir[dir] = { "room": room, "point": point, "dist": dist }
	var picks: Array = by_dir.values()
	picks.sort_custom(func(x, y): return x["dist"] < y["dist"])
	var options: Array = []
	for p in picks.slice(0, 2):
		var dir := _v.compass(p["point"] - self_pos)
		options.append({
			"id": "explore_" + dir.replace("-", "_"), "label": "unexplored %s" % dir,
			"desc": "an unexplored part of the house to the %s — %s route"
				% [dir, _v.route_band(_route_len(ctx, p["point"]))],
			"params": { "point": p["point"], "look_around": true }, "tags": { "inside": true },
		})
	return { "summary": "explore the house", "options": options }


## The object interactions the NPC knows of: one option per DISTINCT action label, pointing at the
## nearest known object offering it (item-gated). Not capped — Von ranks them against the goal.
func interaction_group(self_pos: Vector2) -> Dictionary:
	var known_objs: Dictionary = know["known_object_ids"]
	var nearest := {}  # action label -> nearest known object + its spec (+ squared distance).
	for obj in know["interactables"]:
		if not is_instance_valid(obj) or not known_objs.has(obj.get_instance_id()):
			continue
		var d: float = obj.global_position.distance_squared_to(self_pos)
		for spec in obj.get_interactions():
			var needed: int = spec.get("requires_item", 0)
			if needed != 0 and not _character.inventory.has_item(needed):
				continue
			var label: String = spec.get("label", spec.get("id", ""))
			if not nearest.has(label) or d < nearest[label]["d"]:
				nearest[label] = { "obj": obj, "id": spec.get("id", ""), "d": d }
	var options: Array = []
	for label in nearest:
		var obj = nearest[label]["obj"]
		options.append({
			"id": "do_%d_%s" % [obj.get_instance_id(), nearest[label]["id"]], "label": label,
			"desc": "%s%s" % [label, _v.room_suffix(obj.global_position)],
			"params": { "object": obj, "id": nearest[label]["id"] },
			"tags": { "inside": _v.is_inside(obj.global_position) },
		})
	var labels: Array = nearest.keys()
	var summary := ("use furniture: %s%s"
			% [", ".join(labels.slice(0, 4)).to_lower(), ", …" if labels.size() > 4 else ""])
	return { "summary": summary if not labels.is_empty() else "", "options": options }


## Named places to go: each known room (except this one) and the NPC's starting position.
func room_group(ctx: Dictionary, known_rooms: Array, rooms: Array) -> Dictionary:
	var here := HouseRooms.at(ctx["self_pos"], rooms)
	var options: Array = []
	for room in known_rooms:
		if not here.is_empty() and room["key"] == here["key"]:
			continue
		var point: Vector2 = NavBuilder.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		options.append({
			"id": "room_%s" % room["key"], "label": "the %s" % _v.room_name(room["type"]),
			"desc": "the %s" % _v.room_name(room["type"]),
			"params": { "point": point, "arrive_room": room["key"] }, "tags": { "inside": true },
		})
	options.append({
		"id": "post", "label": "your starting position", "desc": "your starting position",
		"params": { "point": know["post"] }, "tags": { "inside": _v.is_inside(know["post"]) },
	})
	return { "summary": "", "options": options }


## `tags` plus the spot's geometry, kept for the routes debug overlay (`clear_shot`,
## `route_exposed`, `cover`, and the flank `ally_lane` / `held_by` / `crosses` names). The planner
## reads only the boolean tags a level's `drop_tags` names, so the extra keys are inert to
## decisions.
func _geo_tags(s: Dictionary, tags: Dictionary) -> Dictionary:
	for key in ["clear_shot", "route_exposed", "cover", "ally_lane", "held_by"]:
		if s.has(key):
			tags[key] = s[key]
	if s.has("crosses"):
		tags["crosses_name"] = s["crosses"]
	return tags


## One fighting-spot option: its place (`lead`), clear shot, cover, the route there (`moving`: a
## spot to go to rather than where the NPC stands) and other exposure.
func _spot_option(
	id: String,
	label: String,
	lead: String,
	s: Dictionary,
	moving: bool,
) -> Dictionary:
	var parts: Array = [lead]
	parts.append("clear shot" if s["clear_shot"] else "line blocked")
	parts.append(("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open")
	if moving:
		parts.append(_v.route_text(s["route_len"], s["route_exposed"]) + " route")
	if not s["exposed_to"].is_empty():
		parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
	return {
		"id": id, "label": label, "desc": " — ".join(parts),
		"params": { "point": s["point"], "style": &"peek_cover" },
		"tags": _geo_tags(s, { "inside": _v.is_inside(s["point"]) }),
	}


## A firing spot named by its place, `dir` being its bearing from the target: "behind the sofa in
## the kitchen" with cover close by, else "the kitchen, north of them" / "outside, north of them".
func _spot_place(s: Dictionary, dir: String) -> String:
	var room := HouseRooms.at(s["point"], _v.rooms)
	if s["cover"] != "":
		return "behind the %s %s" % [
			s["cover"],
			("in the %s" % _v.room_name(room["type"])) if not room.is_empty() else "outside",
		]
	return ("%s, %s of them"
			% [("the %s" % _v.room_name(room["type"])) if not room.is_empty() else "outside", dir])


## The FLANK branch summary over the `open` sides: how many, the best at a glance (Von still makes
## the pick).
func _flank_summary(flanks: Array, open: Array, rooms: Array) -> String:
	if flanks.is_empty():
		return ""
	var text := ""
	if open.is_empty():
		text = "every side is taken or out of reach"
	else:
		open.sort_custom(func(x, y): return _flank_rank(x) > _flank_rank(y))
		var best: Dictionary = open[0]
		var best_room := HouseRooms.at(best["point"], rooms)
		text = "%d free side%s; best: %s%s, %s route, %s" % [
			open.size(), "" if open.size() == 1 else "s", SnapshotVocab.SIDE_WORDS[best["side"]],
			(" via the %s" % _v.room_name(best_room["type"]))
				if not best_room.is_empty()
				else " outside",
			_v.route_text(best["route_len"], best["route_exposed"]),
			"cover" if best["cover"] != "" else "in the open",
		]
	return text


## How good an open flank looks at a glance (for the summary's "best" only — Von makes the pick).
func _flank_rank(s: Dictionary) -> int:
	return (int(s["clear_shot"]) * 4 + int(s["cover"] != "") * 2 + int(not s["route_exposed"])
			+ int(s["route_len"] <= _v.tuning.context.route_buckets.x))


## The RETREAT branch summary over `options` (best first): whether anywhere hides the NPC, the best
## spot, and how hurt it is.
func _retreat_summary(options: Array, dmg: float) -> String:
	if options.is_empty():
		return ""
	var best: Dictionary = options[0]
	return "best: %s, %s; you are %s" % [
		best["label"],
		"out of their sight"
			if best["tags"]["hidden"]
			else "farther from them, still in their sight",
		_v.health_band(dmg),
	]


## The world point to investigate when under fire from an unseen shooter:
## `tuning.context.investigate_distance` px from the NPC toward where the shots came from, snapped
## onto the navmesh unless `snap_to_navmesh` is false (the retreat group wants the raw direction as
## a threat position, not a reachable spot).
func _shot_origin(ctx: Dictionary, snap_to_navmesh := true) -> Vector2:
	var from: Vector2 = _memory.under_fire_from()
	var reach: float = _v.tuning.context.investigate_distance
	var p: Vector2 = (ctx["self_pos"] as Vector2) + from.normalized() * reach
	return NavBuilder.snap(ctx["map"], p) if snap_to_navmesh else p


## The length (px) of the route the NPC will walk from where it stands to `p`: the one that keeps
## out of the doorway views when it would take it (`AgentDoorViews.walk_route`, E18), else the plain
## one.
func _route_len(ctx: Dictionary, p: Vector2) -> float:
	return float(_views.walk_route(ctx["self_pos"], p, ctx["map"], ctx["space"])["len"])


## The ally (perceived near the target, or calling it on the radio) already fighting hostile `t`.
func _allies_on(ctx: Dictionary, t: Dictionary) -> String:
	for c in ctx["callouts"]:
		if c.get("target_id", 0) == t["id"]:
			return c["name"]
	for a in ctx["allies"]:
		if (a["pos"] as Vector2).distance_to(t["pos"]) <= _v.tuning.tactics.flank_ally_radius * 0.5:
			return a["name"]
	return ""
