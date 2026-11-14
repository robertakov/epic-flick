class_name RobotDefinition
extends Resource
## One of the five permanent robot ARCHETYPES (Жестянка, Попрыгун, Тяжеловес, Ракета, Самурай). Gameplay code never
## branches on the robot: an archetype's base STATS (+ future gameplay modules, see ModuleDefinition) produce
## per-robot COPIES of the shared configs. Appearance is NOT part of the build: SkinDefinition (cosmetic only)
## decides art + palette. The palette fields below are this archetype's DEFAULT skin (SkinCatalog generates it).
## All multipliers are relative to the original Samurai tuning (1.0 = unchanged physics).

@export var id := "robot"
@export var visual_id := ""
@export var display_name := "Робот"
@export_multiline var description := ""
## Price in in-game coins (earned by playing). 0 + starter = owned from the start.
@export var price := 0
@export var starter := false

func effective_visual_id() -> String:
	return visual_id if visual_id != "" else id

@export_group("Stats")
@export var max_health := 100.0
## Scales every body part mass (springs are scaled with it, so the bounce frequency stays the same).
@export var mass_multiplier := 1.0
## Spring stiffness on top of the mass scaling (>1 = stiffer, livelier springs).
@export var spring_strength := 1.0
## Spring energy return on release (landing gains and their energy-guard limits). Keep within ~0.85..1.15.
@export var bounce := 1.0
## Spin-charge impulse multiplier.
@export var energy_boost_multiplier := 1.0
## Spin-charge gain per turn multiplier.
@export var charge_rate := 1.0
## Air control: how fast the spin follows the input (rotation response multiplier).
@export var air_control := 1.0
## Overall size (rig scale, hit shapes and leg lengths).
@export var size := 1.0
## v32 momentum chain (MomentumRules): forward boost gained per clean landing, its ceiling and the forward speed at
## which the boost fades out (px/s).
@export var momentum_gain := 55.0
@export var momentum_max := 220.0
@export var momentum_forward_cap := 1800.0
## v32 natural feet-rebound strength along the surface normal (1.0 = shared tuning; Kengurobot > 1).
@export var rebound_power := 1.0
## v32 main-body (torso capsule) hit size relative to `size` (Sumobot: art stays huge, body collider ~ normal robot).
@export var body_hit_scale := 1.0

@export_group("MK2 (v35 upgraded gameplay variant)")
## MK2 = the SAME archetype (same id, rig, colliders, mass, size) with its own approved art (visual id) and a small,
## identity-preserving set of stat changes (a ModuleDefinition). Unlocked by beating mk2_boss_node, then bought.
@export var mk2_visual_id := ""
## Coins; -1 = no approved price yet (MK2 is shown but can not be bought).
@export var mk2_price := -1
## Campaign node whose completion makes the MK2 purchasable for that profile.
@export var mk2_boss_node := ""
@export var mk2_stat_multipliers := {}
@export var mk2_stat_offsets := {}

## Stats the MK2 module may NEVER touch (collision / physical identity must stay the base robot's).
const MK2_FORBIDDEN := ["size", "mass_multiplier", "body_hit_scale"]


func has_mk2() -> bool:
	return mk2_visual_id != ""


func mk2_purchasable() -> bool:
	return has_mk2() and mk2_price > 0


## The MK2 stat changes as a runtime module (forbidden physical keys are dropped).
func mk2_module() -> ModuleDefinition:
	var m := ModuleDefinition.new()
	m.id = id + "_mk2"
	m.slot = "mk2"
	m.robot_ids = PackedStringArray([id])
	for k in mk2_stat_multipliers:
		if not (k in MK2_FORBIDDEN):
			m.stat_multipliers[k] = float(mk2_stat_multipliers[k])
	for k in mk2_stat_offsets:
		if not (k in MK2_FORBIDDEN):
			m.stat_offsets[k] = float(mk2_stat_offsets[k])
	return m

@export_group("Default skin (cosmetic - see SkinDefinition)")
@export var rig_json := "res://assets/robot/rig.json"
@export var texture_dir := "res://assets/robot/"
## Palette swap of the module art (shader res://shaders/robot_tint.gdshader).
@export_range(-1.0, 1.0) var hue_shift := 0.0
@export var saturation := 1.0
@export var brightness := 1.0
@export var tint := Color.WHITE
@export_range(0.0, 1.0) var tint_amount := 0.0

const TINT_SHADER := preload("res://shaders/robot_tint.gdshader")


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


## Gameplay stats of the archetype (the only values gameplay modules may change).
func base_stats() -> Dictionary:
	return {"max_health": max_health, "mass_multiplier": mass_multiplier, "spring_strength": spring_strength,
		"bounce": bounce, "energy_boost_multiplier": energy_boost_multiplier, "charge_rate": charge_rate,
		"air_control": air_control, "size": size, "momentum_gain": momentum_gain, "momentum_max": momentum_max,
		"momentum_forward_cap": momentum_forward_cap, "rebound_power": rebound_power}


## Returns {"robot": RobotConfig, "contact": ContactConfig, "damage": DamageConfig, "stats": Dictionary} -
## fresh copies. modules: Array[ModuleDefinition] (empty today). The skin is applied by the caller
## (SkinDefinition.apply_visual) and can never change these numbers.
func make_configs(base_robot: RobotConfig, base_contact: ContactConfig, base_damage: DamageConfig, modules: Array = []) -> Dictionary:
	var st := ModuleDefinition.apply_all(base_stats(), modules)
	var mass_multiplier: float = st.mass_multiplier
	var size: float = st.size
	var spring_strength: float = st.spring_strength
	var bounce: float = st.bounce
	var rc: RobotConfig = base_robot.duplicate()
	rc.torso_mass *= mass_multiplier
	rc.head_mass *= mass_multiplier
	rc.arm_mass *= mass_multiplier
	rc.leg_mass *= mass_multiplier
	rc.rotation_response *= float(st.air_control)
	rc.rig_scale *= size
	rc.inertia_radius *= size
	rc.rig_json = rig_json
	rc.texture_dir = texture_dir
	rc.charge_rate = float(st.charge_rate)
	rc.energy_boost_multiplier = float(st.energy_boost_multiplier)
	rc.visual_material = null   # appearance = skin (applied by the caller)
	rc.robot_id = id
	rc.visual_id = effective_visual_id()
	rc.torso_hit_scale = body_hit_scale

	var cc: ContactConfig = base_contact.duplicate(true)
	cc.spring_stiffness *= spring_strength * mass_multiplier
	cc.bottom_out_stiffness *= mass_multiplier
	cc.coil_rest_length *= size
	cc.coil_min_length *= size
	cc.coil_max_length *= size
	cc.foot_half_width *= size
	for g in ["gain_left", "gain_right", "gain_both_normal", "gain_both_flat", "gain_both_sweet", "gain_poor"]:
		cc.set(g, float(cc.get(g)) * bounce)
	var ratios: Dictionary = cc.max_speed_ratio.duplicate()
	for k in ratios:
		ratios[k] = float(ratios[k]) * bounce
	cc.max_speed_ratio = ratios
	cc.momentum_gain = maxf(float(st.momentum_gain), 0.0)
	cc.momentum_max = maxf(float(st.momentum_max), 0.0)
	cc.momentum_forward_cap = maxf(float(st.momentum_forward_cap), 1.0)
	cc.rebound_power = float(st.rebound_power)

	var dc: DamageConfig = base_damage.duplicate()
	dc.max_health = float(st.max_health)
	return {"robot": rc, "contact": cc, "damage": dc, "stats": st}
