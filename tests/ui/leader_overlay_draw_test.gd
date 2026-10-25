extends GameTest
## LD12 (`docs/leadership.md`): the squad-leaders debug overlay
## (`scenes/ui/overlays/leader_overlay.gd`, `LeaderOverlay`, drawn at `DrawLayers.ABOVE`). A global
## row of the overlay bar (`OverlayRegistry.LEADERS`, `show_leaders`, off by default); while it is
## on, a crown over each squad's living leader, moving to the next leader when the view names one. A
## decoupled observer: `watch(views)` takes the squads' `view()` callables and `drawn()` is what is
## shown (`[{ kind: "crown", point, node }]`), which this test reads.
##
## LD28: per squad it also draws, from `view()` only, the leash ring round the living leader
## (`{ kind: "leash", point, radius, node }`, the view's `leash`), each follower's follow spot
## (`{ kind: "spot", point, node }`) with a thin line from the follower to it
## (`{ kind: "line", from, to, node }`), from each member's `follow_spot` (none for one at INF), and
## the leader's trail as a dotted line (`{ kind: "trail", points }`, the view's `trail`). A crown is
## `{ kind: "crown", point, node }`. A view without those keys draws crowns alone.
##
## Fake squad views (plain data) over three puppets for the overlay itself; then the routing, which
## exists once (`MatchBuilder.set_overlay`): the test world's own squads (`s.squads()` over the
## three puppets, so one squad a side) and the bar's toggle through the test world's `set_overlay`,
## as the test runner's bar hands it; then Main's wiring: Main run whole in a world of its own
## (`tests/_main/main_probe.gd`), a Watch match of its own (`Main.start_match`: two invaders and a
## defender on a generated house, so two real squads), the overlay found under its `World`, and the
## bar's toggle through Main's `set_overlay`, the flag the bar hands it. Scripted Von (the first
## option offered). `Settings.path` points at a scratch file (a toggle is saved).

const Registry := preload("res://scenes/ui/overlays/overlay_registry.gd")
const LeaderOverlay := preload("res://scenes/ui/overlays/leader_overlay.gd")
const MainProbe := preload("res://tests/_main/main_probe.gd")
## The Watch match Main builds for its half: its house, and two invaders and a defender.
const MATCH_SEED := 12

## The two fake squads' views, as the overlay's `view` callables return them.
var _views := [{}, {}]


func describe() -> Dictionary:
	return {
		"name": "The squad-leaders overlay crowns each side's leader while on",
		"description": "show_leaders is a global overlay row, off by default; on, one crown over "
			+ "each squad's living leader, following a new leader; built with the squads of a "
			+ "match or a test world, the bar's toggle shows it in either (LD12).",
		"tags": ["ui", "overlay", "leadership"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.set_static(Settings, "path", "user://test_leader_overlay_settings.json")
	s.set_static(Settings, "overlays", {})
	s.set_static(Settings, "setup", {})
	s.set_static(Settings, "debug", Settings.debug)
	s.von_script([])
	s.actor(&"lead", &"puppet", Vector2(150, 300), { "faction": &"invader" })
	s.actor(&"next", &"puppet", Vector2(400, 200), { "faction": &"invader" })
	s.actor(&"boss", &"puppet", Vector2(700, 400), { "faction": &"household" })
	s.squads()


func run(t: TestContext) -> void:
	var rows: Array = Registry.ENTRIES.filter(func(e): return e["flag"] == Registry.LEADERS)
	t.check(
		rows.size() == 1 and not rows[0]["default"],
		"the overlay table has one show_leaders row, off by default",
	)
	t.check(
		Registry.is_global(Registry.LEADERS),
		"show_leaders drives one global overlay, not each NPC's",
	)

	var lead := t.actor(&"lead")
	var next := t.actor(&"next")
	var boss := t.actor(&"boss")
	var overlay: Node2D = LeaderOverlay.new()
	t.world.add_child(overlay)
	t.expect_eq(
		overlay.z_index,
		DrawLayers.ABOVE,
		"drawn above the standing world (DrawLayers.ABOVE)",
	)
	_views = [{ "leader": lead, "members": [] }, { "leader": boss, "members": [] }]
	overlay.watch([func(): return _views[0], func(): return _views[1]])
	await t.frames(2)
	t.check(overlay.drawn().is_empty(), "nothing is drawn while the overlay is off")

	overlay.show_leaders = true
	await t.frames(2)
	t.check(
		_crowned(overlay, lead) and _crowned(overlay, boss) and overlay.drawn().size() == 2,
		"on, one crown over each squad's leader (%s)" % str(overlay.drawn()),
	)

	_views[0]["leader"] = next
	await t.frames(2)
	t.check(
		_crowned(overlay, next) and not _crowned(overlay, lead),
		"when a view names a new leader the crown moves to it (%s)" % str(overlay.drawn()),
	)
	_views[1]["leader"] = null
	await t.frames(2)
	t.expect_eq(overlay.drawn().size(), 1, "a squad with nobody left to lead has no crown")
	await _check_follow(t, overlay, lead, next, boss)
	overlay.queue_free()
	await t.frames(1)

	await _check_test_world(t)
	await _check_main(t)


## The test world's squads (`s.squads()`) and the bar's toggle through the test world's
## `set_overlay`, as the test runner's bar hands it: one crown over each side's leader while on,
## none once off.
func _check_test_world(t: TestContext) -> void:
	var invaders := t.squad(&"invader")
	var household := t.squad(&"household")
	if not t.require(
			invaders != null and household != null,
			"premise: the test world built a squad a side",
	):
		return
	await t.frames(2)
	t.check(_crowns_in(t.world).is_empty(), "the test world's crowns are off by default")
	t.world.set_overlay(Registry.LEADERS, true)
	await t.frames(2)
	var crowns := _crowns_in(t.world)
	t.check(
		crowns.size() == 2
			and crowns.any(func(c): return c.get("node") == invaders.leader())
			and crowns.any(func(c): return c.get("node") == household.leader()),
		"toggled on through the test world, one crown over each side's leader (%s)"
			% str(crowns),
	)
	t.world.set_overlay(Registry.LEADERS, false)
	await t.frames(2)
	t.check(_crowns_in(t.world).is_empty(), "toggled off through the test world, the crowns go")


## Main's match has the overlay over its squads (built by the match builder), off while the flag
## is, and the bar's toggle through Main's `set_overlay` shows it, by the match builder's rule.
func _check_main(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var built: Dictionary = await main.start_match(MatchBuilder.spec({
		"seed": MATCH_SEED,
		"defenders": { "count": 1 },
		"invaders": { "count": 2 },
	}))
	var squads: Dictionary = built.get("squads", {})
	if not t.require(
			squads.has(&"invader") and squads.has(&"household"),
			"premise: Main's match has a squad per side (squads %s)" % str(squads.keys()),
	):
		await MainProbe.close(t, viewport)
		return
	# Held where they stand, so a crown drawn on one frame still sits on its leader the next.
	for c: Node in built["combatants"]:
		c.set("speed", 0.0)
	var lead: Node = squads[&"invader"].leader()
	var boss: Node = squads[&"household"].leader()
	var overlay: Node = (built["world"] as Node).get_node_or_null("LeaderOverlay")
	if not t.require(
			overlay != null,
			"Main's match has the LeaderOverlay under its World",
	):
		await MainProbe.close(t, viewport)
		return
	await t.frames(2)
	t.check(overlay.drawn().is_empty(), "off by default: no crown")
	main.set_overlay(Registry.LEADERS, true)
	await t.frames(2)
	t.check(
		_crowned(overlay, lead) and _crowned(overlay, boss),
		"the bar's toggle shows a crown over each squad's leader (%s)" % str(overlay.drawn()),
	)
	_check_real_view(t, squads[&"invader"], overlay, lead)
	main.set_overlay(Registry.LEADERS, false)
	await t.frames(2)
	t.check(overlay.drawn().is_empty(), "toggled off, the crowns go")
	await MainProbe.close(t, viewport)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))


## A real `squad`'s view() carries leash, trail and each member's follow spot, and `overlay` rings
## its leader `lead` with the leash.
func _check_real_view(t: TestContext, squad: Node, overlay: Node, lead: Node) -> void:
	var view: Dictionary = squad.view()
	t.check(
		view.has("leash") and view.has("trail")
			and (view.get("members", []) as Array).all(func(m): return m.has("follow_spot")),
		"a real squad's view() carries leash, trail and each member's follow_spot (keys %s)"
			% str(view.keys()),
	)
	t.check(
		_of(overlay, "leash").any(func(e): return e.get("node") == lead),
		"the bar's toggle shows the leash ring round the invaders' leader (%s)"
			% str(overlay.drawn()),
	)


## The squad's leash ring, follow spots, lines and trail (LD28), off fake views: drawn while
## on, from the view alone; nothing while off.
func _check_follow(t: TestContext, overlay: Node, lead: Node, next: Node, boss: Node) -> void:
	var spot := Vector2(210, 330)
	var trail := [Vector2(150, 300), Vector2(240, 260), Vector2(330, 220)]
	_views = _fake_views(lead, next, boss, spot, trail)
	await t.frames(2)
	var rings := _of(overlay, "leash")
	t.check(
		rings.size() == 2 and rings.any(func(e): return _rings_lead(e, lead)),
		"a leash ring of 320 px round each living leader (%s)" % str(rings),
	)
	var spots := _of(overlay, "spot")
	t.check(
		spots.size() == 1
			and spots[0].get("node") == next
			and (spots[0].get("point", Vector2.INF) as Vector2).distance_to(spot) < 0.5,
		"the follower's follow spot, and none for a member with no spot (%s)" % str(spots),
	)
	var lines := _of(overlay, "line")
	t.check(
		lines.size() == 1
			and lines[0].get("node") == next
			and (lines[0].get("from", Vector2.INF) as Vector2).distance_to(next.global_position)
				< 2.0
			and (lines[0].get("to", Vector2.INF) as Vector2).distance_to(spot) < 0.5,
		"a thin line from the follower to its spot (%s)" % str(lines),
	)
	var trails := _of(overlay, "trail")
	t.check(
		trails.any(func(e): return Array(e.get("points", [])) == trail),
		"the leader's trail as a dotted line (%s)" % str(trails),
	)
	t.check(
		_crowned(overlay, lead) and _crowned(overlay, boss),
		"and the crowns still (%s)" % str(overlay.drawn()),
	)
	overlay.show_leaders = false
	await t.frames(2)
	t.check(overlay.drawn().is_empty(), "off, no ring, spot, line or trail is drawn")


## The fake views: `lead` leading with a leash of 320 px and `trail`, `next` following to `spot`;
## `boss` leading the other squad alone.
func _fake_views(lead: Node, next: Node, boss: Node, spot: Vector2, trail: Array) -> Array:
	return [
		{
			"leader": lead,
			"leash": 320.0,
			"trail": trail,
			"members": [
				{ "node": lead, "order": {}, "follow_spot": Vector2.INF },
				{ "node": next, "order": {}, "follow_spot": spot },
			],
		},
		{
			"leader": boss,
			"leash": 320.0,
			"trail": [],
			"members": [{ "node": boss, "order": {}, "follow_spot": Vector2.INF }],
		},
	]


## Whether the drawn leash ring `e` is a 320 px one round `lead` where it stands.
func _rings_lead(e: Dictionary, lead: Node) -> bool:
	return (
		e.get("node") == lead
			and (e.get("point", Vector2.INF) as Vector2).distance_to(lead.global_position) < 2.0
			and is_equal_approx(float(e.get("radius", 0.0)), 320.0)
	)


## The crowns drawn by every squad-leaders overlay under `world` (a child with `show_leaders`).
func _crowns_in(world: Node) -> Array:
	var out: Array = []
	for child in world.get_children():
		if "show_leaders" in child and not child.is_queued_for_deletion():
			out.append_array(_of(child, "crown"))
	return out


## The entries of `overlay.drawn()` of kind `kind`.
func _of(overlay: Node, kind: String) -> Array:
	return (overlay.drawn() as Array).filter(func(e): return String(e.get("kind", "")) == kind)


## Whether a crown (an entry of kind `crown`) is drawn over `who`.
func _crowned(overlay: Node, who: Node) -> bool:
	return (overlay.drawn() as Array).any(func(c): return (
		String(c.get("kind", "")) == "crown"
			and c.get("node") == who
			and (c["point"] as Vector2).distance_to(who.global_position) < 2.0
	))
