extends SceneTree
## 图鉴窗口的目录虚拟化和Boss独立头像验收，不读写玩家进度。
func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for index: int in count:
		await process_frame

func _fill(directory: Control) -> int:
	var count: int = 0
	for index: int in 100:
		var id: int = directory.next_portrait_id()
		if id == 0:
			break
		directory.draw_portrait(id,true)
		count += 1
		await process_frame
	return count

func _run() -> void:
	assert("performance" in OS.get_user_data_dir())
	var script: Script = load("res://scripts/adventure/ui/almanac_directory.gd")
	var directory: Control = script.new()
	root.add_child(directory)
	var boss_data: Script = load("res://scripts/adventure/ui/boss_almanac_data.gd")
	var presenter: RefCounted = load("res://scripts/adventure/ui/almanac_resource_presenter.gd").new()
	directory.rebuild(boss_data.rows(),"boss","")
	await _frames(4)
	for id: int in boss_data.TYPES:
		var paths: PackedStringArray = presenter._required_paths("boss",id,1,false)
		assert(paths.size() == 1,"portrait-only resource list")
		assert(boss_data.portrait(id) != null,"independent boss portrait")
		directory.draw_portrait(id,true)
	assert(not ResourceLoader.has_cached("res://scenes/character/zombie_boss/cailleach_visual.tscn"),"portrait must not retain animation")
	assert(not ResourceLoader.has_cached("res://scenes/character/zombie_boss/zombie_boss_006_cailleach.tscn"),"portrait must not retain battle scene")
	var entries: Array[Dictionary] = []
	# 原版稳定植物身份，构造真实静态卡面但不改变任何发现记录。
	for id: int in range(1,25):
		entries.append({"type_id":id,"title":"Plant "+str(id)})
	directory.rebuild(entries,"plant","")
	await _frames(5)
	var first: int = await _fill(directory)
	var first_ids: Array = directory._portraits.keys()
	assert(first > 0 and first < entries.size())
	var scroll: ScrollContainer = directory._scroll
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _frames(4)
	var last: int = await _fill(directory)
	assert(last > 0 and not directory._portraits.has(first_ids.front()),"offscreen portrait release")
	directory.reset_scroll()
	await _frames(4)
	assert(await _fill(directory)>0 and directory._portraits.has(first_ids.front()),"reconstruct after return")
	print("PASS ALMANAC RESIDENCY first=",first," last=",last," retained=",directory._portraits.size())
	directory.queue_free()
	await _frames(8)
	quit()
