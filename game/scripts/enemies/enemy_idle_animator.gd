class_name EnemyIdleAnimator
extends RefCounted
## Character-specific procedural UI/preview idle choreography for the five visual enemy identities.
## Animates modular parts (torso, head, arm_l, arm_r, leg_l, leg_r, and facial clips) while keeping
## all sockets connected via VisualRigProfile.anchor() and never touching gameplay physics or AI.

static func compute_pose(enemy_id: String, t: float) -> Dictionary:
	var pose := {
		"body_pos": Vector2.ZERO,
		"body_rot": 0.0,
		"body_scale": Vector2.ONE,
		"head_angle": 0.0,
		"head_bob": Vector2.ZERO,
		"arm_l_offset": Vector2.ZERO,
		"arm_r_offset": Vector2.ZERO,
		"foot_l_offset": Vector2.ZERO,
		"foot_r_offset": Vector2.ZERO,
		"foot_l_rot": 0.0,
		"foot_r_rot": 0.0,
		"rig_rot": 0.0,
		"expression": &"neutral",
	}
	match enemy_id:
		"devil":
			# Наглый, энергичный, нетерпеливый, будто провоцирует игрока:
			# резкие пружинящие подскоки, боксёрские выпады кулаками и дерзкие кивки головой.
			var w := t * TAU * 1.95
			var s1 := sin(w)
			var c1 := cos(w)
			var snap_hop := -22.0 * pow(maxf(0.0, s1), 1.5) + 9.0 * maxf(0.0, -s1)
			var sway := sin(w * 0.5)
			var jab := pow(maxf(0.0, sin(w + 0.5)), 2.0)
			pose.body_pos = Vector2(sway * 13.0 + jab * 6.0, snap_hop)
			pose.body_rot = sway * 0.13 + jab * 0.08
			pose.body_scale = Vector2(1.0 - snap_hop * 0.0025, 1.0 + snap_hop * 0.0025)
			pose.head_angle = -sway * 0.22 + jab * 0.18 + 0.08 * c1
			pose.head_bob = Vector2(jab * 6.5, -absf(c1) * 4.5)
			# Alternating impatient boxing fist jabs
			pose.arm_l_offset = Vector2(-10.0 - 16.0 * maxf(0.0, s1), -24.0 * maxf(0.0, s1) + 6.0 * maxf(0.0, -s1))
			pose.arm_r_offset = Vector2(10.0 + 16.0 * maxf(0.0, -s1), -24.0 * maxf(0.0, -s1) + 6.0 * maxf(0.0, s1))
			# Restless alternating foot taps
			var tap_l := maxf(0.0, s1) * -9.0
			var tap_r := maxf(0.0, -s1) * -9.0
			pose.foot_l_offset = Vector2(-2.0 * maxf(0.0, s1), tap_l)
			pose.foot_r_offset = Vector2(2.0 * maxf(0.0, -s1), tap_r)
			pose.foot_l_rot = tap_l * 0.018
			pose.foot_r_rot = -tap_r * 0.018
			pose.rig_rot = 0.045 * sway
			if fmod(t, 3.2) > 1.9:
				pose.expression = &"happy"
		"vampire":
			# Спокойный, надменный, контролируемый:
			# медленное аристократичное дыхание/парение, плавный разворот плеч/плаща и высокомерный наклон головы.
			var w := t * TAU * 0.78
			var breath := sin(w)
			var poise := cos(w)
			pose.body_pos = Vector2(poise * 8.0, -16.0 * breath)
			pose.body_rot = poise * 0.085
			pose.body_scale = Vector2(1.0 + breath * 0.045, 1.0 + breath * 0.025)
			# Haughty chin lift and aristocratic tilt
			pose.head_angle = -poise * 0.19 - 0.07 * breath
			pose.head_bob = Vector2(poise * 4.0, -5.0 * maxf(0.0, breath))
			# Symmetrical cape-presentation sweep of the arms
			var spread := breath * 0.5 + 0.5
			pose.arm_l_offset = Vector2(-22.0 * spread + 4.0, -20.0 * spread + 7.0)
			pose.arm_r_offset = Vector2(22.0 * spread - 4.0, -20.0 * spread + 7.0)
			pose.foot_l_rot = -0.04 * maxf(0.0, breath)
			pose.foot_r_rot = 0.04 * maxf(0.0, breath)
			pose.rig_rot = 0.03 * poise
			if fmod(t, 4.8) > 3.2:
				pose.expression = &"happy"
		"cowboy":
			# Расслабленный, уверенный дуэлянт, который ждёт соперника:
			# широкий перенос веса с ноги на ногу, наклон шляпы и рука наготове у кобуры.
			var w := t * TAU * 0.92
			var shift := sin(w)
			var dip := absf(cos(w))
			pose.body_pos = Vector2(shift * 16.0, dip * 9.0 - 2.0)
			pose.body_rot = -shift * 0.115
			# Duelist hat-brim nod then level gaze
			pose.head_angle = shift * 0.18 + cos(w) * 0.12
			pose.head_bob = Vector2(shift * 4.5, dip * 4.0)
			# Left hand relaxed, right gun-hand hovering and twitching near holster
			var draw_ready := maxf(0.0, -shift)
			pose.arm_l_offset = Vector2(-6.0 + shift * 8.0, 6.0 - 8.0 * draw_ready)
			pose.arm_r_offset = Vector2(16.0 * draw_ready + 4.0, -16.0 * draw_ready + 4.0 * shift)
			pose.foot_l_rot = -shift * 0.045
			pose.foot_r_rot = -shift * 0.045
			pose.rig_rot = 0.04 * shift
			if fmod(t, 4.2) > 2.8:
				pose.expression = &"happy"
		"tiger":
			# Хищный, пружинистый, напряжённый, будто готов прыгнуть:
			# глубокий упругий присед с накоплением энергии в пружинах, фиксированный взгляд хищника и взведённые когти.
			var cycle := fmod(t * 1.25, 1.0)
			var crouch := 0.0
			var tremor := 0.0
			if cycle < 0.56:
				var u := cycle / 0.56
				crouch = smoothstep(0.0, 1.0, u) * 24.0
				tremor = sin(t * TAU * 15.0) * u * 1.8
			elif cycle < 0.78:
				var u := (cycle - 0.56) / 0.22
				crouch = lerpf(24.0, -18.0, smoothstep(0.0, 1.0, u))
			else:
				var u := (cycle - 0.78) / 0.22
				crouch = lerpf(-18.0, 0.0, smoothstep(0.0, 1.0, u))
			var stalk := sin(t * TAU * 1.25)
			pose.body_pos = Vector2(stalk * 9.0 + tremor, crouch)
			pose.body_rot = (crouch / 24.0) * 0.13 + stalk * 0.05
			pose.body_scale = Vector2(1.0 + (crouch / 24.0) * 0.06, 1.0 - (crouch / 24.0) * 0.05)
			# Head counter-rotates to keep a locked predatory stare on the target
			pose.head_angle = -pose.body_rot * 1.45 + stalk * 0.10
			pose.head_bob = Vector2(stalk * 4.5, -maxf(0.0, crouch) * 0.28)
			# Claws flare high and wide as the tiger coils, then rake down on release
			var claw := clampf(crouch / 24.0, -0.75, 1.0)
			pose.arm_l_offset = Vector2(-18.0 * claw - 5.0, -22.0 * claw)
			pose.arm_r_offset = Vector2(18.0 * claw + 5.0, -22.0 * claw)
			pose.foot_l_offset = Vector2(-3.0 * maxf(0.0, claw), 0.0)
			pose.foot_r_offset = Vector2(3.0 * maxf(0.0, claw), 0.0)
			pose.rig_rot = 0.04 * stalk
		"shark":
			# Хищный, немного странный, движется иначе, чем остальные:
			# непрерывное синусоидальное скольжение «восьмёркой» и волнообразные движения плавников-рук и головы.
			var w := t * TAU * 1.15
			var glide_x := sin(w)
			var glide_y := sin(w * 2.0)
			pose.body_pos = Vector2(glide_x * 17.0, glide_y * 10.5)
			pose.body_rot = cos(w) * 0.145
			pose.body_scale = Vector2(1.0 + 0.035 * sin(w * 2.0), 1.0 - 0.035 * sin(w * 2.0))
			# Phase-shifted S-wave snout sweep
			pose.head_angle = -sin(w - 0.9) * 0.24
			pose.head_bob = Vector2(sin(w - 0.7) * 7.5, cos(w * 2.0) * 3.5)
			# Banking hydroplane pectoral fin-arms
			pose.arm_l_offset = Vector2(-10.0 + 14.0 * sin(w - 1.0), -18.0 * cos(w - 1.0))
			pose.arm_r_offset = Vector2(10.0 + 14.0 * sin(w - 1.0), 18.0 * cos(w - 1.0))
			pose.foot_l_rot = cos(w) * 0.065
			pose.foot_r_rot = cos(w) * 0.065
			pose.rig_rot = 0.055 * sin(w - 0.4)
			if fmod(t, 3.8) > 2.4:
				pose.expression = &"happy"
	return pose
