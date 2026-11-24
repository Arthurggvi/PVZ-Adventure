extends SceneTree
## 独立存档下实战验证装备轨道、灰烬死亡、余血及脱落部件。
func _initialize():
	_run.call_deferred()

func _frames(n:int):
	for i:int in n:
		await process_frame

func _run():
	assert("battle-perf-next" in OS.get_user_data_dir())
	seed(20261124)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var g=root.get_node("Global")
	g.save_service.stop_autosave()
	var level=load("res://resources/adventure/island_lawn.tres").duplicate(true)
	level.is_day=false
	level.look_show_zombie=false
	level.can_choosed_card=false
	level.monster_mode=ConstLevelData.E_MonsterMode.Null
	level.is_day_sun=false
	level.init_tombstone_num=0
	level.start_sun=5000
	level.prechosen_cards.clear()
	level.prechosen_cards.append(ResourceCardReference.create(ResourceCardReference.CardType.Plant,CharacterRegistry.PlantType.P002SunFlower))
	g.game_para=level
	assert(change_scene_to_file("res://scenes/main/MainGame01Front.tscn")==OK)
	var until:int=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<until and (not is_instance_valid(g.main_game) or g.main_game.main_game_progress!=3):
		await process_frame
	var battle=g.main_game
	assert(is_instance_valid(battle) and battle.main_game_progress==3)
	await _frames(30)
	var binding=load("res://scripts/adventure/adventure_zombie_tier_binding.gd")
	var manager=battle.zombie_manager
	var maker=manager.zombie_wave_manager.zombie_wave_create_manager
	print("BOARD rows=",manager.all_zombie_rows.size()," range=",manager.zombie_range_pos_x)
	# Exercise actual normal-battle spawning, original damage and ash ownership.
	var registry=root.get_node("Global").character_registry
	var total:int=0
	var ash_nodes:Array[Node]=[] # 记录独立退场节点，验证完整演出结束后销毁。
	for id:int in [1,2,3,5,6,7,8,11]:
		var z=maker.wave_create_zombie(id,2,-1,Callable(),false,binding.new(&"tier5" if id in [1,3,5] else &"base"))
		assert(is_instance_valid(z),"spawn "+str(id))
		z.global_position.x=700
		await _frames(4)
		var hp=z.hp_component
		assert(not hp.is_physics_processing(),"live HP idle")
		for d:Node in z.get_node("Body/NodeDrop").get_children():
			if d.has_method("acitvate_it"):
				assert(not d.is_physics_processing(),"unspawned drop idle")
		var ash=z.charred_component
		assert(ash.get_node("ZombieCharred/CharredCorrect").get_child_count()==0,"ash deferred "+str(id))
		assert(ash.lazy_visual_scene!=null,"ash scene "+str(id))
		var original:PackedScene=registry.get_zombie_info(id,CharacterRegistry.ZombieInfoAttribute.ZombieScenes)
		var sample:Node=original.instantiate()
		var original_lib:AnimationLibrary=sample.get_node("AnimationPlayer").get_animation_library(&"")
		var current_lib:AnimationLibrary=z.get_node("AnimationPlayer").get_animation_library(&"")
		var old_count:int=0
		var new_count:int=0
		for clip:StringName in original_lib.get_animation_list():
			var a:Animation=original_lib.get_animation(clip)
			var b:Animation=current_lib.get_animation(clip)
			assert(is_equal_approx(a.length,b.length) and a.loop_mode==b.loop_mode,"animation length/loop")
			old_count+=a.get_track_count()
			new_count+=b.get_track_count()
			for track:int in a.get_track_count():
				if a.track_get_type(track)==Animation.TYPE_METHOD:
					var found:int=b.find_track(a.track_get_path(track),Animation.TYPE_METHOD)
					assert(found>=0 and a.track_get_key_count(track)==b.track_get_key_count(found),"method tracks retained")
					for k:int in a.track_get_key_count(track):
						assert(a.track_get_key_time(track,k)==b.track_get_key_time(found,k) and a.track_get_key_value(track,k)==b.track_get_key_value(found,k),"method key preserved")
		sample.free()
		print("TRACKS id=",id," original=",old_count," current=",new_count)
		var parent:Node=z.get_parent()
		for hit:int in 4:
			z.be_bomb(1000000,true)
			if z.is_death: break
		print("ASH_HIT id=",id," dead=",z.is_death," hp=",z.hp_component.curr_hp," parent=",ash.get_parent().name," preserve=",z._preserves_blast_death_animation())
		assert(is_instance_valid(ash) and ash.get_parent()==parent,"ash reparent "+str(id))
		assert(ash.anim_lib!=null and ash.anim_lib.is_playing(),"ash playback "+str(id))
		assert(ash.anim_lib.get_animation(ash.anim_lib_name).get_track_count()>0)
		ash_nodes.append(ash)
		total+=1
		await _frames(2)
		assert(not is_instance_valid(z),"old zombie gone")
	print("PASS ASH_SPAWN count=",total)
	# Direct real death path with threshold remainder; the same four-step decay remains.
	var z=maker.wave_create_zombie(1,2,-1,Callable(),false,binding.new(&"base"))
	assert(z!=null)
	z.global_position.x=700
	await _frames(3)
	var hp=z.hp_component
	var threshold:int=hp.death_hp
	assert(threshold>0)
	hp.curr_hp=threshold
	assert(z.is_death and hp.is_physics_processing(),"death enables decay")
	var before:int=hp.curr_hp
	for index:int in 5:
		await physics_frame
	assert(hp.curr_hp<before,"original decay resumes")
	z.queue_free()
	await _frames(2)
	print("PASS DEATH_HP_GATE")
	var live=maker.wave_create_zombie(1,2,-1,Callable(),false,binding.new(&"base"))
	await _frames(3)
	var drop=live.get_node("Body/NodeDrop/Node2D_Hand_Drop")
	assert(not drop.is_physics_processing())
	drop.acitvate_it()
	assert(drop.is_active and drop.is_physics_processing())
	drop.drop_body.position.y=drop.ground_y
	drop.velocity=Vector2.ZERO
	drop._physics_process(1.0/60.0)
	assert(not drop.is_active and not drop.is_physics_processing() and is_instance_valid(drop._fade_tween),"landing stops physics")
	var fade:Tween=drop._fade_tween
	drop.fade_and_delete()
	assert(drop._fade_tween==fade,"duplicate fade blocked")
	await create_timer(1.2).timeout
	assert(not is_instance_valid(drop),"drop releases")
	var water_drop=live.get_node("Body/NodeDrop/Node2D_Head_Drop")
	assert(not water_drop.is_physics_processing())
	water_drop.acitvate_it()
	water_drop.is_swimming=true
	water_drop.drop_body.position.y=water_drop.ground_y+2.0
	water_drop._physics_process(1.0/60.0)
	assert(is_equal_approx(water_drop.drop_body.position.y,water_drop.ground_y),"water drop clamps to surface")
	assert(not water_drop.is_physics_processing(),"water drop stops")
	await create_timer(1.2).timeout
	assert(not is_instance_valid(water_drop),"water drop releases")
	print("PASS DROP_GATE")
	var ash_deadline:int=Time.get_ticks_msec()+12000
	for ash_node:Node in ash_nodes:
		while is_instance_valid(ash_node) and Time.get_ticks_msec()<ash_deadline:
			await process_frame
		assert(not is_instance_valid(ash_node),"ash animation completed and released")
	print("PASS ASH_RELEASE")
	battle.queue_free()
	await _frames(10)
	print("PASS BATTLE_NATIVE_OPTIMIZATION")
	quit()
