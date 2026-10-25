class_name GunAmmo extends ItemAmmo
## Items domain: a gun's load, its `ammo` part (`ItemAmmo`): the magazine it is loaded with, which
## each shot spends a round of (`GunItem.secondary`), and the reload that seats the fullest
## magazine its user carries. Built once with its gun (`GunItem._init`); it knows the gun only by
## its id, and the user is passed in on each call.

## The gun's id: its `GunConfig` row and the kind of magazine it takes (`Magazine.gun`).
var gun: StringName = &""
## The magazine it is loaded with (null = unloaded); every shot spends one of its rounds.
var magazine: Magazine


func _init(id: StringName) -> void:
	gun = id


## Rounds left in the loaded magazine (0 when unloaded).
func rounds_loaded() -> int:
	return magazine.rounds if magazine else 0


## Rounds the loaded magazine holds when full (0 when unloaded).
func capacity() -> int:
	return magazine.capacity if magazine else 0


## How long a reload takes: the loaded magazine's type decides (`MagazineConfig.reload_time_of`).
func reload_time() -> float:
	var type: StringName = (magazine.type if magazine
			else StringName(GunConfig.row(gun).get("magazine", &"standard")))
	return MagazineConfig.reload_time_of(type)


## A carried magazine holds more rounds than the one loaded.
func can_reload(user: Node2D) -> bool:
	var best: Magazine = user.ammo.best_magazine(gun)
	return best != null and best.rounds > rounds_loaded()


## Seat the fullest carried magazine; the one it replaces goes back into the carried store unless it
## is empty (nothing refills a magazine, so an empty one is dropped).
func finish_reload(user: Node2D) -> void:
	var fresh: Magazine = user.ammo.take_magazine(gun)
	if fresh == null:
		return
	var spent := magazine
	magazine = fresh
	if spent != null and spent.rounds > 0:
		user.ammo.stow_magazine(spent)
