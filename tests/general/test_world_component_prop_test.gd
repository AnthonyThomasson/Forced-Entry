extends GameTest
## Ticket #76: an actor's prop named `component:prop` is set on that component of the character
## (the typed objects a character holds as properties, built when it is made), before the
## character joins the tree, as a plain prop is set on the character itself
## (`docs/adr/0004-the-character-split-into-typed-components.md`).
##
## The component here is the body's pose's gait (`anatomy:pose:gait`): its stride phase (rad, one
## turn per stride) only advances with the distance walked, so a puppet that stands still keeps the
## phase it was given.

## The stride phase the actor is given (rad); a fresh pose starts at 0.
const STRIDE := 1.25


func describe() -> Dictionary:
	return {
		"name": "A component prop is set on the component",
		"description": "An actor prop `anatomy:pose:gait:_stride` starts the standing puppet's "
			+ "stride phase there, and a plain prop beside it still sets the character.",
		"tags": ["setup", "props"],
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 300))
	s.actor(
		&"still",
		&"puppet",
		Vector2(150, 150),
		{ "anatomy:pose:gait:_stride": STRIDE, "max_health": 80.0 },
	)


func run(t: TestContext) -> void:
	var still := t.actor(&"still")
	await t.frames(3)
	t.require(still.velocity.length() < 1.0, "premise: the puppet stands still")
	t.expect_near(
		still.anatomy.pose.gait.stride_phase(),
		STRIDE,
		0.001,
		"the standing puppet's stride phase is the one its prop gave its pose",
	)
	t.expect_near(still.health, 80.0, 0.001, "the plain prop beside it set the character")
