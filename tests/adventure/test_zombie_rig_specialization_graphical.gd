extends SceneTree
## 原生混合树逐步对照；不冻结、跳过或重新实现任何原生动画事件。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert("battle-perf-next" in OS.get_user_data_dir())
	var registry = root.get_node("Global").character_registry
	var specialization: Script = load("res://scripts/character/zombie/zombie_rig_specialization.gd")
	var max_error: float = 0.0
	for id: int in [1,2,3,5,7]:
		var packed: PackedScene = registry.get_zombie_info(id, CharacterRegistry.ZombieInfoAttribute.ZombieScenes)
		var a = packed.instantiate()
		var b = packed.instantiate()
		var player: AnimationPlayer = b.get_node("AnimationPlayer")
		var branches: Array[StringName] = specialization.unused_branches(b)
		assert(not branches.is_empty(), "known rig eligibility "+str(id))
		var old: AnimationLibrary = player.get_animation_library(&"")
		var optimized: AnimationLibrary = specialization.compile(old,branches)
		assert(optimized!=old)
		player.remove_animation_library(&"")
		player.add_animation_library(&"",optimized)
		a.character_init_type=1
		b.character_init_type=1
		var ta: AnimationTree = a.get_node("AnimationTree")
		var tb: AnimationTree = b.get_node("AnimationTree")
		ta.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		tb.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		seed(42)
		root.add_child(a)
		seed(42)
		root.add_child(b)
		a.is_idle=false
		b.is_idle=false
		var paths: Array[NodePath] = []
		for n: Node in a.get_node("Body/BodyCorrect").find_children("*","Node2D",true,false):
			paths.append(a.get_path_to(n))
		for step: int in 720:
			if step == 120 or step == 300:
				var rate: float = 0.0 if step == 120 else 1.3
				ta.set("parameters/TimeScale/scale",rate)
				tb.set("parameters/TimeScale/scale",rate)
			elif step == 150:
				ta.set("parameters/TimeScale/scale",2.0)
				tb.set("parameters/TimeScale/scale",2.0)
			elif step == 240 or step == 360:
				a.is_attack=step==240
				b.is_attack=step==240
			elif step == 480 or step == 540:
				a.is_swimming=step==480
				b.is_swimming=step==480
			elif step == 600:
				a.is_death=true
				b.is_death=true
			ta.advance(1.0/60.0)
			tb.advance(1.0/60.0)
			for path: NodePath in paths:
				var x: Node2D = a.get_node_or_null(path)
				var y: Node2D = b.get_node_or_null(path)
				if x==null or y==null: continue
				assert(x.is_visible_in_tree()==y.is_visible_in_tree(),"visibility "+str(path))
				if x.is_visible_in_tree() or x.name==&"_ground":
					var u: Transform2D=x.transform
					var v: Transform2D=y.transform
					var err: float=maxf(u.origin.distance_to(v.origin),maxf(u.x.distance_to(v.x),u.y.distance_to(v.y))*50.0)
					max_error=maxf(max_error,err)
					assert(err<0.001,"visible pose "+str(id)+" "+str(step)+" "+str(path)+" err="+str(err))
					if x is Sprite2D:
						assert(x.texture==y.texture,"texture identity "+str(path))
		print("PASS RIG_VISIBLE_POSE ",id," samples=720 max_error=",max_error)
		a.free()
		b.free()
		await process_frame
	print("PASS RIG_SPECIALIZATION")
	quit()
