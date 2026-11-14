class_name RobotArtLibrary
extends RefCounted
## Shared immutable atlas/manifest cache. Physics rig.json remains the authoritative rig.
static var _manifests: Dictionary = {}
static var _textures: Dictionary = {}
static var _visual_profiles: Dictionary = {}

const VISUAL_TO_ASSET_DIR := {
	"rasta": "tin",
	"kenguru": "hopper",
	"sumo": "heavy",
	"chronos": "rocket",
	"tin": "tin",
	"hopper": "hopper",
	"heavy": "heavy",
	"rocket": "rocket",
	"samurai": "samurai",
	# v35 MK2 visual rigs (same physical archetype, own approved art)
	"rasta_mk2": "tin_mk2",
	"kenguru_mk2": "hopper_mk2",
	"sumo_mk2": "heavy_mk2",
	"chronos_mk2": "rocket_mk2",
	"samurai_mk2": "samurai_mk2",
}

static func resolve_asset_id(id_or_visual: String) -> String:
	# v36 colour schemes: "<visual>__<scheme>" -> "<version dir>__<scheme>"
	var cut := id_or_visual.find("__")
	if cut > 0:
		return String(VISUAL_TO_ASSET_DIR.get(id_or_visual.substr(0, cut), id_or_visual.substr(0, cut))) + id_or_visual.substr(cut)
	return String(VISUAL_TO_ASSET_DIR.get(id_or_visual, id_or_visual))

static func visual_profile(id: String) -> Dictionary:
	var dir_id := resolve_asset_id(id)
	if not _visual_profiles.has(dir_id):
		var path := "res://assets/robots/%s/visual_rig.json" % dir_id
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
		_visual_profiles[dir_id] = parsed if parsed is Dictionary else {}
	return _visual_profiles[dir_id]


static func manifest(id: String) -> Dictionary:
	var dir_id := resolve_asset_id(id)
	if _manifests.has(dir_id):
		return _manifests[dir_id]
	var path := "res://assets/robots/%s/manifest.json" % dir_id
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed
	_manifests[dir_id] = data
	return data

static func atlas(id: String, part: String) -> Texture2D:
	var dir_id := resolve_asset_id(id)
	var key := dir_id + "/" + part
	if not _textures.has(key):
		_textures[key] = load("res://assets/robots/%s/%s.png" % [dir_id, part])
	return _textures[key]


static func icon(rig: RigData, part: String) -> Texture2D:
	if rig.art.has("parts") and rig.art.parts.has(part):
		var spec: Dictionary = rig.art.parts[part]
		var frame := int(spec.clips.idle[0])
		var texture := AtlasTexture.new()
		texture.atlas = atlas(rig.visual_id, part)
		texture.region = Rect2(Vector2(frame % int(spec.columns), frame / int(spec.columns)) * Vector2(spec.frame_size[0], spec.frame_size[1]), Vector2(spec.frame_size[0], spec.frame_size[1]))
		return texture
	var names := {"head": "head_neutral", "torso": "torso", "arm_l": "arm_l_fist", "arm_r": "arm_r_fist", "leg_l": "leg_l_boot", "leg_r": "leg_r_boot"}
	return rig.tex[names[part]]
