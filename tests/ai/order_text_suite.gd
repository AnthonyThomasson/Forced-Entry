extends UnitSuite
## Native unit suite (pure logic) for the order sentence of the decision snapshot
## (`SnapshotSections.order_text`, `docs/leadership.md` LD6, LD13, LD24, D38): a stack held for its
## leader's go reads " when they give the go" while its stack is held (the room its held stack is to
## enter kept out of, the confinement's `keep_out`), and none once the go came, whether the squad's
## go reached it (the menu) or the leader stepped in (D14, D38: a go no order memory hears of).
## Beneath `tests/ai/stack/rally_held_until_leader_crosses` (the held text in a real decision); no
## decision of a joiner comes after the leader stepped in, since a crossing member decides nothing.
## The sentences are read off the spec (D38, LD13), never built the way the code builds them.

const SnapshotSections := preload("res://scenes/ai/perception/snapshot/snapshot_sections.gd")
const SnapshotVocab := preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
## The house the orders name: the kitchen behind the back door.
const ROOMS := [{ "key": "kitchen", "type": "kitchen", "rect": Rect2(0, 0, 200, 200) }]
## A human leader's rally's join (LD24, D38): held for its leader's go.
const JOIN := {
	"id": "invader_1", "kind": "stack", "opening": "door_840_190", "into": "kitchen",
	"mode": "join", "wait_go": true, "frame": 80,
}
## An ordered stack held with "Hold for my go" (LD13), a stun first.
const HELD := {
	"id": "invader_2", "kind": "stack", "opening": "door_840_190", "into": "kitchen",
	"mode": "stun", "wait_go": true, "frame": 80,
}
const JOIN_HELD := (
	"Your leader ordered you to go into the kitchen by its doorway with them when they give the go."
)
const JOIN_GONE := "Your leader ordered you to go into the kitchen by its doorway with them."
const HELD_HELD := ("Your leader ordered you to go into the kitchen by its doorway with a stun "
		+ "grenade first when they give the go.")
const HELD_GONE := (
	"Your leader ordered you to go into the kitchen by its doorway with a stun grenade first."
)


## The sections, over the shared vocabulary (room names only: no NPC is needed for an order).
func _sections() -> SnapshotSections:
	var out := SnapshotSections.new()
	out.setup(SnapshotVocab.new(), null, null)
	return out


func test_a_held_join_reads_its_go_to_come() -> void:
	assert_str(_sections().order_text(JOIN, ROOMS, "kitchen")).is_equal(JOIN_HELD)


func test_a_join_whose_leader_stepped_in_reads_no_go_to_come() -> void:
	# The leader crossed: its stack is no longer held, though no go reached the order memory.
	assert_str(_sections().order_text(JOIN, ROOMS, "")).is_equal(JOIN_GONE)


func test_a_join_whose_menu_go_came_reads_no_go_to_come() -> void:
	var gone := JOIN.duplicate()
	gone["go"] = true
	gone["go_mode"] = "stun"
	assert_str(_sections().order_text(gone, ROOMS, "")).is_equal(JOIN_GONE)


func test_a_held_ordered_stack_reads_its_go_to_come() -> void:
	assert_str(_sections().order_text(HELD, ROOMS, "kitchen")).is_equal(HELD_HELD)


func test_a_held_ordered_stack_whose_leader_stepped_in_reads_no_go_to_come() -> void:
	# LD13's stepped-in go (D14): the leader's crossing released the stack off the radio.
	assert_str(_sections().order_text(HELD, ROOMS, "")).is_equal(HELD_GONE)
