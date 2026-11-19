extends GameTest
## A kick lands at the shin, a punch up at the fist (#194 chars3d-a, interface 5): the blows reach
## into the twin space at their real heights. A menu board stands on legs with its sign from 46 px
## up to 80: a punch (the fist is up at 49 px) lands on it; a kick (the foot is at 17 px, reaching
## to about 23) passes under it and lands on nothing. A bookshelf, which stands on the floor, is
## kicked all the same.

const FRONT := 40.0
## How far in front of a sign (its panel at the back of a 100 by 20 px footprint) a puppet stands,
## from the footprint's front edge.
const SIGN_FRONT := 28.0


func describe() -> Dictionary:
	return {
		"name": "A kick lands at the shin, a punch up at the fist",
		"description": "A sign hung 46 px up is punched and not kicked; a floor bookshelf is "
			+ "kicked.",
		"tags": ["melee", "kick", "punch", "pushable", "3d", "twins"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.object(&"sign_punched", "menu_board", Vector2(300, 100))
	s.object(&"sign_kicked", "menu_board", Vector2(300, 250))
	s.object(&"shelf_kicked", "bookshelf", Vector2(300, 400))
	s.actor(&"boxer", &"puppet", Vector2(300, 100 + 10.0 + SIGN_FRONT), { "start_slot": 2 })
	s.actor(&"kicker", &"puppet", Vector2(300, 250 + 10.0 + SIGN_FRONT), { "start_slot": 2 })
	s.actor(&"kicker2", &"puppet", Vector2(300 - FRONT, 400), { "start_slot": 2 })


func run(t: TestContext) -> void:
	await t.frames(3)
	for pair: Array in [
		[&"boxer", &"sign_punched"], [&"kicker", &"sign_kicked"], [&"kicker2", &"shelf_kicked"],
	]:
		t.puppet(pair[0]).aim_at((t.object(pair[1]) as Node2D).global_position)
	await t.seconds(0.3)
	t.puppet(&"boxer").punch()
	t.puppet(&"kicker").kick()
	t.puppet(&"kicker2").kick()
	await t.seconds(1.2)
	var landed := func(actor: StringName, piece: StringName) -> bool:
		return t.happened(
			&"hit_landed", func(d): return d["actor"] == actor and d["body"] == t.object(piece)
		)
	t.check(landed.call(&"boxer", &"sign_punched"), "the punch lands on the sign, 46 px up")
	t.check(not landed.call(&"kicker", &"sign_kicked"), "the kick, at the shin, passes under it")
	t.check(landed.call(&"kicker2", &"shelf_kicked"), "a kick lands on a bookshelf on the floor")
