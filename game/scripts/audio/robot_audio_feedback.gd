class_name RobotAudioFeedback
extends Node
## Read-only adapter to existing controller signals/state. Components override profile families.
var robot: RobotController
var audio: GameAudio
var terrain: TerrainBuilder
var overrides: Dictionary = {}
var additive_layers: Dictionary = {}
var robot_id := ""
var owner_key := ""
var head: RocketHead
var launched := false
var head_started := false
var head_air_time := 10.0
var head_speed_before := 0.0
var lost: Dictionary = {}
var pending_impact := ""
var pending_intensity := 0.0
var flush_pending := false
var charge_clock := 0.0
## v38: other robots' loops (rocket-head flight, rolling, leg thrust) and flick whoosh are only a faint positional
## cue (-22 dB / -12 dB): they must never compete with the player's own robot.
const NPC_LOOP_GAIN := 0.08
const NPC_LAUNCH_GAIN := 0.25
## v39: every robot has a RobotSoundSet; a rival's one-shots play at this gain (-10 dB) on top of distance.
const NPC_ONESHOT_GAIN := 0.32
## v40 (APK v36.7) player energy: NO continuous loop. Stored charge is heard as sparse individual electrical
## discharges whose random interval shortens and whose level rises (strongly non-linear) with the charge; one
## completion event at 100 %, then silence. Player only, airborne, body phase. Rivals: discharge at NPC gain only.
const CHARGE_FULL := "v40/energy_full"
const SPARK_MIN := 0.2          # below 20 % charge: silent
const SPARK_FAMILIES := ["v40/charge_micro", "v40/charge_crackle", "v40/charge_snap", "v40/charge_nearfull"]
## (charge, mean seconds between discharges) - log-interpolated; actual interval = mean x random 0.55..1.6
const SPARK_CURVE := [[0.2, 7.0], [0.35, 5.0], [0.5, 3.2], [0.65, 2.0], [0.75, 1.3], [0.85, 0.8], [0.92, 0.55], [0.97, 0.38], [0.999, 0.3]]
const FULL_REARM := 0.9         # the 100 % cue re-arms only after the charge fell below 90 %
var spark_t := -1.0
var full_armed := true
func loop_gain() -> float: return 1.0 if is_player else NPC_LOOP_GAIN
var thrust_prev: Dictionary = {}
var rolling_contact := 0.0
var rolling_gap := 0.0
var rolling_latched := false
## Wilhelm easter egg (player only): 30 m above the local ground, one 10% roll per separate high jump.
var wilhelm := WilhelmTrigger.new()
var is_player := false
var px_per_meter := 100.0
## v37: robot-specific sound set (RobotSoundSet); null = v27 bank profile path (robots without a set yet).
var sound_set: RobotSoundSet
var pending_raw := 0.0
var head_was_burning := false
var died := false

func setup(r: RobotController, a: GameAudio, t: TerrainBuilder) -> void:
	robot=r; audio=a; terrain=t
	robot_id=r.visual.rig.robot_id
	owner_key="robot:%d:"%r.get_instance_id()
	sound_set=RobotSoundSet.for_robot(String(r.config.robot_id) if r.config else robot_id,a,owner_key)

func _ready() -> void:
	robot.landed.connect(landing)
	robot.body_hit.connect(impact)
	robot.limb_lost.connect(limb)
	robot.rocket_launched.connect(head_launch)
	robot.charge_released.connect(func(c: float, _v: Vector2, _i: Dictionary) -> void: discharge(c))
	if sound_set:
		sound_set.gain_scale=1.0 if is_player else NPC_ONESHOT_GAIN
		robot.damaged.connect(limb_damage)
		if robot.damage:
			robot.damage.rocket_triggered.connect(destroyed)
	if robot.spin_charge:
		robot.spin_charge.charge_full.connect(full_charge)

## v40: 100 % reached (also via the electric anomaly fill): ONE completion event per fill, player only.
func full_charge() -> void:
	if not is_player or not is_instance_valid(robot) or not robot.launched or not full_armed: return
	full_armed=false
	audio.play(CHARGE_FULL,1.0,owner_key+"charge_full",.4,"Robot",robot.global_position,1.0)

## v40: mean seconds between charge discharges (INF = silent: below 20 % and at 100 %).
static func spark_interval(ratio: float) -> float:
	if ratio<SPARK_MIN or ratio>=.999: return INF
	for k in range(1,SPARK_CURVE.size()):
		var a: Array = SPARK_CURVE[k-1]
		var b: Array = SPARK_CURVE[k]
		if ratio<=float(b[0]):
			var u := (ratio-float(a[0]))/(float(b[0])-float(a[0]))
			return exp(lerpf(log(float(a[1])),log(float(b[1])),u))
	return float(SPARK_CURVE[-1][1])

## v40: linear level of one discharge: ~-30 dB at 30 %, ~-17 dB at 50 %, ~-7 dB at 75 %, ~-1 dB near full
## (on top of the per-tier sample loudness micro -31 / crackle -26 / snap -23 / near-full -21 LUFS).
static func spark_level(ratio: float) -> float:
	var t := clampf((ratio-SPARK_MIN)/(1.0-SPARK_MIN),0.0,1.0)
	return 0.03+0.97*pow(t,2.2)

## v40: tier for a charge with a soft random overlap at the borders (roll 0..1 from the AUDIO rng).
static func spark_family(ratio: float, roll: float) -> String:
	var x := ratio+(roll-0.5)*0.12
	if x<0.5: return SPARK_FAMILIES[0]
	if x<0.75: return SPARK_FAMILIES[1]
	if x<0.95: return SPARK_FAMILIES[2]
	return SPARK_FAMILIES[3]

## v40 scheduler step (player only). eligible = airborne body phase while charging; returns true when a spark played.
func spark_step(ratio: float, eligible: bool, dt: float, point: Vector2) -> bool:
	var mean := spark_interval(ratio) if eligible else INF
	if mean==INF:
		spark_t=-1.0
		return false
	if spark_t<0.0:
		spark_t=mean*audio.rng.randf_range(.5,1.5)     # entering: never an immediate spark
		return false
	spark_t-=dt
	if spark_t>0.0: return false
	spark_t=mean*audio.rng.randf_range(.55,1.6)
	var fam := spark_family(ratio,audio.rng.randf())
	audio.play_level(fam,ratio,spark_level(ratio)*audio.rng.randf_range(.85,1.0),point,.02)
	return true

## v37 set: feet landings by authoritative landing class + impact; a charged feet landing gets its own response.
func set_landing(info: Dictionary) -> void:
	var type := String(info.get("type",""))
	if type not in ["left","right","both","poor"]: return
	var imp := float(info.get("impact",0.0))
	var charged := float(info.get("charge_ratio",0.0))>=float(sound_set.spec("charged").get("min_charge",.2)) and String(info.get("charge_zone","feet"))=="feet"
	if charged and sound_set.trigger("charged",imp,robot.global_position): return
	if sound_set.intensity("land",imp)>=0.0: sound_set.trigger("land",imp,robot.global_position)
	else: sound_set.trigger("step",imp,robot.global_position)

## limb / feet damage: a quiet dry armour tick on top of the contact sound (own channel, long cooldown).
func limb_damage(amount: float, zone_class: StringName, _health: float, info: Dictionary) -> void:
	if amount<1.0 or zone_class!=&"feet" or died: return
	sound_set.trigger("armor",amount,info.get("point",robot.global_position))

## destruction (0 HP, no limbs left): the robot breaks apart; the rocket ignition follows as its own event.
func destroyed(_info: Dictionary) -> void:
	if died: return
	died=true
	sound_set.trigger("death",1.0,robot.global_position)

func family(event: String) -> String:
	# v37: a robot sound set may name its own family for adapter events (launch / rolling / voice / energy)
	if sound_set:
		var own := String((sound_set.setting("families",{}) as Dictionary).get(event,""))
		if own!="": return own
	return audio.resolve(robot_id,event,overrides)

func event(event_name: String, intensity: float, dedup := "", cooldown := .14) -> bool:
	var g := .5 if event_name=="voice" else 1.0
	if event_name=="launch" and not is_player: g*=NPC_LAUNCH_GAIN
	var result := audio.play(family(event_name),intensity,owner_key+(event_name if dedup=="" else dedup),cooldown,"Voice" if event_name=="voice" else "Robot",robot.global_position,g)
	# Optional future armor/module layers, separate from primary component substitution.
	for extra in additive_layers.get(event_name,[]): audio.play(String(extra),intensity,owner_key+String(extra),cooldown,"Robot",robot.global_position,.35)
	return result

func landing(info: Dictionary) -> void:
	if sound_set: set_landing(info); return
	if String(info.get("type","")) not in ["left","right","both"] or float(info.get("impact",0.0))<200: return
	event("spring",clampf(float(info.impact)/1600.0,0,1),"spring",.16)

func impact(info: Dictionary) -> void:
	var strength := clampf(float(info.get("impact",0.0))/1600.0,0,1)
	if strength<.10: return
	var kind := "head" if String(info.get("kind",""))=="head" else "body"
	if pending_impact!="head" or kind=="head": pending_impact=kind
	pending_intensity=maxf(pending_intensity,strength)
	pending_raw=maxf(pending_raw,float(info.get("impact",0.0)))
	if not flush_pending:
		flush_pending=true; call_deferred("flush_impact")

func flush_impact() -> void:
	if not is_instance_valid(robot): return
	if sound_set:
		# torso / head / arm hits of one physics step were merged above: ONE response, body or (escalated) crash
		sound_set.trigger("body",pending_raw,robot.global_position)
		pending_impact="";pending_intensity=0;pending_raw=0;flush_pending=false
		return
	event(pending_impact,pending_intensity,"impact",.14)
	if pending_intensity>.8 and robot.damage.health>0: vocal(pending_intensity)
	pending_impact="";pending_intensity=0;flush_pending=false

func limb(side: StringName, part: RigidBody2D) -> void:
	var key := str(side)+":"+str(part.get_instance_id() if is_instance_valid(part) else 0)
	if lost.has(key): return
	lost[key]=true
	if sound_set: sound_set.trigger("detach",1.0,part.global_position if is_instance_valid(part) else robot.global_position)
	else: event("limb",.7,"limb:"+key,0.0)
	# Future leg-attached propulsion loop uses this same side key; dies with the real part.
	audio.stop_owner(owner_key+"leg:"+String(side))

func head_launch(value: RigidBody2D) -> void:
	if head_started: return
	head_started=true;head=value as RocketHead
	if sound_set:
		head_was_burning=is_instance_valid(head) and head.burning
		sound_set.trigger("ignite",1.0,value.global_position if is_instance_valid(value) else robot.global_position)
		return
	event("head_launch",1.0,"head_launch",0.0)

func vocal(strength: float) -> void:
	if sound_set and not bool(sound_set.setting("voice",true)): return
	if family("voice")=="": return
	# v39: a set may make shouts rarer (voice_probability / voice_cooldown); rivals never shout
	if sound_set and not is_player: return
	var cd := float(sound_set.setting("voice_cooldown",8.0)) if sound_set else 8.0
	var prob := float(sound_set.setting("voice_probability",audio.bank.get("voice_probability",.18))) if sound_set else float(audio.bank.get("voice_probability",.18))
	if audio.clock-float(audio.cooldowns.get(owner_key+"voice",-100))<cd: return
	if audio.rng.randf()<prob: event("voice",strength,"voice",cd)

func charge_interval(ratio: float) -> float: return lerpf(1.6,.42,clampf(ratio,0,1))

func discharge(ratio: float) -> void:
	charge_clock=0.0
	if ratio<.015: return
	var dg := float(sound_set.setting("discharge_gain",1.0)) if sound_set else 1.0
	dg*=lerpf(.55,1.15,clampf(ratio,0,1))     # v40: the release scales with the stored charge
	if not is_player: dg*=NPC_ONESHOT_GAIN
	audio.play(family("energy"),ratio,owner_key+"discharge",.14,"Robot",robot.global_position,1.1*dg)
	if ratio>.85:
		# Two compact impulses, delayed only in presentation; never touch charge mechanics.
		var point := robot.global_position
		get_tree().create_timer(.035,true,false,true).timeout.connect(func() -> void:
			if is_instance_valid(audio): audio.play(family("energy"),ratio,owner_key+"discharge_layer",.14,"Robot",point,.45*dg))
		vocal(ratio)

## height_px: local ground surface minus body y (px). Read-only: never writes robot / head / physics state.
func wilhelm_step(height_px: float) -> bool:
	if not is_player or not launched: return false
	if not wilhelm.step(height_px/maxf(px_per_meter,.001),audio.rng): return false
	audio.play("common/wilhelm",1.0,owner_key+"wilhelm",0,"Voice",head.global_position if is_instance_valid(head) else robot.global_position,.9)
	return true

func rolling_strength(contact: bool, speed: float, burning: bool, done: bool, dt: float) -> float:
	rolling_contact=rolling_contact+dt if contact else 0.0
	rolling_gap=0.0 if contact else rolling_gap+dt
	if contact and rolling_contact>=.05: rolling_latched=true
	if rolling_gap>=.10: rolling_latched=false
	if burning or done or not rolling_latched: return 0.0
	return clampf((speed-25.0)/650.0,0,1)

func _process(dt: float) -> void:
	if not is_instance_valid(robot) or not is_instance_valid(audio): return
	var real_dt := dt/maxf(Engine.time_scale,.01)
	if robot.launched and not launched:
		launched=true;event("launch",clampf(robot.linear_velocity.length()/1800.0,0,1),"launch",0)
		# v39: each robot's own take-off gesture under the shared air whoosh
		if sound_set: sound_set.trigger("takeoff",robot.linear_velocity.length(),robot.global_position)
		if robot.linear_velocity.length()>1600: vocal(.9)
	var point := robot.global_position
	var contact := robot.contacts.any_leg_contact or robot.contacts.any_body_contact
	var active := robot.launched and not robot.freeze
	if is_instance_valid(head):
		point=head.global_position;contact=head.get_contact_count()>0;active=not head.done
		if contact:
			if head_air_time>.12 and head_speed_before>160:
				if sound_set: sound_set.trigger("head_bump",head_speed_before,point)
				else: event("head",clampf(head_speed_before/1600.0,0,1),"impact",.14)
			head_air_time=0.0
		else: head_air_time+=real_dt
		head_speed_before=head.linear_velocity.length()
		var burning := head.burning and not head.done
		if sound_set:
			# thrust follows the authoritative burn state: loop while burning, one short burn-out, then nothing
			var th := sound_set.spec("thrust")
			var level := float(th.get("base",.42))+float(th.get("speed",.3))*clampf(head.linear_velocity.length()/1800.0,0,1) if burning else 0.0
			audio.loop_target(owner_key+"flight",String(th.get("family","")),level,point,loop_gain())
			head_was_burning=burning
		else:
			var flight := .35+.4*clampf(head.linear_velocity.length()/1800.0,0,1) if burning else 0.0
			audio.loop_target(owner_key+"flight",family("flight"),flight,point,loop_gain())
		var rolling := rolling_strength(contact,head.linear_velocity.length(),head.burning,head.done,real_dt)
		audio.loop_target(owner_key+"rolling",family("rolling"),rolling,point,loop_gain())
	if not active:
		audio.loop_target(owner_key+"flight","",0.0,point)
		audio.loop_target(owner_key+"rolling","",0.0,point)
		return
	if not is_instance_valid(head):
		# v40: charge accumulation = sparse electrical discharges (player only, airborne); no loop at all
		var ratio := robot.spin_charge.ratio()
		if ratio<FULL_REARM: full_armed=true
		# a destroyed body (0 HP, before / without the rocket) still holds its charge value: it must stay silent
		var alive := not died and (robot.damage==null or robot.damage.health>0.0)
		spark_step(ratio,is_player and alive and not contact,real_dt,point)
		for side in robot.visual.legs:
			var leg: LegVisual = robot.visual.legs[side]
			var thrust := leg.exhaust.intensity if leg.exhaust and leg.leg!=null and leg.leg.attached else 0.0
			audio.loop_target(owner_key+"leg:"+String(side),family("leg_thrust"),thrust,point,loop_gain())
			# v39 Chronobot: a valve puff when a thruster opens (authoritative exhaust state), the loop carries it on
			if sound_set and thrust>.1 and float(thrust_prev.get(side,0.0))<=.035:
				sound_set.trigger("thrust_burst",1.0,point)
			thrust_prev[side]=thrust
	wilhelm_step(terrain.surface_y(point.x)-point.y)

func _exit_tree() -> void:
	if is_instance_valid(audio): audio.stop_owner(owner_key)
