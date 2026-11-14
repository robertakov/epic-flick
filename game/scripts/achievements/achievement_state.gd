class_name AchievementState
extends RefCounted
## Offline profile schema. Unknown keys survive forward/backward-compatible reloads.
static var _definitions: Array = []
static func defaults() -> Dictionary:
	return {"version": 1, "values": {}, "unlocked": {}}
static func sanitize(source: Variant) -> Dictionary:
	var out := defaults()
	if source is not Dictionary: return out
	for field in ["values", "unlocked"]:
		var rows: Variant = source.get(field, {})
		if rows is not Dictionary: continue
		for key in rows:
			var value: Variant = rows[key]
			if key is not String or key.length() > 100 or typeof(value) not in [TYPE_INT, TYPE_FLOAT]: continue
			if not is_finite(float(value)) or float(value) < 0.0: continue
			out[field][key] = int(minf(float(value), 1.0e12)) if field == "unlocked" else minf(float(value), 1.0e9)
	return out
static func definitions() -> Array:
	if _definitions.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/achievements.json"))
		if data is Dictionary: _definitions = data.get("achievements", [])
	return _definitions
static func definition(id: String) -> Dictionary:
	for d in definitions():
		if d.id == id: return d
	return {}
static func presentation(state: Dictionary, d: Dictionary) -> Dictionary:
	var unlocked: bool = state.get("unlocked", {}).has(d.id)
	var masked: bool = bool(d.hidden) and not unlocked
	return {"id": d.id, "hidden": masked, "unlocked": unlocked,
		"name": L.t("ACH_HIDDEN_NAME") if masked else L.f(d.name_key, {"n": int(d.target)}),
		"description": L.t("ACH_HIDDEN_DESC") if masked else L.f(d.description_key, {"n": int(d.target)}),
		"progress": 0.0 if masked else minf(float(state.get("values", {}).get(d.metric, 0)), float(d.target)),
		"target": float(d.target), "timestamp": state.get("unlocked", {}).get(d.id, 0), "category": d.category}
