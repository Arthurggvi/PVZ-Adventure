## 造冰车持续碾压并铺冰，爆胎后停车播放原版翻车动作。
extends Zombie000Base
class_name Zombie013Zamboni

## 地刺扎破轮胎后，经过 280 个初代逻辑刻再爆炸。
const FLAT_TIRE_SECONDS := 2.8
## 辣椒融化冰道后仍存活时，用同一场景继续铺冰。
const ICE_ROAD_SCENE := preload("res://scenes/item/game_scenes_item/ice_road.tscn")

## 车体严重损伤或爆胎时的烟雾。
@onready var smoke: GPUParticles2D = %Smoke
## 普通击毁和爆胎后的爆炸美术。
@onready var death_bomb: ZamboniDeathBomb = $Body/DeathBomb
## 当前车道的冰面，由战场背景持有并在车离场后融化。
@onready var ice_road: IceRoad = $IceRoad
## 车尾的本地位置，用于计算包含小僵尸缩放的铺冰点。
@onready var _ice_offset: Vector2 = ice_road.position
## 车体动画，爆胎时切到两种翻车动作之一。
@onready var _animation_tree: AnimationTree = $AnimationTree

## 是否已被地刺扎破轮胎，防止同一辆车多次消耗地刺王。
var is_caltrop := false
## 当前道路右缘的世界 X 坐标，用于按入场深度减速。
var _right_edge := 0.0
## 越过该世界 X 坐标后保持最低车速。
var _slowdown_end := 0.0
## 冰道允许到达的最左世界坐标，屋顶只铺在右侧平面。
var _ice_limit := 0.0
## 爆胎后剩余的表演时间，单位为游戏秒。
var _flat_tire_remaining := 0.0

## 初始化受损美术和冰道退出回调。
func ready_norm_signal_connect() -> void:
	super()
	hp_stage_change_component.signal_hp_stage_change.connect(_on_damage_stage_changed)
	tree_exiting.connect(_retire_ice)

## 根据当前行的真实格子位置设置车速变化和冰道边界。
func ready_norm() -> void:
	super()
	# cells 是按列排序的真实种植格，兼容不同地图的行长度。
	var cells: Array[PlantCell] = Global.main_game.board.row_cells(lane)
	_right_edge = global_position.x
	_slowdown_end = _right_edge - 300.0
	_ice_limit = _right_edge - 900.0
	if not cells.is_empty():
		_right_edge = cells[-1].global_position.x + cells[-1].size.x
		_slowdown_end = lerpf(cells[0].global_position.x, _right_edge, 0.5)
		_ice_limit = cells[0].global_position.x - cells[0].size.x * 0.5
		if is_instance_valid(Global.main_game.main_game_slope):
			_ice_limit = cells[mini(5, cells.size() - 1)].global_position.x
	_register_ice()

## 展示场景只显示车身。
func ready_show() -> void:
	super()
	ice_road.hide()

## [param delta] 是游戏帧的秒数，用来推进爆胎表演。
func _process(delta: float) -> void:
	if is_show or not is_instance_valid(Global.main_game):
		return
	if is_death:
		if _flat_tire_remaining > 0.0:
			_flat_tire_remaining -= delta
			if _flat_tire_remaining <= 0.0:
				_explode()
		return
	# progress 是当前车身离开行中点的比例，范围 0 至 1。
	var progress: float = clampf(inverse_lerp(_slowdown_end, _right_edge, global_position.x), 0.0, 1.0)
	move_component.update_only_move_speed(lerpf(0.4, 1.0, progress))
	if not is_instance_valid(ice_road):
		ice_road = ICE_ROAD_SCENE.instantiate() as IceRoad
		add_child(ice_road)
		_register_ice()
	ice_road.extend_to(maxf(_ice_limit, to_global(_ice_offset).x - 28.0 * absf(global_scale.x)))

## 把冰道从车身移到关卡背景，并固定在本行右侧。
func _register_ice() -> void:
	ice_road.position = _ice_offset
	ice_road.reparent(Global.main_game.background_manager.background)
	ice_road.global_position.x = maxf(_right_edge, ice_road.global_position.x)
	ice_road.ice_road_init(lane)

## 冰车停止铺设后，冰道仍保留原版的融化时长。
func _retire_ice() -> void:
	if is_instance_valid(ice_road) and not ice_road.is_queued_for_deletion():
		ice_road.start_disappear_timer()

## [param stage] 为受损阶段，重损时开始冒烟。
func _on_damage_stage_changed(stage: int) -> void:
	if stage == 1 and not is_caltrop:
		smoke.emitting = true

## 普通击毁时爆炸。灰烬伤害沿用通用灰烬入口，爆胎则等待动作播放。
func character_death() -> void:
	# already_removed 标识小推车或关卡清理等已经直接结束角色的入口。
	var already_removed: bool = is_death
	super()
	_retire_ice()
	move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDeath)
	if not already_removed and not is_caltrop and is_can_death_language:
		_explode.call_deferred()

## 在伤害回调结束后播放爆炸，随后释放车身。
func _explode() -> void:
	if is_queued_for_deletion():
		return
	death_bomb.activate_it()
	SoundManager.play_character_SFX(&"explosion")
	queue_free()

## 地刺使车体立即失去碾压能力，车身播放损毁和爆胎动作后爆炸。
func be_caltrop() -> void:
	if is_death or is_caltrop:
		return
	is_caltrop = true
	# use_long_wheelie 保留原版车已深入场地时四分之一概率触发的翻车变体。
	var use_long_wheelie: bool = global_position.x < lerpf(_slowdown_end, _right_edge, 0.67) and randi_range(0, 3) == 0
	# playback 是车身动画状态机的播放控制。
	var playback: AnimationNodeStateMachinePlayback = _animation_tree.get("parameters/StateMachine/playback")
	playback.start(&"Zombie_zamboni_wheelie2" if use_long_wheelie else &"Zombie_zamboni_wheelie1")
	smoke.emitting = not use_long_wheelie
	_flat_tire_remaining = FLAT_TIRE_SECONDS
	SoundManager.play_character_SFX(&"balloon_pop")
	hp_component.Hp_loss_death()

## [param _time] 为减速秒数，造冰车免疫寒冷。
func be_ice_decelerate(_time: float) -> void:
	pass

## [param _time] 为冻结秒数，[param _new_time_ice_end_decelerate] 为解冻后的减速秒数。
func be_ice_freeze(_time: float, _new_time_ice_end_decelerate: float) -> void:
	pass

## [param _butter_time] 为黄油停顿秒数，造冰车免疫黄油。
func be_butter(_butter_time: float = 4.0) -> void:
	pass

## 造冰车不会改变行驶阵营。
func be_hypno() -> void:
	pass
