## 管理房门贴图与失败检测；原生临时飞行者只有落地后才能进家。
extends Node2D
class_name MainGameHome

## 房屋失败区域，沿用场景配置的碰撞层与形状。
@onready var area_2d_home: Area2D = $Area2DHome

## 各原版背景对应的门内贴图；无贴图的背景保留空项。
@onready var door_downs: Array[Sprite2D] = [
	$Door/DoorDown/Background1GameoverInteriorOverlay,
	$Door/DoorDown/Background2GameoverInteriorOverlay,
	$Door/DoorDown/Background3GameoverInteriorOverlay,
	$Door/DoorDown/Background4GameoverInteriorOverlay,
	null,
	null
]

## 各原版背景对应的房门遮罩。
@onready var door_masks: Array[Sprite2D] = [
	$Door/DoorMask/Background1GameoverMask,
	$Door/DoorMask/Background2GameoverMask,
	$Door/DoorMask/Background3GameoverMask,
	$Door/DoorMask/Background4GameoverMask,
	$Door/DoorMask/Background5GameoverMask,
	$Door/DoorMask/Background6GameoverMask
]

## 只跟踪进入房屋时仍在原生临时飞行的区域，避免逐帧扫描全部僵尸。
var _airborne_candidates: Array[Area2D] = []
## 失败事件只提交一次，防止同帧多个区域重复触发失败演出。
var _defeat_reported := false
## 立即关闭逻辑检测，物理区域的 monitoring 修改可以安全延后。
var _home_disabled := false

## 无飞行候选时关闭物理回调，并补接离开房屋的清理信号。
func _ready() -> void:
	set_physics_process(false)
	if not area_2d_home.area_exited.is_connected(_on_area_2d_home_area_exited):
		area_2d_home.area_exited.connect(_on_area_2d_home_area_exited)

## 刷新房门贴图，保留进门检测和失败演出所需的节点。
## [param game_BG] 原版背景枚举，用于选择对应的房门和遮罩。
## [param use_original_door] 仅在使用原版背景时显示与之配套的贴图。
func init_home(game_BG: ConstLevelData.GameBg, use_original_door: bool = true) -> void:
	for background_index in door_masks.size(): # 遍历原版背景对应的每组贴图。
		var show_door := use_original_door and background_index == game_BG # 当前贴图组是否与战场背景配套。
		if is_instance_valid(door_downs[background_index]):
			door_downs[background_index].visible = show_door
		door_masks[background_index].visible = show_door

## 检查进入房屋的 [param area]；临时飞行时只登记候选，落地后复核。
func _on_area_2d_home_area_entered(area: Area2D) -> void:
	if not _is_home_active():
		return
	var zombie: Zombie000Base = _get_live_enemy(area) # 仅当前战局的存活敌人能触发失败。
	if zombie == null:
		return
	if zombie.is_native_airborne():
		if not _airborne_candidates.has(area):
			_airborne_candidates.append(area)
		set_physics_process(true)
	elif _overlaps_home_now(area):
		_report_defeat(zombie)

## 按当前形状复核候选，避免落地后没有再次进入信号而漏判；[param _delta] 未使用。
func _physics_process(_delta: float) -> void:
	if not _is_home_active():
		_clear_airborne_candidates()
		return
	for index in range(_airborne_candidates.size() - 1, -1, -1): # 倒序删除已死亡或离开的候选。
		if not is_instance_valid(_airborne_candidates[index]):
			_airborne_candidates.remove_at(index)
			continue
		var area: Area2D = _airborne_candidates[index] # 本次复核的僵尸区域。
		var zombie: Zombie000Base = _get_live_enemy(area) # 无效、友方或离场角色会返回空值。
		if zombie == null or not _overlaps_home_now(area):
			_airborne_candidates.remove_at(index)
		elif not zombie.is_native_airborne():
			_report_defeat(zombie)
			return
	set_physics_process(not _airborne_candidates.is_empty())

## 移除已离开房屋的 [param area]，不保留过期飞行候选。
func _on_area_2d_home_area_exited(area: Area2D) -> void:
	_airborne_candidates.erase(area)
	set_physics_process(not _airborne_candidates.is_empty())

## 仅允许当前仍运行且包含此房屋的战局进行失败判定。
func _is_home_active() -> bool:
	var game: MainGameManager = Global.main_game # 当前战局，用于隔离旧场景和结束后的回调。
	return not _home_disabled and not _defeat_reported and is_inside_tree() \
		and not is_queued_for_deletion() and is_instance_valid(area_2d_home) and area_2d_home.monitoring \
		and is_instance_valid(game) and not game.is_queued_for_deletion() and game.is_ancestor_of(self) \
		and is_instance_valid(game.zombie_manager) and game.zombie_manager.is_game_running()

## 取得 [param area] 所属的存活敌人；调用者先确认房屋属于当前活动战局。
func _get_live_enemy(area: Area2D) -> Zombie000Base:
	if not is_instance_valid(area) or area.is_queued_for_deletion() or not area.is_inside_tree() \
			or not area.monitorable or (area_2d_home.collision_mask & area.collision_layer) == 0:
		return null
	var zombie: Zombie000Base = area.owner as Zombie000Base # 兼容同一僵尸的多个检测区域。
	if not is_instance_valid(zombie) or zombie.is_death or zombie.is_hypno \
			or zombie.is_queued_for_deletion() or zombie.retiring_from_battle \
			or not Global.main_game.is_ancestor_of(zombie):
		return null
	return zombie

## 收集 [param area] 当前启用的直属碰撞形状，实时反映禁用和尺寸变化。
func _get_enabled_shapes(area: Area2D) -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = [] # 返回可参与房屋检测的形状节点。
	for child in area.get_children(): # CollisionShape2D 必须直属物理区域才会参与检测。
		var collision: CollisionShape2D = child as CollisionShape2D # 排除贴图及其他辅助节点。
		if collision != null and not collision.disabled and collision.shape != null \
				and not collision.is_queued_for_deletion():
			shapes.append(collision)
	return shapes

## 用 [param area] 和房屋的即时全局变换求交，不依赖上一次物理帧的重叠缓存。
func _overlaps_home_now(area: Area2D) -> bool:
	var enemy_shapes: Array[CollisionShape2D] = _get_enabled_shapes(area) # 该区域可用的受检形状。
	for home_shape in _get_enabled_shapes(area_2d_home): # 房屋可以由多个形状组成。
		for enemy_shape in enemy_shapes: # 任意一对形状相交即仍位于房屋内。
			if home_shape.shape.collide(home_shape.global_transform, enemy_shape.shape, enemy_shape.global_transform):
				return true
	return false

## 返回房屋实际检测区域的最右边界，禁用或无有效形状时返回负无穷。
func get_defeat_front_x() -> float:
	if _home_disabled or not is_instance_valid(area_2d_home) or not area_2d_home.monitoring:
		return -INF
	var front_x: float = -INF # 累积所有有效形状在世界坐标下的最右边界。
	for collision in _get_enabled_shapes(area_2d_home): # 每个形状使用自己的即时全局变换。
		var bounds: Rect2 = collision.shape.get_rect() # 形状局部包围矩形，兼容不同形状尺寸。
		for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y),
				bounds.end, Vector2(bounds.position.x, bounds.end.y)]: # 四角都转换以兼容旋转和翻转。
			front_x = maxf(front_x, (collision.global_transform * corner).x)
	return front_x

## 提交 [param zombie] 的进家事件，先关闭重复提交以防事件处理期间重入。
func _report_defeat(zombie: Zombie000Base) -> void:
	_defeat_reported = true
	_clear_airborne_candidates()
	EventBus.push_event("zombie_go_home", [zombie])

## 清空候选并停止物理回调，供死亡清理、禁用和离树时复用。
func _clear_airborne_candidates() -> void:
	_airborne_candidates.clear()
	set_physics_process(false)

## 离开场景时不保留其他节点的候选引用。
func _exit_tree() -> void:
	_clear_airborne_candidates()

## 立即禁用进家逻辑，延后修改物理监听以兼容区域信号回调。
func disable_home() -> void:
	_home_disabled = true
	_clear_airborne_candidates()
	area_2d_home.set_deferred("monitoring", false)
