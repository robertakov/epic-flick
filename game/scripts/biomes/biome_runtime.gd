class_name BiomeRuntime
extends RefCounted
## The ONE place that holds the active biome of the running level and applies / restores its scoped physics.
## Green Hills is the exact baseline: every modifier returns the neutral value, gravity is the project default.
## GameManager calls activate() for EVERY run (Green Hills included) and on returning to the menu, so no biome
## state can leak into another level.

const BASE_GRAVITY := 1800.0          # ProjectSettings physics/2d/default_gravity (never changed)
## Liquid-chocolate tuning (feet on a chocolate pool).
const CHOCO_REBOUND := 0.72           # release normal speed x0.72 ...
const CHOCO_MIN_EXIT := 430.0         # ... but never below this (px/s, normal) -> can always leave the pool
const CHOCO_DRAG := 1.5               # tangential speed decay while feet stand in chocolate (1/s)

static var biome: BiomeDef = null
static var terrain: TerrainBuilder = null
static var _space := RID()


static func current() -> BiomeDef:
	return biome if biome != null else BiomeCatalog.get_def(BiomeCatalog.GREEN)


static func id() -> String:
	return current().id


static func gravity() -> float:
	return BASE_GRAVITY * current().gravity_scale


## Apply a biome to the physics world (space gravity) and remember the terrain for surface queries.
static func activate(def: BiomeDef, space: RID, p_terrain: TerrainBuilder) -> void:
	biome = def if def != null else BiomeCatalog.get_def(BiomeCatalog.GREEN)
	terrain = p_terrain
	_space = space
	if space.is_valid():
		PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, gravity())


static func reset(space: RID, p_terrain: TerrainBuilder) -> void:
	activate(BiomeCatalog.get_def(BiomeCatalog.GREEN), space, p_terrain)


## Surface kind under x: &"normal", &"chocolate" or &"jelly".
static func surface_at(x: float) -> StringName:
	var b := current()
	if b.jelly:
		return &"jelly"
	if b.chocolate and terrain != null and terrain.is_chocolate(x):
		return &"chocolate"
	return &"normal"


## Multiplier of the release normal speed of a VALID feet landing at x (1.0 = baseline).
static func feet_release(x: float) -> float:
	var b := current()
	match surface_at(x):
		&"jelly":
			return b.feet_rebound
		&"chocolate":
			return CHOCO_REBOUND
	return b.feet_rebound


static func rebound_cap(x: float) -> float:
	return current().rebound_cap if surface_at(x) == &"jelly" else 1.0
