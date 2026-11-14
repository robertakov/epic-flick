class_name RigData
extends RefCounted
## Loads rig.json (anchors produced by tools/extract_assets.py) and converts everything into
## body-local world pixels. Body origin = torso centre, +Y = down along the legs.

var s := 0.42
var raw: Dictionary
var tex := {}
var robot_id := "samurai"
var visual_id := "samurai"
var art: Dictionary = {}
var torso_center := Vector2.ZERO
var expressions: PackedStringArray = []

const TEXTURES := ["torso", "head_neutral", "head_scared", "head_angry", "head_determined", "head_happy",
	"head_dizzy", "arm_l_shoulder", "arm_l_fist", "arm_r_shoulder", "arm_r_fist", "leg_l_cap", "leg_l_boot",
	"leg_r_cap", "leg_r_boot", "coil_ring"]


func _init(cfg: RobotConfig) -> void:
	s = cfg.rig_scale
	robot_id = cfg.robot_id
	visual_id = cfg.visual_id if cfg.visual_id != "" else cfg.robot_id
	if cfg.texture_dir == "res://assets/robot/":
		art = RobotArtLibrary.manifest(visual_id)
	raw = JSON.parse_string(FileAccess.get_file_as_string(cfg.rig_json))
	for n in TEXTURES:
		tex[n] = load(cfg.texture_dir + n + ".png")
	torso_center = _v(raw.torso.center)
	expressions = PackedStringArray(raw.head.expressions)


static func _v(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


## A torso anchor in body-local world px.
func torso_point(key: String) -> Vector2:
	return (_v(raw.torso[key]) - torso_center) * s


## Anchor of a sub-sprite relative to that sprite's top-left, in world px.
func piece_point(part: String, piece: String, key: String) -> Vector2:
	return _v(raw[part][piece][key]) * s


func coil_rest_vec(part: String) -> Vector2:
	return _v(raw[part].coil_rest_vec) * s


func head_point(key: String) -> Vector2:
	return _v(raw.head[key]) * s
