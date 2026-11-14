class_name SkinCatalog
extends RefCounted
## All skins: one generated DEFAULT skin per archetype (from its RobotDefinition palette, always owned) + extra
## skins from res://config/skins/*.tres (campaign boss rewards now; shop / events later).

const PATHS := [
	"res://config/skins/tin_copper.tres",
	"res://config/skins/hopper_lime.tres",
	"res://config/skins/heavy_iron.tres",
	"res://config/skins/samurai_shogun.tres",
	"res://config/skins/rocket_silver.tres",   # v36: Chronobot's first colour scheme
]

var skins: Array[SkinDefinition] = []
var _by_id := {}


func _init(robots: RobotCatalog) -> void:
	for d in robots.robots:
		_add(SkinDefinition.from_robot_default(d))
	for p in PATHS:
		var s: SkinDefinition = load(p)
		if s:
			_add(s)


func _add(s: SkinDefinition) -> void:
	skins.append(s)
	_by_id[s.id] = s


func get_by_id(id: String) -> SkinDefinition:
	return _by_id.get(id)


func for_robot(robot_id: String) -> Array[SkinDefinition]:
	var out: Array[SkinDefinition] = []
	for s in skins:
		if s.robot_id == robot_id:
			out.append(s)
	return out


func is_default(id: String) -> bool:
	var s := get_by_id(id)
	return s != null and s.source == "default"
