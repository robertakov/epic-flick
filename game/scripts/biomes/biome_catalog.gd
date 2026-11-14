class_name BiomeCatalog
extends RefCounted
## Registry of all biomes (data). IDs are stable technical names (saved in campaign data / tests).
##   green_hills  ЗЕЛЁНЫЕ ХОЛМЫ        baseline (existing world, untouched rules)
##   moon         ЛУНА                 0.45 g, dark starry sky with the Earth, grey regolith
##   heavy        СВЕРХГРАВИТАЦИЯ      1.6 g (v36 display rename from "Тяжёлый мир"; id stays "heavy") + weaker spring rebound, crushed alien world under a giant planet
##   chocolate    ШОКОЛАДНЫЙ МИР       biscuit ground with sticky liquid-chocolate pools that dirty the robot
##   jelly        ЖЕЛЕЙНЫЙ МИР         whole surface is jelly: much stronger feet rebounds, bouncy body hits
##   portal       ПОРТАЛЬНАЯ ЗОНА      stationary paired portals teleport robots
##   chasms       ПРОПАСТИ             real gaps in the track; falling in ends the run
##   cavern       ПЕЩЕРА               physical rock ceiling above the track
##   zone         ЗОНА ОТЧУЖДЕНИЯ      Pripyat-style exclusion zone with electrical / radiation / gravity anomalies

const GREEN := "green_hills"
const SPECIALS := ["moon", "heavy", "chocolate", "jelly", "portal", "chasms", "cavern", "zone"]

static func _pal(dirt: Color, dirt_dark: Color, top: Color, hl: Color, tuft: Color, rock: Color, deco: Color, rock_chance := 0.4, rock_scale := 1.0) -> Dictionary:
	return {"dirt": dirt, "dirt_dark": dirt_dark, "top": top, "hl": hl, "tuft": tuft, "rock": rock, "deco": deco,
		"rock_chance": rock_chance, "rock_scale": rock_scale}

static var _defs: Dictionary = {}


static func _build() -> void:
	if not _defs.is_empty():
		return
	var d := {}
	d[GREEN] = {"id": GREEN, "display_name": "ЗЕЛЁНЫЕ ХОЛМЫ", "special": false, "sky": "green", "props": "",
		"title_style": "green", "intro_always": false}
	d["moon"] = {"id": "moon", "display_name": "ЛУНА", "special": true, "gravity_scale": 0.45,
		"palette": _pal(Color(0.47, 0.48, 0.55), Color(0.36, 0.37, 0.44), Color(0.80, 0.81, 0.87), Color(0.96, 0.97, 1.0),
			Color(0.62, 0.63, 0.70), Color(0.66, 0.67, 0.74), Color(0.30, 0.31, 0.38), 0.75, 1.15),
		"sky": "moon", "props": "moon", "title_style": "moon"}
	d["heavy"] = {"id": "heavy", "display_name": "СВЕРХГРАВИТАЦИЯ", "special": true, "gravity_scale": 1.6, "feet_rebound": 0.86,
		"palette": _pal(Color(0.34, 0.20, 0.30), Color(0.25, 0.13, 0.22), Color(0.30, 0.70, 0.66), Color(0.66, 0.96, 0.90),
			Color(0.20, 0.48, 0.46), Color(0.42, 0.30, 0.40), Color(0.20, 0.10, 0.18), 0.8, 1.5),
		"sky": "heavy", "props": "heavy", "title_style": "heavy"}
	d["chocolate"] = {"id": "chocolate", "display_name": "ШОКОЛАДНЫЙ МИР", "special": true, "chocolate": true,
		"palette": _pal(Color(0.86, 0.62, 0.36), Color(0.74, 0.50, 0.27), Color(0.99, 0.70, 0.80), Color(1.0, 0.95, 0.97),
			Color(0.95, 0.40, 0.55), Color(0.62, 0.36, 0.20), Color(0.66, 0.44, 0.24), 0.0, 1.0),
		"sky": "chocolate", "props": "chocolate", "title_style": "chocolate"}
	d["jelly"] = {"id": "jelly", "display_name": "ЖЕЛЕЙНЫЙ МИР", "special": true, "jelly": true,
		"feet_rebound": 1.42, "rebound_cap": 1.4, "body_bounce": 0.3,
		"palette": _pal(Color(0.80, 0.22, 0.55, 0.92), Color(0.62, 0.12, 0.42, 0.92), Color(1.0, 0.50, 0.80), Color(1.0, 0.86, 0.96),
			Color(0.55, 0.90, 0.35), Color(0.40, 0.85, 0.55), Color(0.96, 0.55, 0.82), 0.0, 1.0),
		"sky": "jelly", "props": "jelly", "title_style": "jelly"}
	d["portal"] = {"id": "portal", "display_name": "ПОРТАЛЬНАЯ ЗОНА", "special": true, "portals": true,
		"palette": _pal(Color(0.30, 0.26, 0.48), Color(0.21, 0.18, 0.36), Color(0.45, 0.95, 0.88), Color(0.86, 1.0, 0.98),
			Color(0.62, 0.40, 0.95), Color(0.48, 0.42, 0.66), Color(0.55, 0.40, 0.90), 0.35, 1.0),
		"sky": "portal", "props": "portal", "title_style": "portal"}
	d["chasms"] = {"id": "chasms", "display_name": "ПРОПАСТИ", "special": true, "chasms": true,
		"palette": _pal(Color(0.56, 0.32, 0.20), Color(0.42, 0.22, 0.14), Color(0.86, 0.60, 0.36), Color(1.0, 0.84, 0.58),
			Color(0.55, 0.42, 0.22), Color(0.62, 0.40, 0.28), Color(0.36, 0.18, 0.11), 0.7, 1.2),
		"sky": "chasms", "props": "chasms", "title_style": "chasms"}
	d["cavern"] = {"id": "cavern", "display_name": "ПЕЩЕРА", "special": true, "ceiling": true,
		"palette": _pal(Color(0.36, 0.30, 0.27), Color(0.27, 0.22, 0.20), Color(0.70, 0.64, 0.52), Color(0.92, 0.88, 0.74),
			Color(0.40, 0.80, 0.70), Color(0.52, 0.47, 0.42), Color(0.22, 0.18, 0.16), 0.6, 1.1),
		"sky": "cavern", "props": "cavern", "title_style": "cavern"}
	d["zone"] = {"id": "zone", "display_name": "ЗОНА ОТЧУЖДЕНИЯ", "special": true, "anomalies": true,
		"palette": _pal(Color(0.36, 0.32, 0.23), Color(0.27, 0.24, 0.17), Color(0.56, 0.62, 0.28), Color(0.80, 0.84, 0.48),
			Color(0.42, 0.46, 0.18), Color(0.50, 0.48, 0.44), Color(0.22, 0.20, 0.14), 0.5, 1.1),
		"sky": "zone", "props": "zone", "title_style": "zone"}
	for k in d:
		_defs[k] = BiomeDef.from_dict(d[k])


static func get_def(id: String) -> BiomeDef:
	_build()
	return _defs.get(id, _defs[GREEN])


static func has(id: String) -> bool:
	_build()
	return _defs.has(id)


static func ids() -> Array:
	_build()
	return _defs.keys()
