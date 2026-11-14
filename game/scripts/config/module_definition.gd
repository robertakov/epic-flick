class_name ModuleDefinition
extends Resource
## FUTURE gameplay module (legs/springs, arms, body, head, ...). Not used by any content yet: this class fixes the
## contract so modules can be added later without touching RobotController / physics code.
## A module changes the archetype's STATS (the same keys as RobotDefinition.base_stats()) by multipliers and
## offsets; trade-offs are expressed by mixing positive and negative changes. Modules never change appearance
## (that is SkinDefinition's job).

@export var id := "module"
@export var display_name := "Модуль"
## Slot the module occupies: "legs", "arms", "body", "head", ...
@export var slot := "legs"
## Archetypes it fits (empty = all five).
@export var robot_ids: PackedStringArray = []
@export var price := 0
## stat key -> multiplier (e.g. {"spring_strength": 1.15, "air_control": 0.9})
@export var stat_multipliers := {}
## stat key -> added value (e.g. {"max_health": 20.0})
@export var stat_offsets := {}


func fits(robot_id: String) -> bool:
	return robot_ids.is_empty() or robot_ids.has(robot_id)


## Applies a list of modules to a stats dictionary (returns a new dictionary).
static func apply_all(stats: Dictionary, modules: Array) -> Dictionary:
	var out := stats.duplicate()
	for m in modules:
		if m == null:
			continue
		for k in m.stat_multipliers:
			if out.has(k):
				out[k] = float(out[k]) * float(m.stat_multipliers[k])
		for k in m.stat_offsets:
			if out.has(k):
				out[k] = float(out[k]) + float(m.stat_offsets[k])
	return out
