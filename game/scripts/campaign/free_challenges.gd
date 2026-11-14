class_name FreeChallenges
extends RefCounted
## Selection only: physical telemetry/evaluation remains the shared StarTracker.
const CONFIG_PATH := "res://config/free_challenges.json"

static func config() -> Dictionary:
	var value = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return value if typeof(value) == TYPE_DICTIONARY else {}

static func compatible(challenges: Array) -> bool:
	var types := []
	var categories := []
	for ch in challenges:
		if typeof(ch) != TYPE_DICTIONARY or StarChallenges.validate(ch) != "":
			return false
		if types.has(ch.type) or categories.has(StarChallenges.category(ch)):
			return false
		types.append(ch.type)
		categories.append(StarChallenges.category(ch))
	# A longer clean-distance objective would automatically complete a shorter distance goal.
	for a in challenges:
		if a.type != "DISTANCE":
			continue
		for b in challenges:
			if b.type in ["BAD_LANDING_LIMIT", "CLEAN_SECTION"] and float(b.m) >= float(a.m):
				return false
	for pair in StarChallenges.INCOMPATIBLE:
		if types.has(pair[0]) and types.has(pair[1]):
			return false
	return true

static func generate(robot_id: String, seed_value: int, id: int, cfg: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result := []
	var overrides: Dictionary = cfg.get("robot_overrides", {}).get(robot_id, {})
	for category in ["A", "B", "C"]:
		var candidates := []
		for type in StarChallenges.TYPES:
			if not cfg.get("thresholds", {}).has(type) or StarChallenges.TYPES[type].cat != category or overrides.get(type, {}).get("exclude", false):
				continue
			var values: Dictionary = cfg.get("thresholds", {}).get(type, {}).duplicate(true)
			values.merge(overrides.get(type, {}), true)
			var ch := {"type": type, "reward": 0}
			for key in StarChallenges.TYPES[type].params:
				var pool: Array = values.get(key, [])
				if not pool.is_empty():
					ch[key] = pool[rng.randi_range(0, pool.size() - 1)]
			if compatible(result + [ch]):
				candidates.append(ch)
		if candidates.is_empty():
			return {}
		result.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	return {"id": id, "seed": seed_value, "robot": robot_id, "config_version": int(cfg.get("version", 1)),
		"challenges": result, "completed": [false, false, false],
		"reward_per_objective": clampi(int(cfg.get("reward_per_objective", 1)), 0, 1000),
		"max_rewarded_objectives": clampi(int(cfg.get("max_rewarded_objectives_per_set", 3)), 0, 3)}

static func valid_set(value: Dictionary) -> bool:
	if typeof(value.get("id")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value.id)) or float(value.id) != floor(float(value.id)) or int(value.id) <= 0 or int(value.id) > 1000000000:
		return false
	if typeof(value.get("challenges")) != TYPE_ARRAY or value.challenges.size() != 3 or not compatible(value.challenges):
		return false
	if typeof(value.get("completed")) != TYPE_ARRAY or value.completed.size() != 3:
		return false
	for flag in value.completed:
		if typeof(flag) != TYPE_BOOL:
			return false
	for key in ["reward_per_objective", "max_rewarded_objectives"]:
		var number = value.get(key)
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)) or float(number) != floor(float(number)) or float(number) < 0:
			return false
	return int(value.max_rewarded_objectives) <= 3 and int(value.reward_per_objective) <= 1000
