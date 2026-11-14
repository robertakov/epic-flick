class_name SkinDefinition
extends Resource
## PURELY COSMETIC appearance of one robot archetype. A skin only decides which module art is drawn and how it is
## recoloured - it never touches stats, physics, AI or damage (RobotDefinition / modules do that).
## v36 COLOUR SCHEMES: hierarchy Robot -> BASE / MK2 -> colour scheme. A scheme with `scheme` = <key> has its own
## repainted art for EACH version (assets/robots/<version dir>__<key>/, tools/players/build_color_schemes.py): same
## parts, sizes, pivots and manifest geometry, only colours differ. The palette shader below is only the legacy
## fallback for a version that has no repainted art.
## Default skins are generated from each RobotDefinition's palette; extra skins are .tres files listed in SkinCatalog.

@export var id := "skin"
@export var robot_id := "samurai"
@export var display_name := "Скин"
## Where the skin comes from: "default", "campaign" (boss reward), later "shop", "event", ...
@export var source := "default"
@export_group("Art")
## v36: colour-scheme key of the repainted art ("" = the version's own approved art).
@export var scheme := ""
## Module art set (same rig layout). Empty = the archetype's art.
@export var rig_json := ""
@export var texture_dir := ""
@export_group("Palette (shaders/robot_tint.gdshader)")
@export_range(-1.0, 1.0) var hue_shift := 0.0
@export var saturation := 1.0
@export var brightness := 1.0
@export var tint := Color.WHITE
@export_range(0.0, 1.0) var tint_amount := 0.0

const TINT_SHADER := preload("res://shaders/robot_tint.gdshader")


static func from_robot_default(d: RobotDefinition) -> SkinDefinition:
	var s := SkinDefinition.new()
	s.id = default_id(d.id)
	s.robot_id = d.id
	s.display_name = "Стандарт"
	s.source = "default"
	s.rig_json = d.rig_json
	s.texture_dir = d.texture_dir
	s.hue_shift = d.hue_shift
	s.saturation = d.saturation
	s.brightness = d.brightness
	s.tint = d.tint
	s.tint_amount = d.tint_amount
	return s


static func default_id(robot_id: String) -> String:
	return robot_id + "_default"


func is_original_palette() -> bool:
	return is_zero_approx(hue_shift) and is_equal_approx(saturation, 1.0) and is_equal_approx(brightness, 1.0) \
		and is_zero_approx(tint_amount)


func make_material() -> Material:
	if is_original_palette():
		return null
	var m := ShaderMaterial.new()
	m.shader = TINT_SHADER
	m.set_shader_parameter("hue_shift", hue_shift)
	m.set_shader_parameter("saturation", saturation)
	m.set_shader_parameter("brightness", brightness)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tint_amount", tint_amount)
	return m


## Visual id of this scheme's art for the BASE or MK2 version ("" art -> the version's own visual id).
func art_visual_id(archetype: RobotDefinition, mk2 := false) -> String:
	var base := archetype.mk2_visual_id if mk2 and archetype.has_mk2() else archetype.effective_visual_id()
	if scheme != "" and has_art(archetype, mk2):
		return base + "__" + scheme
	return base


func has_art(archetype: RobotDefinition, mk2 := false) -> bool:
	if scheme == "":
		return false
	var base := archetype.mk2_visual_id if mk2 and archetype.has_mk2() else archetype.effective_visual_id()
	return not RobotArtLibrary.manifest(base + "__" + scheme).is_empty()


## Applies the skin's appearance to a (per-robot copy of) RobotConfig: art (visual id) + palette material only.
## v36: works for BASE and MK2; never touches any physical / stat field.
func apply_visual(rc: RobotConfig, archetype: RobotDefinition, mk2 := false) -> void:
	rc.rig_json = rig_json if rig_json != "" else archetype.rig_json
	rc.texture_dir = texture_dir if texture_dir != "" else archetype.texture_dir
	rc.visual_id = art_visual_id(archetype, mk2)
	var original := source == "default" and not RobotArtLibrary.manifest(archetype.id).is_empty()
	# repainted art / MK2 approved art / original art: no shader. Only a version without repainted art falls back to
	# the legacy palette shader (base art only - MK2 art is never hue-shifted).
	rc.visual_material = null if (original or mk2 or has_art(archetype, mk2)) else make_material()
	rc.skin_id = id
