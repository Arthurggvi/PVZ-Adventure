## 独立冒险存档验收；使用唯一临时路径，不接触玩家进度。
extends SceneTree

## 延后执行以等待项目单例初始化。
func _initialize() -> void:
	call_deferred("_run")
	create_timer(15, true, false, true).timeout.connect(func(): quit(1))

## 检查赠卡幂等、胜利持久化、备份与损坏文件保护。
func _run() -> void:
	if not ResourceLoader.exists("res://scripts/adventure/island_progress.gd"):
		push_error("FAIL: 缺少独立冒险状态实现")
		quit(1)
		return
	# 动态加载保证缺少实现时输出明确的验收失败。
	var implementation = load("res://scripts/adventure/island_progress.gd")
	# 每次运行使用唯一目录；全部文件留在测试专用路径。
	var path := "user://phase1_tests/%s/state.json" % Time.get_ticks_usec()
	var progress = implementation.new(path) # 本次测试状态。
	assert(progress.load_progress())
	assert(not progress.started and not progress.stage_1_cleared)
	assert(progress.start_new())
	assert(progress.grant_starter_cards())
	assert(progress.grant_starter_cards())
	assert(progress.cards == {"sunflower": 1, "peashooter": 1})
	assert(progress.complete_intro())
	var resumed = implementation.new(path) # 模拟重启后的独立实例。
	assert(resumed.load_progress())
	assert(resumed.intro_completed and resumed.cards == progress.cards)
	assert(not resumed.stage_1_cleared)
	assert(resumed.record_victory())
	assert(progress.load_progress() and progress.stage_1_cleared)
	assert(progress.start_new())
	assert(not progress.stage_1_cleared and not progress.intro_completed)
	assert(FileAccess.file_exists(progress.last_backup_path))
	var archived = implementation.new(progress.last_backup_path) # 新游戏前的备份。
	assert(archived.load_progress() and archived.stage_1_cleared)
	var corrupt := FileAccess.open(path, FileAccess.WRITE) # 人为损坏测试文件。
	corrupt.store_string("invalid json")
	corrupt.close()
	assert(not resumed.load_progress())
	assert(not resumed.grant_starter_cards())
	assert(FileAccess.get_file_as_string(path) == "invalid json")
	print("PASS: adventure progress persistence, idempotency, backup, corruption protection")
	quit(0)
