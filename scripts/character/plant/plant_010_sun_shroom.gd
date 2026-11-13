## 阳光菇保留原版幼年、成熟和产阳光流程；成熟事件只由本株首次正常成长发出。
extends Plant000Base
class_name Plant010SunShroom

## 本株产阳光组件，幼年与成熟切换只改变每份基础价值。
@onready var create_sun_component: CreateSunComponent = $CreateSunComponent
## 成长使用独立动作计时器，仍响应角色速度和战场暂停。
@onready var grow_timer: SpeedTimer = $GrowTimer

## 正常角色速度下的成长秒数；冻结转职可在入树前缩短。
@export var time_grow: float = 100.0
## 幼年每份阳光价值；出生修饰后持续保留，不在就绪时恢复原值。
@export var mini_sun_value: int = 15
## 成熟每份阳光价值；出生修饰后持续保留，不在成长时恢复原值。
@export var norm_sun_value: int = 25

@export_group("动画状态")
## 本株是否已经成熟；读档恢复此状态不补发成熟技能。
@export var is_grow: bool = false

## 本株首次正常成熟后发出；此时动画状态和阳光价值已经完成切换。
signal signal_matured()

## 初始化正常出战幼体；成熟状态只恢复价值，不重新开始成长。
func ready_norm() -> void:
	super()
	update_grow_speed(GlobalUtils.get_dic_product(influence_speed_factors))
	if is_grow:
		grow_timer.stop()
	else:
		grow_timer.start_scaled(time_grow)
	create_sun_component.change_sun_value(norm_sun_value if is_grow else mini_sun_value)
	if is_zombie_mode:
		create_sun_component.disable_component(ComponentNormBase.E_IsEnableFactor.GameMode)

## 原有角色速度分别同步成长与生产，独立缩短成长时长不加速产阳光。
func ready_norm_signal_connect() -> void:
	super()
	signal_update_speed.connect(update_grow_speed)
	signal_update_speed.connect(create_sun_component.owner_update_speed)

## 首次有效超时才成熟；死亡、展示、重复通知均不触发转职事件。
func _on_grow_timer_timeout() -> void:
	if is_grow or is_death or is_queued_for_deletion() \
			or character_init_type != E_CharacterInitType.IsNorm:
		return
	is_grow = true
	grow_timer.stop()
	create_sun_component.change_sun_value(norm_sun_value)
	signal_matured.emit()

## [param speed_factor] 为角色速度乘积；停止或尚未开始时也保存倍率，由计时器保留进度与零速。
func update_grow_speed(speed_factor: float) -> void:
	grow_timer.set_speed_scale(speed_factor)

## [param _attack_zombie] 是本次啃食者；仅我是僵尸模式沿用原版受击产阳光。
func _be_zombie_eat_once_special(_attack_zombie: Zombie000Base) -> void:
	if is_zombie_mode:
		create_sun_component._on_be_eat_once()

## 死亡前结清我是僵尸模式原版产出；转职储蓄由统一角色死亡事件结算。
func character_death() -> void:
	if is_zombie_mode:
		create_sun_component._on_character_death()
	super()

## 返回包含成熟状态的植物存档；转职技能不通过保存动作重复触发。
func gat_save_game_data_plant() -> Dictionary:
	var save_game_data_plant: Dictionary = super() # 基础生命、睡眠及物种字段。
	save_game_data_plant["is_grow"] = is_grow
	return save_game_data_plant

## [param save_game_data_plant] 是已校验的植物存档；成熟恢复不发成长事件、不再次扩散或减冷却。
func load_game_data_plant(save_game_data_plant: Dictionary) -> void:
	super(save_game_data_plant)
	is_grow = save_game_data_plant.get("is_grow", false)
	if is_grow:
		grow_timer.stop()
	create_sun_component.change_sun_value(norm_sun_value if is_grow else mini_sun_value)

## [param state] 为离树预检存档；缺失成熟字段兼容旧档，存在时必须为布尔值。
func accepts_save_state(state: Dictionary) -> bool:
	return super(state) and (not state.has("is_grow") or state["is_grow"] is bool)
