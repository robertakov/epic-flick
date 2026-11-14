class_name EnemyRoster
extends RefCounted
## Stable visual assignment; existing round archetypes, stats, bands and boss data remain authoritative.
static var _data: Dictionary = {}
static func data() -> Dictionary:
	if _data.is_empty(): _data=JSON.parse_string(FileAccess.get_file_as_string("res://config/enemy_roster.json"))
	return _data
static func slot(node_id: String, index: int) -> Dictionary:
	var slots: Array = data().rounds.get(node_id,[])
	return slots[index] if index>=0 and index<slots.size() else {}
static func display_name(enemy_id: String) -> String:
	return String(data().identities.get(enemy_id,{}).get("name",enemy_id))
static func decision_config(base: AIConfig, pressure: bool) -> AIConfig:
	if not pressure: return base
	var cfg := base.duplicate(true) as AIConfig
	var multipliers: Dictionary = data().pressure_decisions
	for key in multipliers:
		cfg.set(key,cfg.get(key)*float(multipliers[key]))
	return cfg

static func resolve_round_opponents(campaign: CampaignData, catalog: RobotCatalog, node_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if campaign == null or not campaign.nodes.has(node_id):
		return out
	var n := campaign.node(node_id)
	var enemies: Array = n.get("enemies", [])
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		var robot_id := String(e.get("robot", "tin"))
		var def := catalog.get_by_id(robot_id) if catalog else null
		if def == null and catalog and not catalog.robots.is_empty():
			def = catalog.robots[0]
			robot_id = def.id
		var presentation := slot(node_id, i)
		var enemy_id := String(presentation.get("id", ""))
		var name_str := display_name(enemy_id) if enemy_id != "" else String(e.get("name", L.t("RACE_RIVAL_N") % (i + 1)))
		out.append({
			"index": i,
			"enemy_id": enemy_id,
			"robot_id": robot_id,
			"skin_id": String(e.get("skin", "")),
			"name": name_str,
			"pressure": bool(presentation.get("pressure", false)),
			"boss": String(n.get("difficulty", "")) == "boss",
		})
	return out
