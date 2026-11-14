class_name RobotCatalog
extends RefCounted
## Ordered list of purchasable robots (data: res://config/robots/*.tres). Add a robot = add a .tres + its path here.

const PATHS := [
	"res://config/robots/tin.tres",
	"res://config/robots/hopper.tres",
	"res://config/robots/heavy.tres",
	"res://config/robots/rocket.tres",
	"res://config/robots/samurai.tres",
]

var robots: Array[RobotDefinition] = []


func _init() -> void:
	for p in PATHS:
		var d: RobotDefinition = load(p)
		if d:
			robots.append(d)


func get_by_id(id: String) -> RobotDefinition:
	for d in robots:
		if d.id == id:
			return d
	return null


func index_of(id: String) -> int:
	for i in robots.size():
		if robots[i].id == id:
			return i
	return -1


func starter_ids() -> Array[String]:
	var out: Array[String] = []
	for d in robots:
		if d.starter or d.price <= 0:
			out.append(d.id)
	return out


## Largest value of a stat over the catalog (to draw relative stat bars).
func stat_max(key: String) -> float:
	var m := 0.0001
	for d in robots:
		m = maxf(m, float(d.get(key)))
	return m
