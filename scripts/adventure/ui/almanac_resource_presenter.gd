## 图鉴窗口私有准备队列；批次资源仅持有至当前同步画面装配完成。
extends RefCounted

## 路径解析只展开当前角色或当前预览所需资源。
const Paths = preload("res://scripts/adventure/ui/ui_resource_paths.gd")
## 与场景转换和工具栏共用的线程资源批次。
const ResourceBatch = preload("res://scripts/ui/transitions/resource_load_batch.gd")
## Boss 头像、动作和专属舞台的资源路径。
const BossData = preload("res://scripts/adventure/ui/boss_almanac_data.gd")
## Buff 的只读资料用于描述当前演示。
const BuffData = preload("res://scripts/adventure/ui/buff_almanac_data.gd")
## Buff 演示只声明自身路径，不预加载全部目录。
const BuffPreview = preload("res://scripts/adventure/ui/buff_almanac_preview.gd")
## 当前唯一准备批次；取消时移交工具栏异步回收。
var _batch: ResourceBatch
## 完成时原样交回宿主校验的分类、编号、阶级与修订身份。
var _job: Dictionary = {}

## 只声明图鉴首屏公共皮肤；按钮状态包含阶级和演示控制，角色资源仍按需准备。
static func initial_resource_paths() -> PackedStringArray:
	var paths: PackedStringArray = Paths.frame() # 公共面板与关闭按钮。
	paths.append_array(Paths.skin(PackedStringArray(["controls/search_field.png", "icons/search_magnifier.png",
		"res://assets/adventure/ui/bottom_bar/icons/icon_deck.png"]), PackedStringArray(["tabs/tab", "slots/plant_slot", "buttons/button"])))
	return paths

## 返回是否仍需轮询当前批次；不会同步等待资源。
func is_busy() -> bool:
	return _batch != null

## 准备 [param kind]、[param type_id]、[param tier] 的资源；[param detail] 区分详情和头像，[param revision] 由宿主校验。
## 缓存命中或启动失败时立即返回结果，否则返回空字典并等待 [method poll]。
func request(kind: String, type_id: int, tier: int, detail: bool, revision: int) -> Dictionary:
	var key: String = "%s:%d:%d:%s" % [kind, type_id, tier, "detail" if detail else "portrait"] # 详情可比头像多依赖，不能共用准备标记。
	_job = {"key": key, "kind": kind, "type_id": type_id, "tier": tier, "detail": detail, "revision": revision}
	_batch = ResourceBatch.new()
	if _batch.start(_required_paths(kind, type_id, tier, detail)) != OK:
		AdventureToolbar.retire_resource_batch(_batch)
		_batch = null
		return _finish(false)
	return {}

## 查询一次当前批次；未完成返回空字典，完成返回原请求身份和 loaded 标记。
func poll() -> Dictionary:
	if _batch == null:
		return {}
	var status: int = _batch.poll() # 仅在批次报告完成后读取已有结果。
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return {}
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_job["resources"] = _batch.resources.duplicate() # 交付字典只在同步构造期间持有资源。
	_batch = null
	return _finish(status == ResourceLoader.THREAD_LOAD_LOADED)

## 撤销旧结果交付并移交在途请求；不会在主线程等待。
func cancel() -> void:
	if _batch != null:
		AdventureToolbar.retire_resource_batch(_batch)
		_batch = null
	_job = {}

## 窗口离场时撤销请求，实际画面随窗口释放。
func dispose() -> void:
	cancel()

## 将 [param loaded] 附加到当前请求的独立结果，再清空待交付身份。
func _finish(loaded: bool) -> Dictionary:
	var result: Dictionary = _job.duplicate() # 返回值不随下一次请求改变。
	result["loaded"] = loaded
	_job = {}
	return result

## 返回 [param kind]、[param type_id]、[param tier] 所需路径；[param detail] 为 false 时 Buff 不需要任何资源。
func _required_paths(kind: String, type_id: int, tier: int, detail: bool) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray() # 保持批次只包含此次实际会呈现的资源。
	if kind == "buff":
		return BuffPreview.required_resource_paths(BuffData.profile(type_id)) if detail else paths
	if kind != "boss":
		return Paths.character(kind, type_id, tier, detail)
	Paths.append(paths, str(BossData.PORTRAITS.get(type_id, "")))
	if not detail:
		return paths
	Paths.append(paths, str(CharacterRegistry.ZombieBossInfo.get(type_id, {}).get(CharacterRegistry.ZombieBossInfoAttribute.BossScenes, "")))
	Paths.append(paths, str(BossData.VISUALS.get(type_id, "")))
	if detail:
		match type_id:
			BossData.LANTERN: Paths.append(paths, BossData.LANTERN_STAGE)
			BossData.SAVIOR: Paths.append(paths, BossData.SAVIOR_STAGE)
	return paths
