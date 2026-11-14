class_name CampaignData
extends RefCounted
## Campaign graph loaded from JSON (res://config/campaign/main.json). Nodes have a type and a list of outgoing
## connections, so side branches / bonus nodes can be added later as data. Only "race" nodes are playable now;
## any other type is listed by the map but reported as not playable.
##
## node: {id, type, round, title, difficulty ("normal" | "hard" | "boss"), next: [ids], reward_first,
##        enemies: [{name, robot, skill, lean, greed}], (optional) pos: [x, y]}

const PLAYABLE_TYPES := ["race"]

var start_id := ""
var nodes := {}            # id -> node dict
var order: Array[String] = []
var load_error := ""


static func load_file(path: String) -> CampaignData:
	var c := CampaignData.new()
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if text == "" or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		c.load_error = "cannot parse %s" % path
		return c
	c.from_dict(json.data)
	if path == "res://config/campaign/main.json":
		c.load_stars("res://config/campaign/stars.json")
	return c


func from_dict(d: Dictionary) -> void:
	nodes.clear()
	order.clear()
	for n in d.get("nodes", []):
		if typeof(n) != TYPE_DICTIONARY or not n.has("id"):
			continue
		var node: Dictionary = n.duplicate(true)
		node.id = String(node.id)
		node["type"] = String(node.get("type", "race"))
		node["next"] = Array(node.get("next", [])).map(func(x) -> String: return String(x))
		node["enemies"] = node.get("enemies", [])
		for enemy in node["enemies"]:
			if enemy.has("target_min_distance") or enemy.has("target_max_distance"):
				var lo = enemy.get("target_min_distance")
				var hi = enemy.get("target_max_distance")
				if typeof(lo) not in [TYPE_FLOAT,TYPE_INT] or typeof(hi) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(lo)) or not is_finite(float(hi)) or float(lo)<=0 or float(hi)<=float(lo):
					load_error = "invalid AI distance band: " + node.id
					return
		node["difficulty"] = String(node.get("difficulty", "normal"))
		node["reward_first"] = int(node.get("reward_first", 0))
		nodes[node.id] = node
		order.append(node.id)
	start_id = String(d.get("start", order[0] if not order.is_empty() else ""))
	# v30: one fixed biome per level (data override "biome", else the deterministic BiomeSchedule by round)
	var rounds := 0
	for id in order:
		rounds = maxi(rounds, int(nodes[id].get("round", 0)))
	for id in order:
		var b := String(nodes[id].get("biome", ""))
		if b == "" or not BiomeCatalog.has(b):
			var r := int(nodes[id].get("round", 0))
			b = BiomeSchedule.for_round(r, maxi(rounds, 1)) if r > 0 else BiomeCatalog.GREEN
		nodes[id]["biome"] = b


func node(id: String) -> Dictionary:
	return nodes.get(id, {})


func next_ids(id: String) -> Array:
	return node(id).get("next", [])


func is_playable(id: String) -> bool:
	return PLAYABLE_TYPES.has(String(node(id).get("type", "")))


## Main-route successor (first race node among the connections), "" at the end.
func main_next(id: String) -> String:
	for n in next_ids(id):
		if is_playable(n):
			return n
	return ""


## Graph edges as [from, to] pairs (drawn by the map).
func edges() -> Array:
	var out := []
	for id in order:
		for n in next_ids(id):
			out.append([id, n])
	return out


func load_stars(path: String) -> void:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		load_error = "cannot parse star data: " + path
		push_error(load_error)
		return
	var seen := {}
	var previous: Array = []
	# v36: every authored challenge by type (baseline values) - source of deterministic biome replacements
	var pool := {}
	for k in order.size():
		var authored = json.data.get(order[k])
		if typeof(authored) == TYPE_ARRAY:
			for ch in authored:
				if typeof(ch) == TYPE_DICTIONARY and StarChallenges.validate(ch) == "":
					if not pool.has(String(ch.type)):
						pool[String(ch.type)] = []
					pool[String(ch.type)].append([k, ch])
	# v36: keys of every authored round (a biome replacement must never duplicate a set)
	var authored_keys := {}
	for k in order.size():
		var a2 = json.data.get(order[k])
		if typeof(a2) == TYPE_ARRAY:
			var ts := []
			for ch in a2:
				if typeof(ch) == TYPE_DICTIONARY:
					ts.append(String(ch.get("type", "")))
			ts.sort()
			authored_keys[",".join(ts)] = order[k]
	var res_prev: Array = []
	for id in order:
		var rows = json.data.get(id)
		if typeof(rows) != TYPE_ARRAY or rows.size() != 3:
			load_error = "expected 3 stars: " + id
			break
		var cats := []
		var types := []
		for ch in rows:
			if typeof(ch) != TYPE_DICTIONARY or StarChallenges.validate(ch) != "":
				load_error = "invalid star: " + id
				break
			cats.append(StarChallenges.category(ch))
			types.append(String(ch.type))
		cats.sort()
		if cats != ["A", "B", "C"]:
			load_error = "star categories: " + id
		for pair in StarChallenges.INCOMPATIBLE:
			if types.has(pair[0]) and types.has(pair[1]):
				load_error = "incompatible stars: " + id
		var shared := 0
		for type in types:
			shared += int(previous.has(type))
		types.sort()
		var key := ",".join(types)
		if shared > 1 or seen.has(key):
			load_error = "repeated stars: " + id
		seen[key] = true
		previous = types
		if load_error != "":
			break
		# v30: authored values are the Green Hills baseline; biome levels get their explicit adjustments
		nodes[id]["stars_base"] = rows.duplicate(true)
		var adjusted := []
		# v36: per-biome eligibility (excluded types replaced deterministically) + parameter rules
		var nid: String = id
		var next_types := []
		var ni := order.find(id) + 1
		if ni < order.size() and typeof(json.data.get(order[ni])) == TYPE_ARRAY:
			for ch in json.data.get(order[ni]):
				if typeof(ch) == TYPE_DICTIONARY:
					next_types.append(String(ch.get("type", "")))
		var rule := func(ts: Array) -> bool:
			var s := ts.duplicate()
			s.sort()
			var common := 0
			var common_next := 0
			for t in ts:
				common += int(res_prev.has(t))
				common_next += int(next_types.has(t))
			return common <= 1 and common_next <= 1 and String(authored_keys.get(",".join(s), nid)) == nid
		for a in BiomeChallenges.resolve(rows, String(nodes[id].get("biome", BiomeCatalog.GREEN)), order.find(id), pool, rule):
			if StarChallenges.validate(a) != "":
				load_error = "invalid biome-adjusted star: %s %s" % [id, StarChallenges.validate(a)]
				break
			adjusted.append(a)
		if load_error != "":
			break
		nodes[id]["stars"] = adjusted
		res_prev = adjusted.map(func(c: Dictionary) -> String: return String(c.type))
	if load_error != "":
		push_error(load_error)
