class_name VisualRigProfile
extends RefCounted
## Read-only art geometry. RigData's gameplay anchors remain the authoritative physics rig.
var data: Dictionary = {}
var rig: RigData
func _init(p_rig: RigData) -> void:
	rig = p_rig
	var vid := rig.visual_id if rig.visual_id != "" else rig.robot_id
	data = RobotArtLibrary.visual_profile(vid) if not rig.art.is_empty() else {}
func enabled() -> bool:
	return not data.is_empty()
func part(key: String) -> Dictionary:
	return data.get("parts", {}).get(key, {})
func anchor(key: String, body: VideoRobotPart, torso: Sprite2D) -> Vector2:
	var point := RigData._v(data.anchors[key]) - RigData._v(part("torso").pivot)
	return torso.transform * (body.transform * point)
func limb_scale(key: String) -> float:
	return float(part(key).unit_scale) * rig.s / 0.42
