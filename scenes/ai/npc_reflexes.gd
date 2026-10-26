extends RefCounted
## AI orchestrator: the controller's reflexes, a part it builds once in its `_ready` and holds as
## `_reflexes`. What the NPC does every tick outside the decision walk: it follows its squad's
## leader and fights within its leash (`docs/leadership.md` LD19, LD23), gets clear of the live
## grenade that threatens it (G16), and, flash-blinded, rolls once whether it fires blind and
## re-decides the moment its sight returns (G15). Built once with its controller, it holds it (a
## node, so no reference cycle) for the NPC's body, perception, behaviour, cadence, tuning and
## squad.

## The controller it belongs to.
var controller: Node
## Whether the NPC followed its squad's leader last tick (`Squad.follows`, LD19).
var _follows := false
## A fight off the leash forced a decision, and the NPC has not been back within the break since.
var _leash_broke := false
## The character was flash-blinded last tick, to re-decide the moment its sight returns.
var _was_blind := false
## The AI's one source of chance (the blind-fire roll, G15), seeded once at bind from the
## character's name and spawn spot, so a seeded match or a test that places the NPC the same way
## draws the same rolls.
var _rng := RandomNumberGenerator.new()


func _init(brain: Node) -> void:
	controller = brain


## Seeds the RNG from `character`'s name and spawn spot, on the controller's first tick.
func bind(character: Node) -> void:
	_rng.seed = hash("%s %s" % [character.name, character.global_position.round()])


## The squad's follow reads, every tick (LD19, LD23): whether the NPC follows its leader (the
## perception's `follows`), deciding at once when that changes (it joined a squad's file, or the
## leader it followed died and it leads now), and the leash it fights within while it holds no
## order (`leash_lead`). A leashed follower fighting farther than `leash_break` leashes from its
## leader, neither committed nor on its way somewhere, decides again, once until it has been back
## within that.
func follow_squad() -> void:
	var squad: Node = controller.squad
	var behavior: Node = controller._behavior
	var follows: bool = (squad != null
			and is_instance_valid(squad)
			and squad.has_method("follows")
			and squad.follows(controller._character))
	controller._perception.follows = follows
	if follows != _follows:
		_follows = follows
		controller._cadence.force("follows its leader" if follows else "leads its squad")
	var lead := leash_lead()
	if lead == null:
		behavior.set_leash(Vector2.INF, 0.0)
		_leash_broke = false
		return
	behavior.set_leash(lead.global_position, squad.leash)
	if (controller._character.global_position.distance_to(lead.global_position)
			<= squad.leash * squad.leash_break):
		_leash_broke = false
	elif (not _leash_broke
			and behavior.in_combat()
			and not behavior.committed()
			and not behavior.walk_pending()):
		_leash_broke = true
		controller._cadence.force("off the leash")


## The leader the NPC follows (`Squad.leader`), or null when it follows none.
func leader_followed() -> Node2D:
	if not controller._perception.follows:
		return null
	return controller.squad.leader() as Node2D


## The leader whose leash the NPC fights within (LD23): the one it follows while it holds no order,
## else null (a member carrying an order, a held stack or a join included, goes where the order
## takes it).
func leash_lead() -> Node2D:
	return leader_followed() if controller._perception.order().is_empty() else null


## The grenade reflex (G16) and the blind NPC (G15), every tick after the SEE pass: hand the
## behaviour the plan to get clear of the live grenade that threatens the NPC (or {}), radio the
## grenades it has seen or heard come down, roll once whether it fires blind the tick it goes blind,
## and re-decide the moment its sight returns.
func react_to_grenades() -> void:
	var perception: Node = controller._perception
	var behavior: Node = controller._behavior
	behavior.poll_throw()
	behavior.set_evade(perception.evade_plan())
	for grenade in perception.grenade_announcements():
		if controller.tuning.radio.send_callouts:
			controller._comms.post_grenade_call(grenade)
	var blind: bool = controller._character.stun.is_blind()
	if blind and not _was_blind:
		# One draw per blinding, whatever the chance, so the sequence does not depend on it.
		var draw := _rng.randf()
		var chance: float = controller.tuning.grenades.blind_fire_chance
		behavior.set_blind_fire(draw < chance or chance >= 1.0)
	if _was_blind and not blind:
		controller._cadence.force("sight returned")
	_was_blind = blind
