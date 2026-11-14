extends Node
## --scenario=technical_all / technical_lifecycle / technical_flick / technical_zone
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
var launches: Array[Dictionary] = []
func check(label: String, ok: bool, detail := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test technical_%s %s %s" % [label,"PASS" if ok else "FAIL",detail])
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func run_all(which: String) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	at.set("scenario_running",true);at.set("max_time",1e9)
	gm.profile.tutorial.handled=true
	gm.flicked.connect(func(tier: String, _mult: float) -> void: launches.append({"tier":tier,"v":gm.robot.linear_velocity,"p":gm.robot.position}))
	if which in ["technical_all","technical_lifecycle"]: await lifecycle()
	if which in ["technical_all","technical_flick"]: await flick()
	if which in ["technical_all","technical_zone"]: await zone()
	gm.go_menu();gm.continue_offers_enabled=false;gm.require_flick_tap_in_autotest=false
	await frames(3) # Flush queued scene teardown before the harness quits.
	print("AT|tests passed=%d failed=%d" % [passed,failed])
func start(mode: StringName=&"free", node: String="r2") -> void:
	gm.go_menu();gm.mode=mode;gm.node_id=node;gm.profile.ensure_campaign_start(node)
	gm.start_run();await frames(3)
	if gm.ui.awareness.visible:gm.ui.awareness.confirm.pressed.emit()
	await frames(3)
	gm.hand.playing=false;gm._on_flick(Vector2.ZERO)
func quiet() -> bool:
	return not gm.ui.continue_card.visible and gm.ui.continue_card.stage=="done" and not get_tree().paused and not gm._valid_continue()
func lifecycle() -> void:
	gm.continue_offers_enabled=true
	gm.profile.coins=599
	await start();gm.distance_m=100;gm._finish("Робот остановился")
	check("completed_not_eligible_after_reward",gm.state==GameManager.State.RESULT and gm.profile.coins>=600 and not gm.can_offer_continue())
	gm.open_campaign_map()
	check("map_no_attempt_owner",gm.attempt==null and not gm.can_offer_continue())
	check("late_offer_rejected_on_map",not gm._offer_continue("late old end") and quiet())
	for i in 40:
		gm.profile.coins=2000
		await start(&"campaign" if i%2==0 else &"free","r%d"%(2+i%4))
		var owner := gm.attempt;var epoch := gm._run_epoch;var old_robot := gm.robot
		gm._finish("Робот остановился")
		check("cycle_%02d_valid_offer"%i,gm._valid_continue() and get_tree().paused)
		var old_accept := gm._offer_accept;var old_decline := gm._offer_decline
		if i%4==0:
			gm._last_restart_ms=-100000;check("restart_from_offer_%d"%i,gm.restart_attempt())
		elif i%4==1:gm.open_campaign_map()
		elif i%4==2:gm.go_menu()
		else:
			gm.decline_continue()
			if gm.state==GameManager.State.WAIT:
				for c in gm.race.competitors:c.finished=true
				gm._finish_campaign()
			check("finalized_%d"%i,not gm.can_offer_continue() and quiet())
			gm.open_campaign_map()
		check("cycle_%02d_exit_clears_offer"%i,quiet())
		# Cross the actual level-selection / character-selection path before starting again.
		gm.open_campaign_map();gm._on_node_start("r2");gm._on_select_play(gm.profile.selected)
		await frames(3)
		if gm.ui.awareness.visible:gm.ui.awareness.confirm.pressed.emit()
		await frames(3);gm.hand.playing=false;gm._on_flick(Vector2.ZERO)
		var balance := gm.profile.coins
		old_accept.call_deferred();old_decline.call_deferred()
		gm._finish.call_deferred("old end",epoch)
		# Old queued HUD and robot signal delivery must not damage the new state.
		if is_instance_valid(old_robot):old_robot.rocket_launched.emit(null)
		await frames(3)
		check("cycle_%02d_new_run_rejects_stale"%i,gm.state==GameManager.State.RUN and quiet() and gm.profile.coins==balance and gm.attempt!=owner)
		# Also reject callbacks from an OLD offer while a NEW valid offer is on screen.
		gm._finish("Робот остановился");old_accept.call();old_decline.call()
		check("cycle_%02d_offer_owner"%i,gm._valid_continue() and gm.profile.coins==balance and not gm._continue_used)
		gm.go_menu()
	gm.profile.coins=1800;await start();var attempt_before:=gm.attempt
	gm._max_x=3000;gm.distance_m=30
	gm._finish("Робот остановился")
	var card:=gm.ui.continue_card
	card._process(1);card.yes.pressed.emit();card._process(1);card.confirm_no.pressed.emit()
	check("confirmation_cancel_no_spend",gm.profile.coins==1800 and card.stage=="offer" and gm._valid_continue())
	card._process(1);card.yes.pressed.emit();card._process(1);card.confirm_yes.pressed.emit();card.confirm_yes.pressed.emit()
	check("legitimate_600_once",gm.profile.coins==1200 and gm._continue_used and gm.attempt==attempt_before and gm.state==GameManager.State.RUN and quiet())
	check("restore_80_percent_safe_protected",is_equal_approx(gm.robot.damage.health,gm.robot.damage.max_health*.8) and gm.respawn_ok(gm.robot.position.x) and gm.robot.damage.invulnerable_left>=2.4 and gm.robot.damage.limbs_remaining.size()==4)
	var reloaded:=ProfileStore.new(gm.profile.path,gm.catalog);reloaded.load_data()
	check("purchase_persisted",reloaded.coins==1200)
	check("no_second_purchase",not gm.accept_continue())
	gm._finish("Робот остановился")
	check("once_per_run",gm.state==GameManager.State.RESULT and quiet())
	gm.go_menu();check("menu_late_end_no_effect",not gm._offer_continue("old end") and quiet())
	gm.continue_offers_enabled=false
func touch(pos: Vector2, down: bool, index:=0) -> void:
	var ev:=InputEventScreenTouch.new();ev.index=index;ev.position=pos;ev.pressed=down;Input.parse_input_event(ev)
func flick() -> void:
	gm.continue_offers_enabled=false;gm.require_flick_tap_in_autotest=true
	var worst:=INF;var best:=0.0
	for id in ["tin","hopper","heavy","rocket","samurai"]:
		if not gm.profile.owned.has(id):gm.profile.owned.append(id)
		gm.profile.select(id)
		for k in 8:
			gm.go_menu();gm.debug_track_seed=4100+k;gm.mode=&"free" if k<4 else &"campaign";gm.node_id="r2"
			gm.start_run();await frames(3)
			if gm.ui.awareness.visible:gm.ui.awareness.confirm.pressed.emit()
			await frames(3)
			var tier: String=["MINIMUM","NORMAL","STRONG","MAXIMUM"][k%4]
			gm.ui.flick_bar._phase=FlickPowerBar.ratio_for_tier(tier);gm.ui.flick_bar.marker_ratio=gm.ui.flick_bar._phase
			var before:=launches.size();var x0:=gm.robot.position.x
			touch(Vector2(600,500),true);await frames(2);touch(Vector2(600,500),true,1)
			await frames(12)
			touch(gm.ui.abandon_button.get_global_rect().get_center(),false)
			touch(gm.ui.restart_button.get_global_rect().get_center(),false,1)
			await frames(30)
			var dx:=gm.robot.position.x-x0;worst=minf(worst,dx);best=maxf(best,dx)
			var correct:=launches.size()==before+1
			if correct:correct=absf((launches[-1].v as Vector2).length()-gm.launch_speed*2*FlickPowerBar.multiplier_for_tier(tier))<.1
			check("flick_%s_%d"%[id,k],correct and dx>250 and not gm.robot.freeze and not gm.robot.sleeping and not gm.input.holding and gm.state==GameManager.State.RUN,"dx=%.1f tier=%s launches=%d actual=%s"%[dx,tier,launches.size()-before,str(launches[-1]) if launches.size()>before else "none"])
			gm._notification(NOTIFICATION_APPLICATION_PAUSED);gm._notification(NOTIFICATION_APPLICATION_RESUMED)
			check("resume_%s_%d"%[id,k],not gm.input.holding and not get_tree().paused)
	print("AT|flick_matrix 40 real-touch launches dx_range=%.2f..%.2f flick=%.0f"%[worst,best,gm.settings.get_value("flick")])
	gm.go_menu();gm.require_flick_tap_in_autotest=false
func zone() -> void:
	gm.continue_offers_enabled=false;gm.debug_biome="zone";gm.mode=&"free"
	var count:=0;var sampled_names:={};var max_error:=0.0;var up:=0;var down:=0
	for seed in [101,202,303,404,505,606]:
		gm.go_menu();gm.mode=&"free";gm.debug_track_seed=seed;gm.start_run();await frames(4);gm.hand.playing=false
		gm.terrain.ensure_ahead(65000)
		var points_before:=gm.terrain.points.duplicate()
		for cx in [2500.0,6000.0,12000.0,24000.0,42000.0]:
			for zoom in [.34,.6,.9]:
				var size:=Vector2(1280,720);var cam:=Vector2(cx,gm.terrain.surface_y(cx)-300)
				var tr:=Transform2D(0,Vector2.ONE*zoom,0,size*.5-cam*zoom)
				var items:=BiomePainter.zone_layout(size,cam,tr,gm.terrain)
				for item in items:
					var projected: Vector2=tr*gm.terrain.to_global(Vector2(item.world_x,gm.terrain.surface_y(item.world_x)))
					var anchor: Vector2=item.rect.position+item.anchor*item.scale
					max_error=maxf(max_error,anchor.distance_to(projected));count+=1;sampled_names[item.name]=true
					# Independent screen-space foot samples catch corner float on steep slopes.
					var foot: Vector2=BiomePainter.ZONE_FOOT_SPANS[item.name]
					for j in 17:
						var sx: float=item.rect.position.x+lerpf(foot.x,foot.y,j/16.0)*item.scale
						var wx: float=(tr.affine_inverse()*Vector2(sx,0)).x
						var sy: float=(tr*Vector2(wx,gm.terrain.surface_y(wx))).y
						max_error=maxf(max_error,sy-anchor.y)
					var slope:=gm.terrain.surface_y(item.world_x+20)-gm.terrain.surface_y(item.world_x-20)
					up+=int(slope<0);down+=int(slope>0)
		check("zone_seed_%d_grounded"%seed,max_error<.02 and gm.terrain.points==points_before,"max_error=%.6f"%max_error)
		if seed in [101,303,505]:
			gm.camera.enabled=false;gm.ui.visible=false
			for cx in [6000.0,24000.0]:
				var cam:=Vector2(cx,gm.terrain.surface_y(cx)-200)
				gm.get_viewport().canvas_transform=Transform2D(0,Vector2.ONE*.6,0,Vector2(640,360)-cam*.6)
				await frames(3);at.call("_shot","zone_%d_%d"%[seed,int(cx)])
			gm.camera.enabled=true;gm.ui.visible=true
	check("zone_many_slopes_all_assets",count>500 and up>20 and down>20 and sampled_names.size()==BiomePainter.ZONE_SKYLINE.size(),"count=%d uphill=%d downhill=%d names=%d"%[count,up,down,sampled_names.size()])
	gm.debug_biome="";gm.debug_track_seed=-1;gm.go_menu()
