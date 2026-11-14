class_name BiomeSchedule
extends RefCounted
## Deterministic campaign biome assignment (one biome per level, identical on every replay, every device).
##   r1..r15  : Green Hills only (the player first learns the "normal" world)
##   r16      : Moon, guaranteed (first surprise, first physics change)
##   after r16: one special level after 2..5 normal ones (mean ~3.5; drawn from a fixed seeded bag, never the same
##              spacing three times in a row, so there is no obvious period); the special biome is the least used
##              one that is NOT among the last two specials (no repeat, at least two others in between), ties broken
##              by the fixed seed. Green Hills stays the clear majority.
## A campaign node may override it with "biome": "<id>" in main.json (editable data); tests check the defaults.

const SEED := 160_303
const FIRST_SPECIAL_ROUND := 16
const GAP_BAG := [2, 3, 3, 4, 4, 5]

static var _cache: Dictionary = {}


static func for_round(round_number: int, rounds := 100) -> String:
	var table := assign(rounds)
	return String(table.get(round_number, BiomeCatalog.GREEN))


static func assign(rounds := 100) -> Dictionary:
	if _cache.has(rounds):
		return _cache[rounds]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out := {}
	for r in range(1, rounds + 1):
		out[r] = BiomeCatalog.GREEN
	if rounds < FIRST_SPECIAL_ROUND:
		_cache[rounds] = out
		return out
	out[FIRST_SPECIAL_ROUND] = "moon"
	var history: Array[String] = ["moon"]
	var used := {}
	for id in BiomeCatalog.SPECIALS:
		used[id] = 0
	used["moon"] = 1
	var last_gaps: Array[int] = []
	var r := FIRST_SPECIAL_ROUND
	while true:
		var gap: int = GAP_BAG[rng.randi_range(0, GAP_BAG.size() - 1)]
		while last_gaps.size() >= 2 and last_gaps[-1] == gap and last_gaps[-2] == gap:
			gap = GAP_BAG[rng.randi_range(0, GAP_BAG.size() - 1)]
		last_gaps.append(gap)
		r += gap + 1
		if r > rounds:
			break
		var recent := history.slice(maxi(0, history.size() - 2))
		var candidates: Array = BiomeCatalog.SPECIALS.filter(func(id: String) -> bool: return not recent.has(id))
		var low := 1 << 30
		for id in candidates:
			low = mini(low, int(used[id]))
		var pool: Array = candidates.filter(func(id: String) -> bool: return int(used[id]) == low)
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		out[r] = pick
		used[pick] = int(used[pick]) + 1
		history.append(pick)
	_cache[rounds] = out
	return out
