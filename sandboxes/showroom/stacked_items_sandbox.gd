extends GameTest
## A showroom of the small items (#194 stack-a, D20, `docs/stacked-items.md`): you are the player,
## with a pistol (3) and fists (2), in a room that holds a table of tableware, a desk with a
## monitor, a lamp and a book, a bookcase with books and a cup on top of it, a stack of boxes on
## crates, and a row of plates, cups and a book lying on the floor.
##
## Shoot anything on a top: a round passes a plate and knocks it off, a crate stops it. Shove (walk
## into) a box on its crate, a lamp, a monitor, a crate: each moves alone, the rest stay put.
## Knock the table over (shoot it near its edge, or shove it hard with a car's worth of weight) and
## watch the tableware spill. Walk over the row on the floor: the plates, cups and the book are
## stepped over and stay where they lie; the crate at its end is shoved. Throw nothing at the
## stack unless you mean to see it fall.
##
## Nothing is asserted. Temporary showroom: it goes with the ticket's last job.

const ARENA := Rect2(0, 0, 1000, 640)
const TABLE := Vector2(300, 140)
const DESK := Vector2(620, 110)
const CASE := Vector2(900, 120)
const STACK := Vector2(780, 420)
const FLOOR_ROW := Vector2(200, 480)
## The floor's walk-over row, left to right: a plate, a cup, a book and a bowl, `ROW_GAP` px apart,
## then a crate (taller than a step: shoved) at its end.
const ROW_GAP := 34.0


func describe() -> Dictionary:
	return {
		"name": "Stacked items showroom",
		"description": "Player sandbox: WASD, mouse, LMB fire, 2 fists, 3 pistol. A table of "
			+ "plates, cups and a bowl, a desk with a monitor, a lamp and a book, a bookcase "
			+ "with a cup and books on top, two crates and a box stacked, and plates, a cup and "
			+ "a book lying on the floor to walk over. Shoot or shove anything: it moves alone.",
		"tags": ["sandbox", "player", "items", "stacking", "furniture", "showroom"],
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.actor(&"you", &"player", Vector2(120, 330), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(940, 420), { "max_health": 200.0, "faction": &"dummy" })
	# a table of tableware
	s.object(&"table", "dining_table", TABLE)
	s.object(&"t_plate_a", "plate", Vector2(-14, -8), { "on": &"table" })
	s.object(&"t_plate_b", "plate", Vector2(16, 8), { "on": &"table" })
	s.object(&"t_cup", "cup", Vector2(0, 14), { "on": &"table" })
	s.object(&"t_bowl", "bowl", Vector2(24, -12), { "on": &"table" })
	s.object(&"t_cup_on_plate", "cup", Vector2(-14, -8), { "on": &"table" })
	# a desk
	s.object(&"desk", "desk", DESK)
	s.object(&"d_monitor", "monitor", Vector2(-20, -6), { "on": &"desk" })
	s.object(&"d_lamp", "desk_lamp", Vector2(40, -10), { "on": &"desk" })
	s.object(&"d_book", "book", Vector2(14, 10), { "on": &"desk" })
	# a bookcase: a cup and a book on its top
	s.object(&"case", "bookshelf", CASE)
	s.object(&"c_cup", "cup", Vector2(0, -20), { "on": &"case" })
	s.object(&"c_book", "book", Vector2(0, 14), { "on": &"case" })
	# boxes stacked on crates
	s.object(&"crate_low", "crate", STACK)
	s.object(&"crate_mid", "crate", Vector2.ZERO, { "on": &"crate_low" })
	s.object(&"box_top", "box", Vector2.ZERO, { "on": &"crate_mid" })
	s.object(&"crate_side", "crate", STACK + Vector2(-44, 0))
	s.object(&"box_side", "box", Vector2.ZERO, { "on": &"crate_side" })
	# what lies on the floor: walked over; and a crate at the end of the row
	s.object(&"f_plate", "plate", FLOOR_ROW)
	s.object(&"f_cup", "cup", FLOOR_ROW + Vector2(ROW_GAP, 0))
	s.object(&"f_book", "book", FLOOR_ROW + Vector2(ROW_GAP * 2.0, 0))
	s.object(&"f_bowl", "bowl", FLOOR_ROW + Vector2(ROW_GAP * 3.0, 0))
	s.object(&"f_crate", "crate", FLOOR_ROW + Vector2(ROW_GAP * 4.0, 0))
	s.switch(&"nav.rebake", false)


func run(_t: TestContext) -> void:
	pass
