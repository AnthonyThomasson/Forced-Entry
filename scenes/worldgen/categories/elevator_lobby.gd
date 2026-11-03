class_name ElevatorLobbyCatalog
## World Generation domain: the elevator lobby, a placeholder room for stairs and elevators.
## It owns no pieces, arrangements or clutter, and its recipe is `bare`: nothing is placed in it
## (HouseSpawner lays only its floor stencil, "WIP ELEVATOR LOBBY"). Its `text` is that stencil's.

const OBJECTS := {}
const ARRANGEMENTS := {}
const RECIPES := {
	"elevator_lobby": {
		"bare": true,
		"text": "WIP ELEVATOR LOBBY",
		"palettes": [
			{
				"wood": GeneralCatalog.WOOD.charcoal,
				"fabric": GeneralCatalog.FABRIC.slate,
				"floor": "concrete",
			},
		],
		"zones": [],
	},
}
