## 雪橇散队队员的战场惰性准备任务：提前请求资源，逐个子树准备等阶与图集。
## 由现有 ZombieUpdateScheduler 在游戏帧内驱动，不新增全局加载器或线程执行器。
extends RefCounted
class_name BobsledCrewWarmup

## 子队员在权威物种注册表中的场景，必须与 Z1001 现有定义一致。
const SCENE_PATH := "res://scenes/character/zombie/zombie_1001_bobsled_signle.tscn"
## 正在创建外观和图集的四个阶段；一个帧最多消费预算内的若干子树。
enum Stage { IDLE, TIER_PARTS, ATLAS_SETUP, ATLAS_PARTS, PUBLISH }
## 角色与等阶美术沿用项目已有身份，不额外复制任何原图素材。
const MEMBER_TYPE := CharacterRegistry.ZombieType.Z1001BobsledSingle

## 本场的唯一出生和外观缓存管理器。
var _manager: ZombieManager
## 当前异步资源请求返回的共享场景，依赖资源仍由原注册表管理。
var _scene: PackedScene
## 资源是否已经提交异步请求，重复雪橇不会重复加载。
var _requested_scene: bool = false
## 正式请求失败时关闭本次预热，不影响原始同步生成入口。
var _failed: bool = false
## 等待分帧准备的等阶标识，先到的队员优先。
var _queue: Array[StringName] = []
## 防止同一等阶在场内被多辆雪橇重复预热。
var _seen: Dictionary[StringName, bool] = {}
## 进行中等阶，以及尚未进入角色树的暂存样本。
var _tier: StringName = &""
var _sample: Zombie000Base
## 本次独占的完整等阶外观结果，最终交给管理器既有缓存。
var _appearance: AdventureZombieTierArt.PreparedAppearance
## 本次颜色与纹理映射；通过角色等阶目录获取权威资源。
var _textures: Dictionary = {}
## 逐个处理的场景节点；每个子树只在一个阶段内处理一次。
var _children: Array[Node] = []
## 当前图集或等阶编译中待处理的子树索引。
var _cursor: int = 0
## 当前执行阶段；闲置时没有临时实例或图集。
var _stage: Stage = Stage.IDLE

## [param manager] 是此场的 ZombieManager，必须与调用方的出生工厂一致。
func configure(manager: ZombieManager) -> void:
	_manager = manager

## [param tier] 为雪橇实际等阶，子代继承该标识；重复请求立即忽略。
func request(tier: StringName) -> void:
	if _failed or _seen.has(tier):
		return
	_seen[tier] = true
	_queue.append(tier)
	if not _requested_scene:
		_requested_scene = true
		var result: Error = ResourceLoader.load_threaded_request(SCENE_PATH, "PackedScene")
		if result != OK:
			_failed = true # 保留正式 create_norm_zombie 的同步回退。
			_queue.clear()

## 是否有未完成的准备任务；全部完成后现有调度器自动关闭空闲处理。
func has_work() -> bool:
	return not _failed and (_scene == null and _requested_scene or _stage != Stage.IDLE or not _queue.is_empty())

## [param max_usecs] 与当前调度器预算相同；单个原生子树可能略微超时。
## 返回时不会修改已经入场的任何僵尸或改动波次自然刷新统计。
func advance(max_usecs: int) -> void:
	if not has_work() or not is_instance_valid(_manager):
		return
	if _scene == null:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(SCENE_PATH)
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			_failed = true
			return # 异步失败时由原同步出生入口保底。
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			return
		_scene = ResourceLoader.load_threaded_get(SCENE_PATH) as PackedScene
		if _scene == null:
			_failed = true
			return
		# 原注册表从ResourceLoader已完成的缓存中取得同一资源，避免首次散队再次冷加载。
		Global.character_registry.get_zombie_info(MEMBER_TYPE, CharacterRegistry.ZombieInfoAttribute.ZombieScenes)
	var deadline: int = Time.get_ticks_usec() + maxi(500, max_usecs) # 本帧主线程工作上界。
	while Time.get_ticks_usec() < deadline:
		if _stage == Stage.IDLE:
			if _queue.is_empty():
				return
			_start(_queue.pop_front())
			if _stage == Stage.IDLE:
				continue
		if _stage == Stage.TIER_PARTS:
			var changed: bool = AdventureZombieTierArt._apply_tree(
				_children[_cursor], _textures, _sample, _appearance) if not _textures.is_empty() else false
			_appearance.has_tier_art = changed or _appearance.has_tier_art
			_cursor += 1
			if _cursor == _children.size():
				_stage = Stage.ATLAS_SETUP
		elif _stage == Stage.ATLAS_SETUP:
			_make_atlas()
		elif _stage == Stage.ATLAS_PARTS:
			AdventureZombieTierArt._apply_tree(_children[_cursor], _textures, _sample, _appearance)
			_cursor += 1
			if _cursor == _children.size():
				_stage = Stage.PUBLISH
		elif _stage == Stage.PUBLISH:
			_publish()

## 开始 [param tier] 的唯一外观任务；实例不入战斗树，无音效、AI或出生事件。
func _start(tier: StringName) -> void:
	_tier = tier
	_sample = _scene.instantiate() as Zombie000Base
	if _sample == null:
		_stage = Stage.IDLE
		return
	_appearance = AdventureZombieTierArt.PreparedAppearance.new()
	_textures = AdventureZombieTierArtCatalog.textures_for(int(_sample.zombie_type), tier) if tier != &"" else {}
	if not _textures.is_empty():
		_appearance.has_tier_art = AdventureZombieTierArt._apply_body_resources(
			_sample, _textures, _sample, _appearance) # 根实例不属于子树列表，保持与原预备器一致。
	_children = _sample.get_children()
	_cursor = 0
	_stage = Stage.TIER_PARTS

## 使用本场剩余图集预算创建同原版一致的纹理映射；实际像素打包已由现有队列限频。
func _make_atlas() -> void:
	if _manager.periodic_updates.can_pack_sprites():
		var parts: Dictionary = {} # 收集当前外观包含的原始纹理。
		AdventureZombieTierArt._collect_parts(_sample, parts)
		var atlas := ZombieSpriteAtlas.new() # 原有共享图集系统。
		atlas.prepare(parts)
		if not atlas.textures.is_empty():
			_appearance.pending_atlas = atlas
			_textures = atlas.textures
			AdventureZombieTierArt._apply_body_resources(
				_sample, _textures, _sample, _appearance) # 图集映射与根脚本资源保持同步。
			_cursor = 0
			_stage = Stage.ATLAS_PARTS
			return
	_stage = Stage.PUBLISH

## 只在完整外观已准备好时纳入管理器既有缓存，不能覆盖已由实战提前生成的条目。
func _publish() -> void:
	_manager.cache_prepared_bobsled_appearance(_sample, _tier, _appearance)
	_sample.free()
	_sample = null
	_appearance = null
	_children.clear()
	_textures = {} # 解除当前字典引用，不能clear；图集仍共享textures并等待后续分帧上传。
	_stage = Stage.IDLE
