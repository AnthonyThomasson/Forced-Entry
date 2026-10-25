# Items and the vehicle split into typed parts

`item.gd` (the `Item` base) had 33 public methods and `gun.gd` (`GunItem`) 35, against gdstyle's
`quality/max-public-methods` (20), which issue #76 turns on with no exclusion. `vehicle.gd` had 18 vars and 31 public
methods (`max-class-variables` 15), and `vehicle_boarding.gd`, `dropped_item.gd` and `thrown_grenade.gd` had 16 to 18
vars.

`Item` is a polymorphic base: the character calls its virtuals on whatever is held, and each kind overrides them. It
is split per concern into three typed parts it holds, each built once with the item and handed up by its kind through
`super(...)`. `strike` (`ItemStrike`) is the melee geometry the hands read, held as data: a fist's by default, a long
gun's from its row. `art` (`ItemArt`, subclassed by `GunArt`, `GrenadeArt` and `SpoonArt`) is how it is drawn and its
weapon `style`. `ammo` (`ItemAmmo`, subclassed by `GunAmmo`) is its load and reload. The item keeps the hold-and-use
contract, gun identity and throwing. What differs between kinds only as data goes into the kind's config row: a gun's
sizes, grip and stances in `GunConfig`, a grenade's art size in `GrenadeConfig`. `PistolItem`, `SmgItem` and `RifleItem`
only name their row. No part holds its item: items are `RefCounted` and are made mid-fight, so a cycle would never be
freed. A part holds the ids it needs, and is handed the user on each call.

The vehicle is split as the character was (ADR 0004). `cabin` (`VehicleCabin`) holds the doors, seats and rides. The
existing driving model, `drive`, takes the intent, the engine and the skid. A private `_contacts`
(`VehicleContacts`) holds the crashes and the characters struck. The body keeps its exports, the drivable and
hittable contracts (interface 19, interface 3), and the shape the ride and the visuals read. The boarding ride's
current pose phase is its inner `Pose`. `DroppedItem`'s and `ThrownGrenade`'s exports were tuning no scene authored.
They become holders: `DroppedItemConfig`, and three family-wide statics in `GrenadeConfig`.

A member keeps its name, except that a prefix its part already says is dropped (`strike_direction` →
`strike.direction`, `ammo_capacity` → `ammo.capacity`).

## Consequences

Callers name the part: `item.art.draw_weapon(canvas, user)`, `item.strike.forward()`, `item.ammo.can_reload(user)`,
`item.art.style`, `vehicle.cabin.seat_point(id)`, `vehicle.drive.start_engine()`. That is 54 item sites, 46 of them in
the Character domain and tests (the other 8 are the Items domain's dropped item, thrown grenade and registry), and 23
vehicle sites, all inside the Vehicles domain. No AI file changes: the AI reads the character's components and an
item's `display_name`, so it still has no per-weapon code. `Item` ends at 5 vars and 15 public methods, `GunItem` at 3
and 11, the vehicle at 7 and 19. A new gun is a `GunConfig` row and an `ItemRegistry` case. A new kind that is not a gun
writes its `Item` subclass, plus an `ItemArt` subclass if it is drawn and its `ItemStrike` numbers if it strikes. Each
item allocates three more objects when it is made, so a plain perf A/B plays a different fight (the sight cadence is
keyed on instance ids) and is compared on the same fight. The architecture skill's interfaces 6, 7 and 19 name the
parts, and its "Typed components" convention covers a polymorphic base.

## Considered options

- **Fewer, wider virtuals taking a query** (`item.hold(hand, raised)`, `item.strike(aim, amount) -> StrikePose`):
  rejected. The hands ask every physics frame, so a returned value is an allocation per frame per character. A query
  key loses its type, the reason ADR 0003 gives.
- **Every concern a part, with a subclass per kind** (a `GunStrike`, a hold part): rejected. The strike and the hold
  differ between kinds only by numbers. Data in the row needs no override, and a new gun writes no class.
- **Parts that keep a reference to their item:** rejected. A `RefCounted` cycle is never freed, and an item is made per
  grenade thrown.
- **The weapon style left on the item, read by the art through its item:** rejected for the same cycle. The style is
  looks only, so it belongs to the art.
- **The vehicle's drivable reads moved into a part** (`vehicle.drive.slip()`): rejected. Audio and the camera read them
  duck-typed off the body (interfaces 10, 19), and a contract names the body, as ADR 0004 kept the character's.
- **Exclusions, a higher threshold, or a split by size** (`gun_a.gd`, a deeper inheritance chain): rejected by #76 and
  ADR 0004. gdstyle counts per file, so a chain would pass while the contract stayed as wide.
