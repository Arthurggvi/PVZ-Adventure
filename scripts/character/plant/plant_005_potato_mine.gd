extends Plant000Base
class_name Plant005PotatoMine

## 出土后才启用的踩雷检测组件。
@onready var detect_component: DetectComponent = $DetectComponent
## 负责同一行爆炸伤害与表现的组件。
@onready var bomb_component: BombComponentBase = $BombComponent
## 从种下到开始出土的变速计时器。
@onready var prepare_timer: SpeedTimer = $PrepareTimer

## 开始出土前的埋伏时间，单位为正常倍率下的秒。
@export var prepare_time := 15.0

@export_group("动画状态")
## 埋伏计时已结束，动画树可以开始播放出土动画。
@export var is_prepare_end := false


## 初始化正常出战角色
func ready_norm() -> void:
	super()
	## 土豆雷默认禁用攻击射线检测组件
	detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Prepare)
	## 默认禁用眨眼组件
	blink_component.disable_component(ComponentNormBase.E_IsEnableFactor.Prepare)

	# 已有速度因素先同步；在零速下种植也能保留完整准备任务。
	update_prepare_speed(GlobalUtils.get_dic_product(influence_speed_factors))
	if is_zombie_mode:
		_on_prepare_timer_timeout()
	else:
		prepare_timer.start_scaled(prepare_time)

## 出战实例在踩雷判定成功时引爆，并把速度变化同步给埋伏计时器。
func ready_norm_signal_connect() -> void:
	super()
	detect_component.signal_can_attack.connect(_detonate)
	signal_update_speed.connect(update_prepare_speed)

## 踩雷成功后引爆并移除土豆雷；被吃掉、碾压或铲除走普通死亡流程。
func _detonate() -> void:
	if is_death or is_queued_for_deletion() or not detect_component.is_enabling \
			or not bomb_component.is_enabling or bomb_component.is_bomb:
		return
	bomb_component.bomb_once()
	character_death()

## 出土动画结束后才允许出战实例踩雷；展示实例只恢复眨眼。
func _rise_end() -> void:
	if is_death or is_queued_for_deletion():
		return
	if character_init_type == E_CharacterInitType.IsNorm:
		detect_component.enable_component(ComponentNormBase.E_IsEnableFactor.Prepare)
	blink_component.enable_component(ComponentNormBase.E_IsEnableFactor.Prepare)

## 埋伏结束后启动出土动画，并播放泥土和出土音效。
func _on_prepare_timer_timeout() -> void:
	if is_prepare_end or is_death or is_queued_for_deletion():
		return
	is_prepare_end = true
	# 复用出土表现，随植物一起定位到草坪或屋顶格子。
	var dirt_effect: DirtRiseEffect = SceneRegistry.DIRT_RISE_EFFECT.instantiate()
	add_child(dirt_effect)
	dirt_effect.start_dirt()

## [param new_prepare_time] 新的埋伏时长，单位为正常倍率下的秒；从头开始计时。
func set_prepare_time(new_prepare_time: float) -> void:
	prepare_time = new_prepare_time
	prepare_timer.start_scaled(prepare_time)

## [param speed_factor] 埋伏计时倍率；0 暂停进度，恢复时继续计时。
func update_prepare_speed(speed_factor: float) -> void:
	prepare_timer.set_speed_scale(speed_factor)
