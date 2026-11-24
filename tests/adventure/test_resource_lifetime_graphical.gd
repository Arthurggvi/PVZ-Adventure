extends SceneTree
## 图形隔离验收；不修改生产存档。只在真实图形后端比较引擎视频内存。

const Scope = preload("res://scripts/autoload/global/battle_resource_scope.gd")

const IDS = [29,30,31,32,33,34,38,39,40,41]

func _initialize():
	_run.call_deferred()

func _settle():
	for index in range(10):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _memory() -> float:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)/1048576.0

func _check(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL "+label)
		quit(1)
		print("FAIL ",label)
		assert(condition,label)
	print("PASS ",label)

func _run():
	assert("resource-lifetime-test" in OS.get_user_data_dir() or "s1-acceptance" in OS.get_user_data_dir(), "Must isolate user data")
	assert(DisplayServer.get_name() != "headless", "Graphical renderer required")
	print("USER_DIR ",OS.get_user_data_dir())
	Engine.max_fps=60
	var registry = root.get_node("Global").character_registry
	var cards = root.get_node("AllCards")
	await _settle()
	var baseline = _memory()
	var base_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("BASE video=",baseline," nodes=",base_nodes)
	for cycle in range(3):
		for id in IDS:
			var resource = registry.get_zombie_info(id, CharacterRegistry.ZombieInfoAttribute.ZombieScenes)
			_check(resource is PackedScene,"registered "+str(id))
			resource=null
			await process_frame
		await _settle()
		var after = _memory()
		print("REGISTRY_CYCLE ",cycle," video=",after," delta=",after-baseline)
		_check(after <= baseline+20.0,"no progressive registry residency")
	var scope = Scope.new()
	var owner = Node.new()
	root.add_child(owner)
	var path: String = CharacterRegistry.ZombieInfo[30][CharacterRegistry.ZombieInfoAttribute.ZombieScenes]
	var r = scope.resolve(owner,path)
	var rid = r.get_instance_id()
	r=null
	await _settle()
	var retained = _memory()
	r=scope.resolve(owner,path)
	_check(r.get_instance_id()==rid,"battle owner retains identical scene")
	r=null
	owner.queue_free()
	await _settle()
	print("BATTLE_SCOPE retained=",retained," released=",_memory())
	_check(_memory() <= baseline+20.0,"battle owner exit releases lease")
	var ref = ResourceCardReference.create(ResourceCardReference.CardType.Zombie,30)
	var Paths = load("res://scripts/adventure/ui/ui_resource_paths.gd")
	var portrait = Paths.character("zombie",30,1,false)
	var detail = Paths.character("zombie",30,1,true)
	_check(not portrait.has(path) and detail.has(path),"portrait excludes battle scene")
	var card = cards.create_card(ref)
	_check(card != null,"card copy")
	root.add_child(card)
	var preview=cards.create_static_preview(ref)
	_check(preview != null,"preview copy")
	root.add_child(preview)
	for id in [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,27,28,29,30,31,32,33]:
		var template = cards.get_template(ResourceCardReference.create(ResourceCardReference.CardType.Zombie,id))
		_check(template != null,"template "+str(id))
	print("TEMPLATES peak_nodes=",Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	await _settle()
	_check(not cards.is_catalog_materialized(),"temporary templates released")
	_check(is_instance_valid(card) and is_instance_valid(preview),"copies survive release")
	card.queue_free()
	preview.queue_free()
	await _settle()
	var final_nodes=Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("FINAL video=",_memory()," nodes=",final_nodes," baseline_nodes=",base_nodes)
	_check(final_nodes <= base_nodes+8,"no retained template nodes")
	_check(_memory() <= baseline+20.0,"final video budget")
	print("PASS RESOURCE LIFETIME S1")
	quit(0)
