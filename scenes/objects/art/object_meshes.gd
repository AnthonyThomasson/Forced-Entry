class_name ObjectMeshes
extends RefCounted
## Objects domain, the 3D meshes of its pieces (`domain-art/meshes.md`): which art ids
## have a mesh of their own and the one call that plugs them into the 3D mirror. Each id has a
## script beside the painters (`table_mesh.gd`) with `static func build(piece) -> Node3D`, built
## from Art's mesh kit, in 3D units and centred on the piece's origin; an art id with none stays a
## proxy box. Main's 3D view registers them (`register`) and tracks the floor stencils (`track`)
## before it mirrors the match.

const TableMesh = preload("res://scenes/objects/art/table_mesh.gd")
const SofaMesh = preload("res://scenes/objects/art/sofa_mesh.gd")
const ChairMesh = preload("res://scenes/objects/art/chair_mesh.gd")
const CabinetMesh = preload("res://scenes/objects/art/cabinet_mesh.gd")
const ShelfMesh = preload("res://scenes/objects/art/shelf_mesh.gd")
const CounterMesh = preload("res://scenes/objects/art/counter_mesh.gd")
const ApplianceMesh = preload("res://scenes/objects/art/appliance_mesh.gd")
const BedMesh = preload("res://scenes/objects/art/bed_mesh.gd")
const OfficeChairMesh = preload("res://scenes/objects/art/office_chair_mesh.gd")
const ToiletMesh = preload("res://scenes/objects/art/toilet_mesh.gd")
const BathMesh = preload("res://scenes/objects/art/bath_mesh.gd")
const RugMesh = preload("res://scenes/objects/art/rug_mesh.gd")
const PlantMesh = preload("res://scenes/objects/art/plant_mesh.gd")
const LampMesh = preload("res://scenes/objects/art/lamp_mesh.gd")
const CoatRackMesh = preload("res://scenes/objects/art/coat_rack_mesh.gd")
const ReclinerMesh = preload("res://scenes/objects/art/recliner_mesh.gd")
const FixtureMesh = preload("res://scenes/objects/art/fixture_mesh.gd")
const HotplateMesh = preload("res://scenes/objects/art/hotplate_mesh.gd")
const TechMesh = preload("res://scenes/objects/art/tech_mesh.gd")
const ClinicMesh = preload("res://scenes/objects/art/clinic_mesh.gd")
const SecurityMesh = preload("res://scenes/objects/art/security_mesh.gd")
const ShopMesh = preload("res://scenes/objects/art/shop_mesh.gd")
const NoodleMesh = preload("res://scenes/objects/art/noodle_mesh.gd")
const StockMesh = preload("res://scenes/objects/art/stock_mesh.gd")
const AwningMesh = preload("res://scenes/objects/art/awning_mesh.gd")
const StreetPropMesh = preload("res://scenes/objects/art/street_prop_mesh.gd")
const PodiumMesh = preload("res://scenes/objects/art/podium_mesh.gd")
const ShellDecorMesh = preload("res://scenes/objects/art/shell_decor_mesh.gd")
const DecorMesh = preload("res://scenes/objects/art/decor_mesh.gd")
const StreetlightMesh = preload("res://scenes/objects/art/streetlight_mesh.gd")
const CarMesh = preload("res://scenes/objects/art/car_mesh.gd")
const StencilMesh = preload("res://scenes/objects/art/stencil_mesh.gd")
## The builder script per `ObjectArt` id.
const BUILDERS := {
	"table": TableMesh,
	"sofa": SofaMesh,
	"chair": ChairMesh,
	"cabinet": CabinetMesh,
	"shelf": ShelfMesh,
	"counter": CounterMesh,
	"appliance": ApplianceMesh,
	"bed": BedMesh,
	"office_chair": OfficeChairMesh,
	"toilet": ToiletMesh,
	"bath": BathMesh,
	"rug": RugMesh,
	"plant": PlantMesh,
	"lamp": LampMesh,
	"coat_rack": CoatRackMesh,
	"recliner": ReclinerMesh,
	"fixture": FixtureMesh,
	"hotplate": HotplateMesh,
	"tech": TechMesh,
	"clinic": ClinicMesh,
	"security": SecurityMesh,
	"shop": ShopMesh,
	"noodle": NoodleMesh,
	"stock": StockMesh,
	"awning": AwningMesh,
	"street_prop": StreetPropMesh,
	"podium": PodiumMesh,
	"shell_decor": ShellDecorMesh,
	"decor": DecorMesh,
	"streetlight": StreetlightMesh,
	"car": CarMesh,
}


## Add every builder to `builders` (`WorldMirror.builders`) under the finer key of its art id, and
## the building's structure (walls, doors, floors: `StructureMeshes`).
static func register(builders: Dictionary) -> void:
	StructureMeshes.register(builders)
	for art: String in BUILDERS:
		var builder := Callable(BUILDERS[art], &"build")
		if builder.is_valid():
			builders[MirrorProxy.furniture_key(art)] = builder
		else:
			push_error("ObjectMeshes: the mesh script of '%s' has no static build(piece)" % art)


## Show the floor stencils (`DecalFactory.STENCIL_GROUP`: plain `StencilDecal` nodes, no physics
## body) by `StencilMesh`: `follower` (Art's `MeshFollower`; a `WorldMirror` has the same
## `track_group`) shows every one of that group under the world it follows.
static func track(follower: Node3D) -> void:
	follower.track_group(DecalFactory.STENCIL_GROUP, Callable(StencilMesh, &"build"))
