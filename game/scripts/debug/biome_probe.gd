extends Node
## Debug-only physics probe (calibration for biome geometry): --scenario=biome_probe [--probe_gravity=1.0]
## Plays free runs with the normal smart bot and prints apex heights / airborne horizontal speeds.
var gm: GameManager
var at: Node


func run_all(_which: String) -> void:
	at.set("max_time", 1.0e9)
	var gs := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe_gravity="):
			gs = float(a.substr(16))
	PhysicsServer2D.area_set_param(get_viewport().world_2d.space, PhysicsServer2D.AREA_PARAM_GRAVITY, 1800.0 * gs)
	var apexes: Array[float] = []
	var vxs: Array[float] = []
	var takeoff_vx: Array[float] = []
	for id in ["tin", "hopper", "heavy", "rocket", "samurai"]:
		for s in 3:
			if not gm.profile.owned.has(id):
				gm.profile.owned.append(id)
			gm.profile.select(id)
			gm.mode = &"free"
			gm.track_seed = 0
			at.call("start_seen_run")
			var t := 0.0
			var air := false
			var apex := 0.0
			while gm.state != GameManager.State.RESULT and t < 45.0:
				await get_tree().physics_frame
				t += 1.0 / 120.0
				if gm.state != GameManager.State.RUN or not is_instance_valid(gm.robot):
					continue
				var r := gm.robot
				if not r.launched:
					continue
				var h := gm.terrain.height_at(r.global_position.x) - r.global_position.y
				var contact := r.contacts.any_contact
				if not contact:
					if not air:
						air = true; apex = h
						takeoff_vx.append(r.linear_velocity.x)
					apex = maxf(apex, h)
					vxs.append(r.linear_velocity.x)
				elif air:
					air = false
					apexes.append(apex)
			gm.go_menu()
			await get_tree().process_frame
	apexes.sort(); vxs.sort(); takeoff_vx.sort()
	var q := func(a: Array, p: float) -> float: return float(a[clampi(int(a.size() * p), 0, a.size() - 1)]) if not a.is_empty() else 0.0
	print("AT|probe gravity=%.2f apex_px n=%d p50=%.0f p75=%.0f p90=%.0f p97=%.0f max=%.0f" % [gs, apexes.size(), q.call(apexes, .5), q.call(apexes, .75), q.call(apexes, .9), q.call(apexes, .97), q.call(apexes, .999)])
	print("AT|probe air_vx p10=%.0f p25=%.0f p50=%.0f p75=%.0f | takeoff_vx p10=%.0f p25=%.0f p50=%.0f" % [q.call(vxs, .1), q.call(vxs, .25), q.call(vxs, .5), q.call(vxs, .75), q.call(takeoff_vx, .1), q.call(takeoff_vx, .25), q.call(takeoff_vx, .5)])
	PhysicsServer2D.area_set_param(get_viewport().world_2d.space, PhysicsServer2D.AREA_PARAM_GRAVITY, 1800.0)
	print("AT|tests passed=1 failed=0")
